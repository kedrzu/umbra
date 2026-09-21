#!/bin/zsh
# Przepięcie mikrofonu fifine bez dotykania kabla.
#
# Firmware MV-SILICON w fifine wiesza endpoint izochroniczny IN po zbyt szybkich
# cyklach start/stop strumienia (push-to-talk Wispr Flow). Objaw: mikrofon jest
# widoczny w systemie i ustawiony jako domyślne wejście, ale nie oddaje próbek —
# w logu leci `AUAInputTransferManager_completeBlock USB underflow`, a sterownik
# eskaluje lockDelayMS 24 → 550 i się poddaje.
#
# Restart sterownika (killall usbaudiod) NIE pomaga — usterka siedzi w urządzeniu.
# Pomaga wyłącznie odcięcie zasilania portu, czyli to, co robi ten skrypt.
#
# Port jest szukany po VID:PID, więc skrypt przeżywa przepięcie huba czy doku.

set -euo pipefail

VIDPID="3142:0068"   # MV-SILICON fifine Microphone
UHUBCTL="${UHUBCTL:-/opt/homebrew/bin/uhubctl}"

if [[ ! -x "$UHUBCTL" ]]; then
  print -u2 "Brak uhubctl ($UHUBCTL). Zainstaluj: brew install uhubctl"
  exit 1
fi

location=$("$UHUBCTL" | awk -v vidpid="$VIDPID" '
  /^Current status for hub /  { hub = $5 }
  /^  Port [0-9]+:/ && index($0, vidpid) { sub(":", "", $2); print hub, $2; exit }
')

if [[ -z "$location" ]]; then
  print -u2 "Nie znalazłem mikrofonu ($VIDPID) na żadnym hubie — sprawdź, czy jest wpięty."
  exit 1
fi

hub="${location%% *}"
port="${location##* }"

print "Przepinam fifine na hubie $hub, port $port…"
"$UHUBCTL" -l "$hub" -p "$port" -a cycle -d 2

print "Gotowe. Sprawdź poziom wejścia w Ustawieniach dźwięku."
