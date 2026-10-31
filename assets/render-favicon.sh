#!/usr/bin/env bash
# Renderuje assets/icon-source.svg -> assets/favicon.png (192 px, przezroczyste rogi).
# Paseo bierze favicon.png jako ikonę projektu: kwadrat, <=32 KB. Źródło celowo NIE nazywa
# się favicon.svg - Paseo wybrałby SVG przed PNG, a SVG nie przechodzi jego testu kwadratu.
# Chrome headless potrzebuje gniazda w katalogu profilu, więc poza sandboxem.
set -euo pipefail
cd "$(dirname "$0")"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf '<html><body style="margin:0;background:transparent"><img src="file://%s/icon-source.svg" width="192" height="192" style="display:block"></body></html>' "$PWD" > "$work/i.html"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
  --user-data-dir="$work/profile" --hide-scrollbars --default-background-color=00000000 \
  --window-size=192,192 --screenshot="$PWD/favicon.png" "file://$work/i.html" > /dev/null 2>&1
ls -l favicon.png
