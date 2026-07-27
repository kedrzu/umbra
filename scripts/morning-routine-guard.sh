#!/bin/zsh
# Siatka bezpieczeństwa dla porannej rutyny asystenta.
#
# Paseo sam radzi sobie ze snem Maca (scheduler porównuje zapisany nextRunAt z zegarem,
# więc po wybudzeniu odpala zaległy run). NIE radzi sobie z restartem demona: przy starcie
# przewija nextRunAt do przodu BEZ wykonania, więc run po reboocie/aktualizacji przepada.
#
# Ten skrypt odpala launchd (RunAtLoad + StartCalendarInterval), czyli z semantyką
# "wykona się po wybudzeniu / po starcie systemu", w dwóch trybach:
#
#   PREFLIGHT (kilka minut PRZED rutyną) - podnosi Docker z serwerami MCP i demona Paseo,
#     żeby agent o 8:00 miał komplet narzędzi. Kalendarz łączy się przez
#     `docker exec` (patrz .mcp.json), więc kontener musi stać wcześniej.
#
#   CATCH-UP (po godzinie rutyny) - jeśli dzisiejszy run nie poszedł, odpala go ręcznie.
#
# Idempotentny: gdy rutyna dziś już poszła, nie robi nic.
# Instalacja: ./setup-morning-routine.sh  (plist wskazuje wprost na ten plik w repo)

set -u

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"

# launchd daje minimalny PATH - dokładamy typowe lokalizacje narzędzi.
PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$HOME/.bun/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
for node_bin in "$HOME"/.nvm/versions/node/*/bin(N); do
    PATH="$node_bin:$PATH"
done
export PATH

source "$SCRIPT_DIR/morning-routine.env"

log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

paseo_cli() {
    if [ -n "$PASEO_HOST" ]; then
        paseo "$@" --host "$PASEO_HOST"
    else
        paseo "$@"
    fi
}

# ==========================================
# 1. Czy dziś w ogóle rutyna ma chodzić?
# ==========================================
today_dow=$(date +%u)   # 1=poniedziałek ... 7=niedziela
if [ "$RUN_DAYS" != "*" ]; then
    case "$RUN_DAYS" in
        *-*)
            dow_from="${RUN_DAYS%%-*}"
            dow_to="${RUN_DAYS##*-}"
            if [ "$today_dow" -lt "$dow_from" ] || [ "$today_dow" -gt "$dow_to" ]; then
                exit 0
            fi
            ;;
        *)
            [[ ",$RUN_DAYS," == *",$today_dow,"* ]] || exit 0
            ;;
    esac
fi

now_minutes=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
run_minutes=$(( RUN_HOUR * 60 + RUN_MINUTE ))
pre_minutes=$(( run_minutes - GUARD_PRE_MINUTES ))

# Za wcześnie - nawet na preflight.
[ "$now_minutes" -lt "$pre_minutes" ] && exit 0

if [ "$now_minutes" -lt "$run_minutes" ]; then
    MODE="preflight"
else
    MODE="catchup"
fi

# ==========================================
# 2. Stan harmonogramu (bez budzenia czegokolwiek)
# ==========================================
# Czytamy stan wprost z plików Paseo - nie wymaga działającego demona.
schedule_state=$(SCHEDULE_NAME="$SCHEDULE_NAME" python3 - <<'PY'
import json, os, glob, datetime

name = os.environ["SCHEDULE_NAME"]

def find_key(obj, key):
    """Rekurencyjnie znajdź wartość klucza - układ rekordu bywa płaski albo zagnieżdżony."""
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

def local_date(iso):
    if not iso:
        return ""
    try:
        dt = datetime.datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
    except ValueError:
        return ""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt.astimezone().date().isoformat()

for path in sorted(glob.glob(os.path.expanduser("~/.paseo/schedules/*.json"))):
    try:
        with open(path) as fh:
            rec = json.load(fh)
    except (OSError, ValueError):
        continue
    if rec.get("name") != name:
        continue

    runs = rec.get("runs") or []
    running = any(r.get("status") == "running" for r in runs)
    stamps = [find_key(rec, "lastRunAt")]
    for r in runs:
        stamps.extend([r.get("startedAt"), r.get("scheduledFor")])
    dates = sorted({local_date(s) for s in stamps if s} - {""})

    print(rec.get("id", ""))
    print(rec.get("status", ""))
    print(dates[-1] if dates else "")
    print("running" if running else "idle")
    break
PY
)

schedule_id=$(print -r -- "$schedule_state" | sed -n '1p')
schedule_status=$(print -r -- "$schedule_state" | sed -n '2p')
last_run_date=$(print -r -- "$schedule_state" | sed -n '3p')
run_state=$(print -r -- "$schedule_state" | sed -n '4p')

if [ -z "$schedule_id" ]; then
    log "BŁĄD: nie znalazłem harmonogramu \"$SCHEDULE_NAME\". Odpal: $PROJECT_ROOT/setup-morning-routine.sh"
    exit 1
fi

if [ "$schedule_status" = "paused" ]; then
    log "Harmonogram jest zapauzowany - nic nie robię."
    exit 0
fi

today=$(date +%Y-%m-%d)
if [ "$MODE" = "catchup" ]; then
    if [ "$last_run_date" = "$today" ]; then
        log "Rutyna dziś już poszła ($last_run_date) - nic do nadrobienia."
        exit 0
    fi
    if [ "$run_state" = "running" ]; then
        log "Run jest właśnie w toku - nie duplikuję."
        exit 0
    fi
    log "Brak dzisiejszego runu (ostatni: ${last_run_date:-brak}) - nadrabiam."
else
    if [ "$last_run_date" = "$today" ]; then
        log "Rutyna dziś już poszła - preflight zbędny."
        exit 0
    fi
    log "Preflight przed rutyną (${RUN_HOUR}:$(printf '%02d' "$RUN_MINUTE"))."
fi

# ==========================================
# 3. Preflight: serwery MCP w Dockerze
# ==========================================
# gmail (4002) i calendar to kontenery z docker-compose.yml. Kalendarz klienci MCP
# odpalają przez `docker exec` (patrz .mcp.json), więc kontener musi stać ZANIM
# wystartuje agent - inaczej rutyna leci bez kalendarza i bez poczty.
if ! docker info >/dev/null 2>&1; then
    log "Docker nie odpowiada - uruchamiam Docker Desktop..."
    open -ga Docker 2>/dev/null || log "OSTRZEŻENIE: nie udało się uruchomić Docker Desktop"
    for _ in {1..45}; do
        docker info >/dev/null 2>&1 && break
        sleep 2
    done
fi

if docker info >/dev/null 2>&1; then
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" up -d >/dev/null 2>&1 \
        && log "Kontenery MCP gotowe (gmail, calendar)." \
        || log "OSTRZEŻENIE: docker compose up -d nie powiódł się."
else
    log "OSTRZEŻENIE: Docker nadal nie odpowiada - rutyna pojedzie bez Gmaila/Kalendarza."
fi

# ==========================================
# 4. Preflight: demon Paseo
# ==========================================
if ! paseo_cli daemon status >/dev/null 2>&1; then
    log "Demon Paseo nie odpowiada - startuję..."
    paseo_cli daemon start >/dev/null 2>&1 || log "OSTRZEŻENIE: paseo daemon start nie powiódł się."
    for _ in {1..15}; do
        paseo_cli daemon status >/dev/null 2>&1 && break
        sleep 2
    done
fi

if ! paseo_cli daemon status >/dev/null 2>&1; then
    log "BŁĄD: demon Paseo niedostępny."
    exit 1
fi

if [ "$MODE" = "preflight" ]; then
    log "Preflight zakończony - rutynę odpali harmonogram Paseo."
    exit 0
fi

# ==========================================
# 5. Nadrobienie runu
# ==========================================
log "paseo schedule run-once $schedule_id"
if paseo_cli schedule run-once "$schedule_id" >/dev/null 2>&1; then
    log "Rutyna odpalona."
else
    log "BŁĄD: paseo schedule run-once nie powiódł się."
    exit 1
fi
