#!/bin/bash
set -e

# Poranna rutyna asystenta - instalator harmonogramu
# Idempotentny: możesz odpalać go dowolną liczbę razy, doprowadza konfigurację
# do stanu opisanego w scripts/morning-routine.env.
#
# Zakłada dwie warstwy:
#   1) harmonogram Paseo (cron) - odpala świeżego agenta z /do-your-job,
#      radzi sobie ze snem Maca (zaległy run leci po wybudzeniu)
#   2) LaunchAgent -> scripts/morning-routine-guard.sh - nadrabia to,
#      czego Paseo nie ogarnia (reboot, restart demona, wyłączony Docker)
#
# Użycie:
#   ./setup-morning-routine.sh            # instalacja / aktualizacja
#   ./setup-morning-routine.sh --status   # diagnostyka, nic nie zmienia
#   ./setup-morning-routine.sh --dry-run  # pokaż co by zrobił
#   ./setup-morning-routine.sh --uninstall

# This script lives at the project root; resolve it regardless of the caller's cwd.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# shellcheck source=scripts/morning-routine.env
source "$PROJECT_ROOT/scripts/morning-routine.env"

GUARD_SCRIPT="$PROJECT_ROOT/scripts/morning-routine-guard.sh"
PLIST_PATH="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
CRON="$RUN_MINUTE $RUN_HOUR * * $RUN_DAYS"

MODE_ACTION="install"
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --status)    MODE_ACTION="status" ;;
        --uninstall) MODE_ACTION="uninstall" ;;
        --dry-run)   DRY_RUN=1 ;;
        -h|--help)
            sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo -e "${RED}Nieznany argument: $arg${NC}"
            exit 1
            ;;
    esac
done

run() {
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${YELLOW}[dry-run]${NC} $*"
    else
        "$@"
    fi
}

# ==========================================
# Narzędzia
# ==========================================
ensure_paseo_on_path() {
    if command -v paseo &> /dev/null; then
        return 0
    fi
    for node_bin in "$HOME"/.nvm/versions/node/*/bin; do
        if [ -x "$node_bin/paseo" ]; then
            export PATH="$node_bin:$PATH"
            return 0
        fi
    done
    [ -x "$HOME/.local/bin/paseo" ] && export PATH="$HOME/.local/bin:$PATH" && return 0
    return 1
}

paseo_cli() {
    if [ -n "$PASEO_HOST" ]; then
        paseo "$@" --host "$PASEO_HOST"
    else
        paseo "$@"
    fi
}

# Wypisuje "id<TAB>status" istniejącego harmonogramu o nazwie $SCHEDULE_NAME (albo nic).
find_schedule() {
    SCHEDULE_NAME="$SCHEDULE_NAME" python3 - <<'PY'
import json, os, glob

name = os.environ["SCHEDULE_NAME"]
for path in sorted(glob.glob(os.path.expanduser("~/.paseo/schedules/*.json"))):
    try:
        with open(path) as fh:
            rec = json.load(fh)
    except (OSError, ValueError):
        continue
    if rec.get("name") == name and rec.get("status") != "deleted":
        print("%s\t%s" % (rec.get("id", ""), rec.get("status", "")))
        break
PY
}

# Czy istniejący harmonogram ma już dokładnie taką konfigurację, jakiej chcemy?
# Jeśli tak, pomijamy `schedule update` - dzięki temu ponowne odpalenie instalatora
# jest prawdziwym no-opem i nie ma szans ruszyć harmonogramu (ani odpalić runu).
schedule_matches() {
    SCHED_ID="$1" \
    WANT_CRON="$CRON" WANT_TZ="$TIMEZONE" WANT_PROMPT="$PROMPT" \
    WANT_PROVIDER="$PROVIDER" WANT_MODE="$MODE" WANT_CWD="$PROJECT_ROOT" WANT_NAME="$SCHEDULE_NAME" \
    python3 - <<'PY'
import json, os, sys

path = os.path.expanduser("~/.paseo/schedules/%s.json" % os.environ["SCHED_ID"])
try:
    with open(path) as fh:
        rec = json.load(fh)
except (OSError, ValueError):
    sys.exit(1)

cadence = rec.get("cadence") or {}
cfg = (rec.get("target") or {}).get("config") or {}

same = (
    cadence.get("type") == "cron"
    and cadence.get("expression") == os.environ["WANT_CRON"]
    and cadence.get("timezone") == os.environ["WANT_TZ"]
    and rec.get("name") == os.environ["WANT_NAME"]
    and rec.get("prompt") == os.environ["WANT_PROMPT"]
    and (rec.get("target") or {}).get("type") == "new-agent"
    and cfg.get("provider") == os.environ["WANT_PROVIDER"]
    and cfg.get("modeId") == os.environ["WANT_MODE"]
    and cfg.get("cwd") == os.environ["WANT_CWD"]
)
sys.exit(0 if same else 1)
PY
}

schedule_field() {
    # $1 = schedule id, $2 = klucz (szukany rekurencyjnie)
    SCHED_ID="$1" FIELD="$2" python3 - <<'PY'
import json, os

path = os.path.expanduser("~/.paseo/schedules/%s.json" % os.environ["SCHED_ID"])
field = os.environ["FIELD"]

def find_key(obj, key):
    if isinstance(obj, dict):
        if key in obj and obj[key]:
            return obj[key]
        for v in obj.values():
            found = find_key(v, key)
            if found:
                return found
    elif isinstance(obj, list):
        for v in obj:
            found = find_key(v, key)
            if found:
                return found
    return None

try:
    with open(path) as fh:
        print(find_key(json.load(fh), field) or "")
except (OSError, ValueError):
    print("")
PY
}

# ==========================================
# Plist
# ==========================================
write_plist() {
    # Dwa odpalenia guarda dziennie: preflight przed rutyną (Docker + demon) i catch-up po niej.
    local pre_total=$(( RUN_HOUR * 60 + RUN_MINUTE - GUARD_PRE_MINUTES ))
    local post_total=$(( RUN_HOUR * 60 + RUN_MINUTE + GUARD_DELAY_MINUTES ))
    local pre_hour=$(( (pre_total / 60 + 24) % 24 ))
    local pre_minute=$(( pre_total % 60 ))
    local guard_hour=$(( (post_total / 60) % 24 ))
    local guard_minute=$(( post_total % 60 ))

    local days=()
    if [ "$RUN_DAYS" = "*" ]; then
        days=(1 2 3 4 5 6 7)
    elif [[ "$RUN_DAYS" == *-* ]]; then
        local from="${RUN_DAYS%%-*}" to="${RUN_DAYS##*-}"
        for ((d = from; d <= to; d++)); do days+=("$d"); done
    else
        IFS=',' read -r -a days <<< "$RUN_DAYS"
    fi

    local intervals=""
    for d in "${days[@]}"; do
        for slot in "$pre_hour:$pre_minute" "$guard_hour:$guard_minute"; do
            intervals+="        <dict>
            <key>Weekday</key>
            <integer>$d</integer>
            <key>Hour</key>
            <integer>${slot%%:*}</integer>
            <key>Minute</key>
            <integer>${slot##*:}</integer>
        </dict>
"
        done
    done

    local content
    content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>$LAUNCHD_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>$GUARD_SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartCalendarInterval</key>
    <array>
$intervals    </array>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$ERR_FILE</string>
</dict>
</plist>"

    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${YELLOW}[dry-run]${NC} zapis $PLIST_PATH (guard: ${pre_hour}:$(printf "%02d" "$pre_minute") + ${guard_hour}:$(printf "%02d" "$guard_minute"), dni: ${days[*]})"
        return 0
    fi

    mkdir -p "$(dirname "$PLIST_PATH")"
    printf '%s\n' "$content" > "$PLIST_PATH"
    echo -e "  ${GREEN}✓${NC} $PLIST_PATH (guard: preflight ${pre_hour}:$(printf '%02d' "$pre_minute") + catch-up ${guard_hour}:$(printf '%02d' "$guard_minute"), dni: ${days[*]})"
}

reload_launchagent() {
    run launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${YELLOW}[dry-run]${NC} launchctl bootstrap gui/$(id -u) $PLIST_PATH"
    else
        launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
        echo -e "  ${GREEN}✓${NC} LaunchAgent załadowany ($LAUNCHD_LABEL)"
    fi
}

# ==========================================
# Akcje
# ==========================================
print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Poranna rutyna asystenta - harmonogram              ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
}

do_status() {
    print_header
    echo -e "${YELLOW}Konfiguracja${NC}"
    echo "  Harmonogram : $SCHEDULE_NAME"
    echo "  Cron        : $CRON ($TIMEZONE)"
    echo "  Provider    : $PROVIDER (mode: $MODE)"
    echo "  Katalog     : $PROJECT_ROOT"
    echo

    echo -e "${YELLOW}Paseo${NC}"
    if ensure_paseo_on_path; then
        echo -e "  ${GREEN}✓${NC} paseo: $(command -v paseo)"
        if paseo_cli daemon status &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} demon działa"
        else
            echo -e "  ${RED}✗${NC} demon nie odpowiada (paseo daemon start)"
        fi
    else
        echo -e "  ${RED}✗${NC} paseo nie znaleziony"
    fi

    local found id
    found="$(find_schedule)"
    if [ -n "$found" ]; then
        id="${found%%$'\t'*}"
        echo -e "  ${GREEN}✓${NC} harmonogram: $id (status: ${found##*$'\t'})"
        echo "      ostatni run : $(schedule_field "$id" lastRunAt)"
        echo "      następny run: $(schedule_field "$id" nextRunAt)"
    else
        echo -e "  ${RED}✗${NC} brak harmonogramu o nazwie \"$SCHEDULE_NAME\""
    fi
    echo

    echo -e "${YELLOW}LaunchAgent${NC}"
    if [ -f "$PLIST_PATH" ]; then
        echo -e "  ${GREEN}✓${NC} $PLIST_PATH"
    else
        echo -e "  ${RED}✗${NC} brak $PLIST_PATH"
    fi
    if launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} załadowany w launchd"
    else
        echo -e "  ${RED}✗${NC} niezaładowany w launchd"
    fi
    echo "  Log: $LOG_FILE"
    echo

    echo -e "${YELLOW}Serwery MCP (Docker)${NC}"
    if docker info &> /dev/null; then
        docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps --format '  {{.Name}}\t{{.Status}}' 2>/dev/null \
            || echo "  (brak kontenerów)"
    else
        echo -e "  ${RED}✗${NC} Docker nie odpowiada"
    fi
}

do_uninstall() {
    print_header
    echo -e "${YELLOW}Usuwam harmonogram i LaunchAgenta...${NC}"

    if ensure_paseo_on_path; then
        local found
        found="$(find_schedule)"
        if [ -n "$found" ]; then
            run paseo_cli schedule delete "${found%%$'\t'*}" > /dev/null
            echo -e "  ${GREEN}✓${NC} harmonogram Paseo usunięty (${found%%$'\t'*})"
        else
            echo -e "  ${GREEN}✓${NC} harmonogram już nie istnieje"
        fi
    fi

    run launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
    if [ -f "$PLIST_PATH" ]; then
        run rm -f "$PLIST_PATH"
        echo -e "  ${GREEN}✓${NC} plist usunięty"
    fi
    echo
    echo -e "${GREEN}Gotowe.${NC} Kontenerów Dockera ani logów nie ruszam."
}

do_install() {
    print_header

    # --- 1. Preflight ---
    echo -e "${YELLOW}Sprawdzam wymagania...${NC}"

    if ! ensure_paseo_on_path; then
        echo -e "  ${RED}✗${NC} nie znalazłem CLI 'paseo' (npm i -g @getpaseo/cli lub Paseo.app)"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} paseo: $(command -v paseo)"

    command -v python3 &> /dev/null || { echo -e "  ${RED}✗${NC} python3 nie znaleziony"; exit 1; }
    echo -e "  ${GREEN}✓${NC} python3"

    [ -f "$GUARD_SCRIPT" ] || { echo -e "  ${RED}✗${NC} brak $GUARD_SCRIPT"; exit 1; }
    chmod +x "$GUARD_SCRIPT" 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} guard: $GUARD_SCRIPT"

    if ! paseo_cli daemon status &> /dev/null; then
        echo -e "  ${YELLOW}!${NC} demon Paseo nie odpowiada - startuję..."
        paseo_cli daemon start &> /dev/null || true
        sleep 3
    fi
    if paseo_cli daemon status &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} demon Paseo działa"
    else
        echo -e "  ${RED}✗${NC} demon Paseo niedostępny (paseo daemon start)"
        exit 1
    fi

    if paseo_cli provider ls 2>/dev/null | awk '{print $1}' | grep -qx "$PROVIDER"; then
        echo -e "  ${GREEN}✓${NC} provider: $PROVIDER"
    else
        echo -e "  ${RED}✗${NC} provider '$PROVIDER' niedostępny (paseo provider ls)"
        exit 1
    fi
    echo

    # --- 2. Harmonogram Paseo ---
    echo -e "${YELLOW}Harmonogram Paseo...${NC}"
    local found schedule_id
    found="$(find_schedule)"

    if [ -n "$found" ] && schedule_matches "${found%%$'\t'*}" && [ "${found##*$'\t'}" != "paused" ]; then
        schedule_id="${found%%$'\t'*}"
        echo -e "  ${GREEN}✓${NC} bez zmian: $schedule_id (konfiguracja już zgodna)"
    elif [ -n "$found" ]; then
        schedule_id="${found%%$'\t'*}"
        echo "  Znaleziony istniejący: $schedule_id - aktualizuję w miejscu."
        run paseo_cli schedule update "$schedule_id" \
            --cron "$CRON" \
            --timezone "$TIMEZONE" \
            --name "$SCHEDULE_NAME" \
            --prompt "$PROMPT" \
            --provider "$PROVIDER" \
            --mode "$MODE" \
            --cwd "$PROJECT_ROOT" > /dev/null
        if [ "${found##*$'\t'}" = "paused" ]; then
            run paseo_cli schedule resume "$schedule_id" > /dev/null
            echo -e "  ${GREEN}✓${NC} wznowiony (był zapauzowany)"
        fi
        echo -e "  ${GREEN}✓${NC} zaktualizowany: $schedule_id"
    else
        # --target new-agent jest wymagane: harmonogram celujący w istniejącego agenta
        # wysyła powiadomienie push tylko przy pierwszym runie.
        #
        # UWAGA: utworzenie harmonogramu cron odpala JEDEN run od razu (paseo 0.1.109 /
        # daemon 0.2.2 - mimo że CLI twierdzi "cron schedules never fire on creation").
        # Traktuj to jako darmowy smoke test; kolejne uruchomienia instalatora już nie
        # tworzą runu, bo idą ścieżką "bez zmian" albo "update".
        if [ "$DRY_RUN" = "1" ]; then
            echo -e "  ${YELLOW}[dry-run]${NC} paseo schedule create --name \"$SCHEDULE_NAME\" --cron \"$CRON\" --timezone $TIMEZONE --target new-agent --provider $PROVIDER --mode $MODE --cwd $PROJECT_ROOT <prompt>"
            schedule_id="(dry-run)"
        else
            local created
            created="$(paseo_cli schedule create \
                --name "$SCHEDULE_NAME" \
                --cron "$CRON" \
                --timezone "$TIMEZONE" \
                --target new-agent \
                --provider "$PROVIDER" \
                --mode "$MODE" \
                --cwd "$PROJECT_ROOT" \
                --json \
                "$PROMPT")"
            schedule_id="$(printf '%s' "$created" | python3 -c 'import json,sys
def find(o):
    if isinstance(o, dict):
        if isinstance(o.get("id"), str): return o["id"]
        for v in o.values():
            r = find(v)
            if r: return r
    elif isinstance(o, list):
        for v in o:
            r = find(v)
            if r: return r
    return None
try: print(find(json.load(sys.stdin)) or "")
except Exception: print("")')"
            echo -e "  ${GREEN}✓${NC} utworzony: ${schedule_id:-?}"
        fi
    fi
    echo "  Cron: $CRON ($TIMEZONE), cwd: $PROJECT_ROOT"
    echo

    # --- 3. LaunchAgent (siatka bezpieczeństwa) ---
    echo -e "${YELLOW}LaunchAgent (nadrabianie po reboocie/uśpieniu)...${NC}"
    write_plist
    reload_launchagent
    echo

    # --- 4. Podsumowanie ---
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                      Gotowe!                               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    if [ "$DRY_RUN" != "1" ] && [ -n "${schedule_id:-}" ]; then
        echo "  Następny run: $(schedule_field "$schedule_id" nextRunAt)"
        echo
        echo "  Test ręczny  : paseo schedule run-once $schedule_id"
        echo "  Podgląd      : paseo schedule inspect $schedule_id"
        echo "  Logi guarda  : $LOG_FILE"
        echo "  Diagnostyka  : ./setup-morning-routine.sh --status"
    fi
}

case "$MODE_ACTION" in
    status)    do_status ;;
    uninstall) do_uninstall ;;
    install)   do_install ;;
esac
