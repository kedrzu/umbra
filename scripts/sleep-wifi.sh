#!/bin/zsh
# Wi-Fi wyłączone na czas snu - koniec wybudzeń z pakietów sieciowych.
#
# Dlaczego: uśpiony Mac zostaje w sieci Wi-Fi i budzi się (E_RX_IP_PACKET), gdy
# przyjdzie pakiet na otwarty port DOWOLNEJ aplikacji - Claude Code, Linear, Slack,
# WhatsApp, Tailscale... pmset (tcpkeepalive/womp/powernap = 0) tego nie wyłącza.
# Noc 2026-10-08/09: 76 wybudzeń na godzinę, Mac na nogach 95% nocy. Łatanie
# aplikacja po aplikacji nie ma końca, więc odcinamy samo radio.
#
# Odpalane przez sleepwatcher (LaunchAgent z setup-sleep-guard.sh):
#   sleep  -> -s  przed każdym zaśnięciem: Wi-Fi off (jeśli było włączone)
#   wake   <- sleep-guard.sh --wake, gdy po wybudzeniu pojawi się człowiek: Wi-Fi on
# Radio wraca dopiero przy obecności człowieka, nie przy samym wybudzeniu: w ciemnym
# wybudzeniu (DarkWake) otworzyłoby drogę do kolejnej burzy pakietów.
#
# Wi-Fi wraca tylko wtedy, gdy to MY je wyłączyliśmy (marker) - jeśli wyłączysz
# Wi-Fi ręcznie, skrypt go nie włączy. Siatka bezpieczeństwa: sleep-guard.sh przy
# każdym ticku z obecnym użytkownikiem też woła `wake`.
#
#   ./scripts/sleep-wifi.sh sleep|wake|status

set -u
SCRIPT_DIR="${0:A:h}"
PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
source "$SCRIPT_DIR/sleep-guard.env"

MARKER="$STATE_DIR/wifi-off-by-sleep"
mkdir -p "$STATE_DIR"

log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WIFI_LOG_FILE"; }

wifi_device() {
    networksetup -listallhardwareports 2>/dev/null | awk '/Hardware Port: Wi-Fi/ { getline; print $2; exit }'
}

wifi_is_on() {  # $1 = urządzenie
    networksetup -getairportpower "$1" 2>/dev/null | grep -q ': On$'
}

dev=$(wifi_device)
[[ -z "$dev" ]] && { log "brak karty Wi-Fi - nic nie robię"; exit 0; }

case "${1:-}" in
    sleep)
        [[ "$WIFI_OFF_DURING_SLEEP" == "1" ]] || exit 0
        # Na Apple Silicon "sen" przy zgaszonym ekranie bywa tylko Deep Idle: system
        # dalej pracuje, bo ktoś trzyma PreventSystemSleep (np. caffeinate -s z
        # harmonogramu godzin pracy, który działa tylko na zasilaczu). sleepwatcher
        # zgłasza to jak zaśnięcie - 2026-10-09 zgasiło to Wi-Fi w środku dnia.
        if pmset -g batt | grep -q "AC Power" &&
           pmset -g assertions | awk '$1 == "PreventSystemSleep" { exit !($2 > 0) }'; then
            log "sen pominięty: na zasilaczu trzymana PreventSystemSleep (Deep Idle, nie sen) - Wi-Fi zostaje"
            exit 0
        fi
        if wifi_is_on "$dev"; then
            networksetup -setairportpower "$dev" off && touch "$MARKER" && log "sen: Wi-Fi ($dev) wyłączone"
        fi
        ;;
    wake)
        [[ -f "$MARKER" ]] || exit 0
        networksetup -setairportpower "$dev" on && rm -f "$MARKER" && log "wybudzenie: Wi-Fi ($dev) włączone"
        ;;
    status)
        print -r -- "Wi-Fi ($dev): $(wifi_is_on "$dev" && print włączone || print wyłączone)"
        [[ -f "$MARKER" ]] && print -r -- "Marker: Wi-Fi wyłączone przez strażnika (wróci przy wybudzeniu ekranu)"
        print -r -- "Ostatnie wpisy ($WIFI_LOG_FILE):"
        tail -5 "$WIFI_LOG_FILE" 2>/dev/null | sed 's/^/  /'
        ;;
    *)
        sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
