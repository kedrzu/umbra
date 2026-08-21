#!/bin/zsh
# Strażnik snu: pilnuje, żeby Mac w trybie clamshell realnie zasypiał.
#
# Dlaczego w ogóle istnieje: przy zamkniętej pokrywie z dokiem i zasilaniem
# AppleClamshellCausesSleep = No, więc o uśpieniu decydują wyłącznie asercje IOKit.
# Jedna aplikacja z otwartym strumieniem CoreAudio (Spotify trzyma go nawet przy
# zerowym odtwarzaniu) trzyma PreventUserIdleSystemSleep i maszyna czuwa godzinami.
# Wyłączanie monitora, klawiatury i peryferiów nie pomaga - to tylko przenosi
# strumień na wbudowane głośniki.
#
# Zasada działania (jeden "tick", odpalany przez launchd co POLL_SECONDS):
#
#   użytkownik JEST      -> przywróć aplikacje z RELAUNCH_APPS, które sami ubiliśmy
#   użytkownika NIE MA   -> ubij aplikacje z QUIT_APPS (poza tymi realnie zajętymi),
#                           ale TYLKO w oknie sprzątania (wieczór/noc)
#
# Okno czasowe jest tu kluczowe: w ciągu dnia 15-minutowa przerwa w pracy to norma
# i nie może kosztować użytkownika ubitego Spotify. Przywracanie działa poza oknem.
#
# Nie ma tu wykrywania wybudzeń ani forsowania snu: po zdjęciu asercji macOS zasypia
# sam po swoim timerze (pmset -g custom -> sleep). Świadomie nie reagujemy na DarkWake
# (te z pakietów sieciowych zdarzają się co kilkanaście minut) - relaunch dzieje się
# tylko przy realnej obecności użytkownika, więc dark wake nie wskrzesi blokera.
#
# Tryby:
#   --watch     jeden tick, cicho (tak odpala launchd)
#   --once      jeden tick, gadatliwie (do testów z ręki)
#   --sleep     ubij wszystko z QUIT_APPS i uśpij natychmiast ("idę spać")
#   --status    diagnostyka: kto trzyma asercje, kiedy ostatnio spał
#
# Instalacja: ./setup-sleep-guard.sh

set -u

SCRIPT_DIR="${0:A:h}"

# launchd daje minimalny PATH.
PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PATH

source "$SCRIPT_DIR/sleep-guard.env"

MODE="watch"
case "${1:---watch}" in
    --watch)  MODE="watch" ;;
    --once)   MODE="once" ;;
    --sleep)  MODE="sleep" ;;
    --status) MODE="status" ;;
    -h|--help)
        sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        print -r -- "Nieznany argument: $1"
        exit 1
        ;;
esac

mkdir -p "$STATE_DIR"

VERBOSE=0
[[ "$MODE" == "once" || "$MODE" == "sleep" ]] && VERBOSE=1

log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
# Gadanie tylko w trybach ręcznych - w --watch logujemy wyłącznie realne akcje,
# żeby log nie puchł o 1440 linii dziennie.
say() { [[ "$VERBOSE" == "1" ]] && log "$*"; return 0; }

# ==========================================
# Odczyt stanu systemu
# ==========================================

# Sekundy od ostatniego ruchu myszy/klawiatury.
hid_idle_seconds() {
    local ns
    ns=$(ioreg -c IOHIDSystem 2>/dev/null | awk -F'= ' '/HIDIdleTime/ {gsub(/[^0-9]/, "", $2); print $2; exit}')
    if [[ -z "$ns" ]]; then
        print -r -- 0            # nie wiemy -> udajemy obecność, czyli nic nie ubijamy
        return
    fi
    print -r -- $(( ns / 1000000000 ))
}

# powerd wystawia tę asercję dokładnie wtedy, gdy ekran się świeci.
display_is_on() {
    pmset -g assertions 2>/dev/null | grep -q 'Prevent sleep while display is on'
}

# Czy jesteśmy w oknie sprzątania? Okno przechodzi przez północ (np. 20 -> 8).
in_cleanup_window() {
    local h
    h=$(( 10#$(date +%H) ))
    if [[ "$CLEANUP_FROM_HOUR" -lt "$CLEANUP_TO_HOUR" ]]; then
        [[ "$h" -ge "$CLEANUP_FROM_HOUR" && "$h" -lt "$CLEANUP_TO_HOUR" ]]
    else
        [[ "$h" -ge "$CLEANUP_FROM_HOUR" || "$h" -lt "$CLEANUP_TO_HOUR" ]]
    fi
}

# Czy dany PID trzyma asercję audio (coreaudiod wystawia ją "Created for PID: N.")?
# To jedyny wiarygodny sygnał, że proces realnie blokuje sen. Bez tego warunku
# ubijanie procesów pomocniczych Chromium zamienia się w pętlę: helper wraca
# w sekundę, my ubijamy go przy kolejnym ticku, i tak w kółko.
pid_holds_audio_assertion() {  # $1 = pid
    pmset -g assertions 2>/dev/null | awk -v pid="$1" '
        /^[[:space:]]+pid [0-9]+\(/     { owner = $0; next }
        /Created for PID:/              {
            if (owner ~ /coreaudiod/ && $0 ~ ("Created for PID: " pid "\\.")) found = 1
        }
        END { exit !found }
    '
}

app_running() {  # $1 = nazwa procesu
    pgrep -x "$1" > /dev/null 2>&1
}

# osascript przy braku uprawnień TCC potrafi zawisnąć na dialogu systemowym.
# Pod launchd oznaczałoby to stertę zombie ticków (nowy co POLL_SECONDS), więc
# każde wywołanie AppleScriptu dostaje twardy limit czasu.
osa() {  # $1 = timeout w sekundach, reszta = argumenty osascript
    local limit="$1"; shift
    local out pid
    out=$(mktemp "${TMPDIR:-/tmp}/sleep-guard.XXXXXX")
    osascript "$@" > "$out" 2>/dev/null &
    pid=$!
    local i
    for i in $(seq 1 $(( limit * 4 ))); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.25
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        rm -f "$out"
        return 1
    fi
    wait "$pid" 2>/dev/null
    cat "$out"
    rm -f "$out"
    return 0
}

# Czy aplikacja realnie coś robi (gra muzykę)? Jeśli tak - nie ruszamy jej,
# nawet gdy użytkownika nie ma przy biurku (może słuchać w innym pokoju).
app_is_busy() {  # $1 = nazwa procesu, $2 = nazwa aplikacji
    local proc="$1" app="$2"

    if [[ "$proc" == "Spotify" ]]; then
        local state
        # Uwaga: to zapytanie odpaliłoby Spotify, gdyby nie działał - stąd app_running wyżej.
        state=$(osa 5 -e 'tell application "Spotify" to player state as string')
        [[ "$state" == "playing" ]] && return 0
        [[ -n "$state" ]] && return 1
        # osascript bez uprawnień TCC - schodzimy na heurystykę CPU.
    fi

    local pid cpu
    pid=$(pgrep -x "$proc" 2>/dev/null | head -1)
    [[ -z "$pid" ]] && return 1
    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
    [[ -z "$cpu" ]] && return 1
    awk -v c="$cpu" -v t="$BUSY_CPU_PERCENT" 'BEGIN { exit !(c > t) }'
}

# ==========================================
# Akcje na aplikacjach
# ==========================================
slug() { print -r -- "${1// /-}"; }

quit_app() {  # $1 = nazwa procesu, $2 = nazwa aplikacji
    local proc="$1" app="$2" i

    osa 5 -e "tell application \"$app\" to quit" > /dev/null 2>&1
    for i in {1..10}; do
        app_running "$proc" || return 0
        sleep 0.5
    done

    pkill -x "$proc" > /dev/null 2>&1
    sleep 1
    if app_running "$proc"; then
        pkill -9 -x "$proc" > /dev/null 2>&1
        sleep 1
    fi
    ! app_running "$proc"
}

# Iteracja po konfiguracji "Proc|Aplikacja" (po linii na wpis).
for_each_app() {  # $1 = zawartość zmiennej, $2 = nazwa funkcji do wywołania
    local line proc app
    print -r -- "$1" | while IFS='|' read -r proc app; do
        [[ -z "$proc" ]] && continue
        "$2" "$proc" "$app"
    done
}

wants_relaunch() {  # $1 = nazwa procesu
    print -r -- "$RELAUNCH_APPS" | cut -d'|' -f1 | grep -qx "$1"
}

# ==========================================
# Tick
# ==========================================
quit_one() {
    local proc="$1" app="$2"
    app_running "$proc" || { say "  $app: nie działa"; return 0; }

    if app_is_busy "$proc" "$app"; then
        say "  $app: realnie zajęty (gra/pracuje) - zostawiam"
        return 0
    fi

    if quit_app "$proc" "$app"; then
        log "Ubiłem $app (bezczynność ${IDLE_MINUTES} min)."
        wants_relaunch "$proc" && touch "$STATE_DIR/quit-$(slug "$proc")"
    else
        log "OSTRZEŻENIE: nie udało się ubić $app."
    fi
}

# Osierocony strumień audio w procesie pomocniczym (Chromium AudioService).
# Nie zamykamy aplikacji - Chromium sam odtworzy helpera, gdy będzie potrzebny.
quit_helper() {
    local desc="$1" pattern="$2" pid cpu
    pid=$(pgrep -f "$pattern" 2>/dev/null | head -1)
    [[ -z "$pid" ]] && { say "  $desc: nie działa"; return 0; }

    if ! pid_holds_audio_assertion "$pid"; then
        say "  $desc: nie trzyma asercji audio - zostawiam"
        return 0
    fi

    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
    if [[ -n "$cpu" ]] && awk -v c="$cpu" -v t="$BUSY_CPU_PERCENT" 'BEGIN { exit !(c > t) }'; then
        say "  $desc: realnie odtwarza (${cpu}% CPU) - zostawiam"
        return 0
    fi

    if pkill -f "$pattern" > /dev/null 2>&1; then
        log "Ubiłem $desc - osierocony strumień audio (${cpu:-?}% CPU)."
    else
        say "  $desc: pkill nic nie ubił"
    fi
}

relaunch_one() {
    local proc="$1" app="$2"
    local marker="$STATE_DIR/quit-$(slug "$proc")"
    [[ -f "$marker" ]] || return 0

    if app_running "$proc"; then
        rm -f "$marker"                       # wrócił sam (albo z ręki) - marker nieaktualny
        return 0
    fi

    if open -ga "$app" 2>/dev/null; then
        log "Przywróciłem $app (użytkownik wrócił)."
        rm -f "$marker"
    else
        log "OSTRZEŻENIE: nie udało się uruchomić $app."
    fi
}

# Czy jest cokolwiek do przywrócenia (marker po naszym wieczornym sprzątaniu)?
has_pending_relaunch() {
    local f
    for f in "$STATE_DIR"/quit-*(N); do
        return 0
    done
    return 1
}

do_tick() {
    # Szybka ścieżka: w dzień, gdy nie ma też nic do przywrócenia, kończymy na samym
    # sprawdzeniu zegara - bez ioreg i bez pmset. Im mniej pracy przypada na tick,
    # tym mniej powodów, żeby maszyna w ogóle się rozbudziła.
    if ! in_cleanup_window && ! has_pending_relaunch; then
        say "Poza oknem sprzątania (${CLEANUP_FROM_HOUR}:00-${CLEANUP_TO_HOUR}:00), nic do przywrócenia - koniec."
        return 0
    fi

    local idle
    idle=$(hid_idle_seconds)

    if display_is_on || [[ "$idle" -lt "$PRESENCE_SECONDS" ]]; then
        say "Użytkownik obecny (bezczynność ${idle}s) - przywracam co trzeba."
        for_each_app "$RELAUNCH_APPS" relaunch_one
        return 0
    fi

    if [[ "$idle" -lt $(( IDLE_MINUTES * 60 )) ]]; then
        say "Bezczynność ${idle}s - za wcześnie (próg $(( IDLE_MINUTES * 60 ))s)."
        return 0
    fi

    # W ciągu dnia nie ruszamy niczego: przerwa w pracy to nie powód, żeby
    # użytkownik stracił Spotify czy Claude'a.
    if ! in_cleanup_window; then
        say "Poza oknem sprzątania (${CLEANUP_FROM_HOUR}:00-${CLEANUP_TO_HOUR}:00) - nie ruszam niczego."
        return 0
    fi

    say "Bezczynność ${idle}s, ekran zgaszony - sprzątam blokery snu."
    for_each_app "$QUIT_APPS" quit_one
    for_each_app "$QUIT_HELPERS" quit_helper
}

# ==========================================
# Tryby ręczne
# ==========================================
do_sleep() {
    log "Tryb --sleep: ubijam blokery i usypiam."
    print -r -- "$QUIT_APPS" | while IFS='|' read -r proc app; do
        [[ -z "$proc" ]] && continue
        app_running "$proc" || continue
        if quit_app "$proc" "$app"; then
            log "  ubity: $app"
            wants_relaunch "$proc" && touch "$STATE_DIR/quit-$(slug "$proc")"
        else
            log "  OSTRZEŻENIE: nie udało się ubić $app"
        fi
    done
    for_each_app "$QUIT_HELPERS" quit_helper
    log "pmset sleepnow"
    pmset sleepnow
}

do_status() {
    print -r -- "=== Asercje trzymające system (pmset -g assertions) ==="
    pmset -g assertions 2>/dev/null | sed -n '/Listed by owning/,/Kernel Assertions/p' | sed '$d'
    print -r --

    print -r -- "=== Bezczynność ==="
    local idle
    idle=$(hid_idle_seconds)
    print -r -- "  Od ostatniego ruchu : ${idle}s (próg ubijania: $(( IDLE_MINUTES * 60 ))s)"
    if display_is_on; then
        print -r -- "  Ekran               : włączony"
    else
        print -r -- "  Ekran               : zgaszony"
    fi
    if in_cleanup_window; then
        print -r -- "  Okno sprzątania     : TAK (${CLEANUP_FROM_HOUR}:00-${CLEANUP_TO_HOUR}:00)"
    else
        print -r -- "  Okno sprzątania     : nie, poza godzinami (${CLEANUP_FROM_HOUR}:00-${CLEANUP_TO_HOUR}:00)"
    fi
    print -r --

    print -r -- "=== Pilnowane aplikacje ==="
    print -r -- "$QUIT_APPS" | while IFS='|' read -r proc app; do
        [[ -z "$proc" ]] && continue
        local mark=""
        wants_relaunch "$proc" && mark=" (wraca po powrocie użytkownika)"
        if app_running "$proc"; then
            if app_is_busy "$proc" "$app"; then
                print -r -- "  $app: działa, ZAJĘTY - nie będzie ubity$mark"
            else
                print -r -- "  $app: działa, bezczynny - kandydat do ubicia$mark"
            fi
        else
            print -r -- "  $app: nie działa$mark"
        fi
    done
    print -r --

    print -r -- "=== Osierocone strumienie audio ==="
    print -r -- "$QUIT_HELPERS" | while IFS='|' read -r desc pattern; do
        [[ -z "$desc" ]] && continue
        local hpid hcpu
        hpid=$(pgrep -f "$pattern" 2>/dev/null | head -1)
        if [[ -z "$hpid" ]]; then
            print -r -- "  $desc: nie działa"
        else
            hcpu=$(ps -p "$hpid" -o %cpu= 2>/dev/null | tr -d ' ')
            if pid_holds_audio_assertion "$hpid"; then
                print -r -- "  $desc: pid $hpid, ${hcpu}% CPU, TRZYMA asercję audio - kandydat do ubicia"
            else
                print -r -- "  $desc: pid $hpid, ${hcpu}% CPU, nie blokuje snu"
            fi
        fi
    done
    print -r --

    print -r -- "=== Ostatnie przejścia zasilania ==="
    pmset -g log 2>/dev/null | grep -E "Entering Sleep state|DarkWake|Wake from" | tail -6
}

case "$MODE" in
    watch|once) do_tick ;;
    sleep)      do_sleep ;;
    status)     do_status ;;
esac
