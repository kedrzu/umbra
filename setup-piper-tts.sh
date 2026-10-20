#!/bin/bash
set -e

# Polski głos dla Paseo (czytanie odpowiedzi w trybie głosowym) - instalator
# Idempotentny: możesz odpalać go dowolną liczbę razy, doprowadza stan do
# opisanego w scripts/piper-tts.env.
#
# Lokalny TTS Paseo ma tylko angielski głos (Kokoro), a listy modeli nie da się
# rozszerzyć ani pluginem, ani configiem. Paseo pozwala za to podmienić adres
# dostawcy `openai` - więc stawiamy Pipera w Dockerze za API zgodnym z OpenAI
# (services/piper-tts/) i kierujemy tam Paseo. Dyktowanie (Parakeet v3, lokalnie)
# zostaje bez zmian.
#
# Użycie:
#   ./setup-piper-tts.sh               # instalacja / aktualizacja
#   ./setup-piper-tts.sh --status      # diagnostyka, nic nie zmienia
#   ./setup-piper-tts.sh --dry-run     # pokaż co by zrobił
#   ./setup-piper-tts.sh --restart     # po zmianach zrestartuj demona Paseo
#   ./setup-piper-tts.sh --uninstall   # wróć do lokalnego Kokoro, zatrzymaj kontener
#
# UWAGA: ustawienia mowy demon czyta tylko przy starcie (`paseo daemon reload`
# ich nie przeładowuje). Restart demona ubija wszystkie działające pod nim
# agenty, dlatego NIE jest domyślny - zrób go, kiedy nic ważnego nie pracuje.

# This script lives at the project root; resolve it regardless of the caller's cwd.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# compose.yml bierze wartości ze środowiska, więc eksportujemy cały plik.
set -a
# shellcheck source=scripts/piper-tts.env
source "$PROJECT_ROOT/scripts/piper-tts.env"
set +a

COMPOSE_FILE="$PROJECT_ROOT/services/piper-tts/compose.yml"
CONTAINER="umbra-piper-tts"
BASE_URL="http://127.0.0.1:$PIPER_TTS_PORT/v1"
BACKUP_FILE="$PASEO_DIR/config.json.bak-piper-tts"

MODE_ACTION="install"
DRY_RUN=0
DO_RESTART=0

for arg in "$@"; do
    case "$arg" in
        --status)    MODE_ACTION="status" ;;
        --uninstall) MODE_ACTION="uninstall" ;;
        --dry-run)   DRY_RUN=1 ;;
        --restart)   DO_RESTART=1 ;;
        -h|--help)
            sed -n '3,23p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'
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

# CLI Paseo to binarka Electrona, która przy każdym wywołaniu sypie na stderr
# ostrzeżeniem o podpisie kodu - odfiltrowujemy tylko ten szum.
paseo_cli() {
    paseo "$@" 2> >(grep -v 'codesign_util' >&2)
}

paseo_get() {
    paseo_cli daemon config get "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(json.dumps(d["value"]) if d.get("set") else "")'
}

compose() {
    docker compose -f "$COMPOSE_FILE" "$@"
}

# --- Docker --------------------------------------------------------------

require_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}✗ Docker nie działa - uruchom Docker Desktop i spróbuj ponownie.${NC}"
        exit 1
    fi
}

container_state() {
    docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "brak"
}

wait_for_health() {
    local i
    for i in $(seq 1 30); do
        if curl -sf "http://127.0.0.1:$PIPER_TTS_PORT/health" >/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

smoke_test() {
    local out bytes
    out="$(mktemp)"
    curl -sf "$BASE_URL/audio/speech" -H 'Content-Type: application/json' \
        -d '{"model":"tts-1","voice":"alloy","input":"Test polskiego głosu.","response_format":"pcm"}' \
        -o "$out" || { rm -f "$out"; return 1; }
    bytes=$(wc -c < "$out" | tr -d ' ')
    rm -f "$out"
    [ "$bytes" -gt 24000 ] || return 1
    echo -e "  ${GREEN}✓${NC} synteza działa ($((bytes / 48))ms audio @24 kHz)"
}

# --- Paseo config --------------------------------------------------------

desired_tts() {
    printf '{"provider":"openai","model":"%s","voice":"%s"}' "$PASEO_TTS_MODEL" "$PASEO_TTS_VOICE"
}

desired_endpoint() {
    printf '{"apiKey":"%s","baseUrl":"%s"}' "$PASEO_TTS_API_KEY" "$BASE_URL"
}

configure_paseo() {
    local current_tts current_endpoint
    current_tts="$(paseo_get features.voiceMode.tts)"
    current_endpoint="$(paseo_get providers.openai.tts)"

    # Kopia dotychczasowego bloku TTS - tylko raz, żeby --uninstall wracał
    # do stanu sprzed Pipera, a nie do poprzedniej wersji Pipera.
    if [ ! -f "$BACKUP_FILE" ] && [ -n "$current_tts" ] \
        && ! echo "$current_tts" | grep -q '"provider": *"openai"'; then
        echo -e "  Kopia obecnych ustawień TTS → ${BLUE}$BACKUP_FILE${NC}"
        [ "$DRY_RUN" = "1" ] || echo "$current_tts" > "$BACKUP_FILE"
    fi

    if python3 -c 'import json,sys; sys.exit(json.loads(sys.argv[1] or "null") != json.loads(sys.argv[2]))' \
        "$current_tts" "$(desired_tts)"; then
        echo -e "  ${GREEN}✓${NC} features.voiceMode.tts już wskazuje na Pipera"
    else
        run paseo_cli daemon config set features.voiceMode.tts "$(desired_tts)" >/dev/null
        echo -e "  ${GREEN}✓${NC} features.voiceMode.tts → openai ($PASEO_TTS_MODEL/$PASEO_TTS_VOICE)"
        CHANGED=1
    fi

    # CLI maskuje apiKey ("[redacted]"), więc porównujemy adres i samo to, że klucz jest.
    if python3 -c '
import json, sys
cur = json.loads(sys.argv[1] or "{}")
sys.exit(not (cur.get("baseUrl") == sys.argv[2] and cur.get("apiKey")))' \
        "$current_endpoint" "$BASE_URL"; then
        echo -e "  ${GREEN}✓${NC} providers.openai.tts już wskazuje na $BASE_URL"
    else
        run paseo_cli daemon config set providers.openai.tts "$(desired_endpoint)" >/dev/null
        echo -e "  ${GREEN}✓${NC} providers.openai.tts → $BASE_URL"
        CHANGED=1
    fi
}

restart_notice() {
    if [ "$DO_RESTART" = "1" ]; then
        echo -e "${YELLOW}Restartuję demona Paseo (działające agenty zostaną przerwane)...${NC}"
        run paseo_cli daemon restart
    elif [ "${CHANGED:-0}" = "1" ]; then
        echo -e "${YELLOW}! Zmiany wejdą po restarcie demona Paseo:${NC} ./setup-piper-tts.sh --restart"
        echo -e "  (albo restart aplikacji Paseo; restart przerywa działające agenty)"
    fi
}

# --- Akcje ---------------------------------------------------------------

do_status() {
    echo -e "${BLUE}Piper TTS${NC}"
    echo -e "  Kontener: $(container_state)"
    if curl -sf "http://127.0.0.1:$PIPER_TTS_PORT/health" 2>/dev/null; then
        echo
        echo -e "  RAM: $(docker stats --no-stream --format '{{.MemUsage}}' "$CONTAINER" 2>/dev/null)"
    else
        echo -e "  ${RED}✗${NC} brak odpowiedzi na :$PIPER_TTS_PORT"
    fi
    echo -e "${BLUE}Paseo${NC}"
    echo -e "  features.voiceMode.tts:  $(paseo_get features.voiceMode.tts)"
    echo -e "  providers.openai.tts:    $(paseo_get providers.openai.tts | sed -E 's/"apiKey": *"[^"]*"/"apiKey":"…"/')"
    [ -f "$BACKUP_FILE" ] && echo -e "  Kopia sprzed Pipera:     $(cat "$BACKUP_FILE")"
    return 0
}

do_install() {
    require_docker
    echo -e "${BLUE}Kontener Piper ($PIPER_VOICE, 127.0.0.1:$PIPER_TTS_PORT)${NC}"
    run compose up -d --build
    if [ "$DRY_RUN" = "0" ]; then
        wait_for_health || { echo -e "${RED}✗ Serwer nie wstał - zobacz: docker logs $CONTAINER${NC}"; exit 1; }
        smoke_test || { echo -e "${RED}✗ Synteza nie działa - zobacz: docker logs $CONTAINER${NC}"; exit 1; }
    fi
    echo -e "${BLUE}Konfiguracja Paseo${NC}"
    configure_paseo
    restart_notice
}

do_uninstall() {
    local previous
    previous='{"provider":"local","model":"kokoro-en-v0_19","speakerId":0}'
    [ -f "$BACKUP_FILE" ] && previous="$(cat "$BACKUP_FILE")"
    echo -e "${BLUE}Konfiguracja Paseo${NC}"
    run paseo_cli daemon config set features.voiceMode.tts "$previous" >/dev/null
    echo -e "  ${GREEN}✓${NC} features.voiceMode.tts → $previous"
    if [ -n "$(paseo_get providers.openai.tts)" ]; then
        run paseo_cli daemon config unset providers.openai.tts >/dev/null
        echo -e "  ${GREEN}✓${NC} usunięto providers.openai.tts"
    fi
    CHANGED=1
    if docker info >/dev/null 2>&1; then
        echo -e "${BLUE}Kontener Piper${NC}"
        run compose down
    fi
    restart_notice
}

case "$MODE_ACTION" in
    status)    do_status ;;
    install)   do_install ;;
    uninstall) do_uninstall ;;
esac
