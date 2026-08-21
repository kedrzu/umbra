#!/bin/bash
set -e

# Strażnik snu - instalator LaunchAgenta.
# Idempotentny: możesz odpalać go dowolną liczbę razy, doprowadza konfigurację
# do stanu opisanego w scripts/sleep-guard.env.
#
# Po co: Mac w clamshell (zamknięta pokrywa + dok + zasilanie) nie usypia sam,
# bo AppleClamshellCausesSleep = No, a o śnie decydują wyłącznie asercje IOKit.
# Spotify trzyma otwarty strumień CoreAudio nawet gdy nic nie gra i blokuje sen
# godzinami. Strażnik zdejmuje ten bloker, gdy nikogo nie ma przy biurku,
# i przywraca Wispr Flow, gdy użytkownik wróci.
#
# Użycie:
#   ./setup-sleep-guard.sh            # instalacja / aktualizacja
#   ./setup-sleep-guard.sh --status   # diagnostyka, nic nie zmienia
#   ./setup-sleep-guard.sh --dry-run  # pokaż co by zrobił
#   ./setup-sleep-guard.sh --uninstall

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# shellcheck source=scripts/sleep-guard.env
source "$PROJECT_ROOT/scripts/sleep-guard.env"

GUARD_SCRIPT="$PROJECT_ROOT/scripts/sleep-guard.sh"
PLIST_PATH="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"

MODE_ACTION="install"
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --status)    MODE_ACTION="status" ;;
        --uninstall) MODE_ACTION="uninstall" ;;
        --dry-run)   DRY_RUN=1 ;;
        -h|--help)
            sed -n '4,21p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'
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

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║             Strażnik snu - clamshell / asercje             ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
}

write_plist() {
    # StartInterval, NIE StartCalendarInterval: ten pierwszy nie budzi śpiącego Maca,
    # tylko odpala się przy najbliższym wybudzeniu. Odwrotnie strażnik snu sam
    # wybudzałby maszynę co minutę.
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
        <string>--watch</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$POLL_SECONDS</integer>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$ERR_FILE</string>
</dict>
</plist>"

    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${YELLOW}[dry-run]${NC} zapis $PLIST_PATH (co ${POLL_SECONDS}s)"
        return 0
    fi

    mkdir -p "$(dirname "$PLIST_PATH")"
    printf '%s\n' "$content" > "$PLIST_PATH"
    echo -e "  ${GREEN}✓${NC} $PLIST_PATH (tick co ${POLL_SECONDS}s)"
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

do_status() {
    print_header
    echo -e "${YELLOW}Konfiguracja${NC}"
    echo "  Okno sprzątania   : ${CLEANUP_FROM_HOUR}:00 - ${CLEANUP_TO_HOUR}:00 (w dzień nic nie ubijamy)"
    echo "  Próg bezczynności : ${IDLE_MINUTES} min"
    echo "  Powrót użytkownika: < ${PRESENCE_SECONDS}s od ruchu"
    echo "  Tick              : co ${POLL_SECONDS}s"
    echo "  Ubijane           : $(echo "$QUIT_APPS" | cut -d'|' -f2 | paste -sd',' - | sed 's/,/, /g')"
    echo "  Przywracane       : $(echo "$RELAUNCH_APPS" | cut -d'|' -f2 | paste -sd',' - | sed 's/,/, /g')"
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

    echo -e "${YELLOW}Stan bieżący${NC}"
    /bin/zsh "$GUARD_SCRIPT" --status | sed 's/^/  /'
}

do_uninstall() {
    print_header
    echo -e "${YELLOW}Usuwam LaunchAgenta...${NC}"
    run launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
    if [ -f "$PLIST_PATH" ]; then
        run rm -f "$PLIST_PATH"
        echo -e "  ${GREEN}✓${NC} plist usunięty"
    else
        echo -e "  ${GREEN}✓${NC} plist już nie istnieje"
    fi
    echo
    echo -e "${GREEN}Gotowe.${NC} Skryptu ani logów nie ruszam."
}

do_install() {
    print_header

    echo -e "${YELLOW}Sprawdzam wymagania...${NC}"
    [ -f "$GUARD_SCRIPT" ] || { echo -e "  ${RED}✗${NC} brak $GUARD_SCRIPT"; exit 1; }
    chmod +x "$GUARD_SCRIPT" 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} strażnik: $GUARD_SCRIPT"

    if /bin/zsh -n "$GUARD_SCRIPT" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} składnia strażnika OK"
    else
        echo -e "  ${RED}✗${NC} błąd składni w $GUARD_SCRIPT"
        exit 1
    fi
    echo

    echo -e "${YELLOW}LaunchAgent...${NC}"
    write_plist
    reload_launchagent
    echo

    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                      Gotowe!                               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "  Okno sprzątania                      : ${CLEANUP_FROM_HOUR}:00 - ${CLEANUP_TO_HOUR}:00"
    echo "  Ubijane przy ${IDLE_MINUTES} min bezczynności: $(echo "$QUIT_APPS" | cut -d'|' -f2 | paste -sd',' - | sed 's/,/, /g')"
    echo "  Wraca po powrocie do biurka          : $(echo "$RELAUNCH_APPS" | cut -d'|' -f2 | paste -sd',' - | sed 's/,/, /g')"
    echo
    echo "  Idę spać teraz : $GUARD_SCRIPT --sleep"
    echo "  Test ticku     : $GUARD_SCRIPT --once"
    echo "  Diagnostyka    : ./setup-sleep-guard.sh --status"
    echo "  Log            : $LOG_FILE"
}

case "$MODE_ACTION" in
    status)    do_status ;;
    uninstall) do_uninstall ;;
    install)   do_install ;;
esac
