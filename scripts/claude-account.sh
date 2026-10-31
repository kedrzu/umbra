#!/usr/bin/env bash
# Przełączanie kont Claude Code bez osobnych profili/folderów.
#
# Claude Code na macOS trzyma logowanie w dwóch miejscach:
#   - Keychain, pozycja "Claude Code-credentials" (tokeny OAuth, JSON)
#   - ~/.claude.json, klucz "oauthAccount" (kto jest zalogowany: email, organizacja)
# Skrypt odkłada parę (tokeny + oauthAccount) do ~/.claude-accounts/<nazwa>/ i przywraca ją.
#
# Użycie:
#   claude-account.sh save <nazwa>   # zapisz aktualnie zalogowane konto pod nazwą
#   claude-account.sh use <nazwa>    # przełącz na zapisane konto
#   claude-account.sh list           # zapisane konta, * = aktywne
#   claude-account.sh current        # kto jest teraz zalogowany
#
# Tokeny OAuth się rotują: po odświeżeniu stary refresh token przestaje działać. Dlatego `use`
# przed przełączeniem zawsze odświeża backup aktywnego konta — inaczej powrót na nie skończyłby się
# ponownym logowaniem.

set -euo pipefail

SERVICE="Claude Code-credentials"
ACCOUNT="${USER}"
CLAUDE_JSON="${HOME}/.claude.json"
STORE="${CLAUDE_ACCOUNTS_DIR:-${HOME}/.claude-accounts}"

die() { echo "błąd: $*" >&2; exit 1; }

valid_creds() { jq -e '.claudeAiOauth.refreshToken' >/dev/null 2>&1 <<<"$1"; }

# `security -w` wypisuje dane w hex, gdy nie są czystym tekstem — wtedy dekodujemy.
# Zwraca błąd, gdy w Keychain nie ma poprawnych tokenów (np. pozycja ucięta).
read_keychain() {
  local raw
  raw=$(security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null) \
    || die "brak pozycji \"$SERVICE\" w Keychain — zaloguj się najpierw przez /login"
  valid_creds "$raw" || raw=$(xxd -r -p <<<"$raw" 2>/dev/null || true)
  valid_creds "$raw" || return 1
  printf '%s' "$raw"
}

# Bez `security -i`: tryb interaktywny tnie linie po ~4 KB, a tokeny z mcpOAuth są dłuższe.
# Cena: przez ułamek sekundy tokeny są w argv procesu `security`.
write_keychain() {
  security add-generic-password -U -a "$ACCOUNT" -s "$SERVICE" -w "$1"
  [[ "$(read_keychain)" == "$1" ]] || die "zapis do Keychain się nie powiódł (odczyt różni się od zapisu)"
}

live_uuid() { jq -r '.oauthAccount.accountUuid // empty' "$CLAUDE_JSON"; }

# Nazwa zapisanego konta, które jest teraz zalogowane (po accountUuid), albo pusto.
active_name() {
  local uuid dir
  uuid=$(live_uuid)
  [[ -n "$uuid" && -d "$STORE" ]] || return 0
  for dir in "$STORE"/*/; do
    [[ -f "$dir/oauthAccount.json" ]] || continue
    if [[ "$(jq -r '.accountUuid' "$dir/oauthAccount.json")" == "$uuid" ]]; then
      basename "$dir"
      return 0
    fi
  done
}

save() {
  local name="$1" dir="$STORE/$1" creds
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "nazwa może mieć tylko litery, cyfry, . _ -"
  [[ -n "$(live_uuid)" ]] || die "w $CLAUDE_JSON nie ma oauthAccount — zaloguj się najpierw"
  creds=$(read_keychain) || die "tokeny w Keychain są uszkodzone — zrób /login i zapisz ponownie"
  (umask 077; mkdir -p "$dir")
  chmod 700 "$STORE" "$dir"
  (umask 077
   printf '%s' "$creds" > "$dir/credentials.json.tmp"
   jq '.oauthAccount' "$CLAUDE_JSON" > "$dir/oauthAccount.json.tmp")
  mv "$dir/credentials.json.tmp" "$dir/credentials.json"
  mv "$dir/oauthAccount.json.tmp" "$dir/oauthAccount.json"
  echo "zapisano '$name' ($(jq -r '.emailAddress' "$dir/oauthAccount.json"))"
}

warn_running() {
  if pgrep -x claude >/dev/null 2>&1; then
    echo "uwaga: działają sesje Claude Code — przełączenie obejmie NOWE sesje; działająca sesja," >&2
    echo "       która odświeży token, może nadpisać go z powrotem swoim kontem." >&2
  fi
}

use() {
  local name="$1" dir="$STORE/$1" current tmp
  [[ -f "$dir/credentials.json" && -f "$dir/oauthAccount.json" ]] || die "nie ma zapisanego konta '$name' (zobacz: list)"
  valid_creds "$(cat "$dir/credentials.json")" || die "kopia '$name' jest uszkodzona — zaloguj się na to konto i zrób: save $name"

  current=$(active_name)
  if [[ "$current" == "$name" ]]; then
    echo "'$name' jest już aktywne"
    return 0
  fi
  if [[ -n "$current" ]]; then
    # odśwież rotowane tokeny aktywnego konta; gdy Keychain jest uszkodzony, zostaje stara kopia
    ( save "$current" >/dev/null ) || echo "uwaga: nie odświeżono kopii '$current', została poprzednia" >&2
  elif [[ -n "$(live_uuid)" ]]; then
    die "aktywne konto ($(jq -r '.oauthAccount.emailAddress' "$CLAUDE_JSON")) nie jest zapisane — najpierw: save <nazwa>, inaczej przepadnie"
  fi

  warn_running
  write_keychain "$(cat "$dir/credentials.json")"

  cp -p "$CLAUDE_JSON" "$STORE/.claude.json.bak"
  tmp=$(mktemp "${CLAUDE_JSON}.XXXXXX")
  jq --slurpfile acct "$dir/oauthAccount.json" '.oauthAccount = $acct[0]' "$CLAUDE_JSON" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$CLAUDE_JSON"

  echo "przełączono na '$name' ($(jq -r '.emailAddress' "$dir/oauthAccount.json"))"
}

list() {
  local active dir n
  [[ -d "$STORE" ]] || { echo "brak zapisanych kont"; return 0; }
  active=$(active_name)
  for dir in "$STORE"/*/; do
    [[ -f "$dir/oauthAccount.json" ]] || continue
    n=$(basename "$dir")
    printf '%s %-12s %s  %s\n' "$([[ "$n" == "$active" ]] && echo '*' || echo ' ')" "$n" \
      "$(jq -r '.emailAddress' "$dir/oauthAccount.json")" \
      "$(jq -r '.organizationName // ""' "$dir/oauthAccount.json")"
  done
}

current() {
  local n
  n=$(active_name)
  echo "$(jq -r '.oauthAccount.emailAddress // "niezalogowany"' "$CLAUDE_JSON")${n:+ ($n)}"
}

case "${1:-}" in
  save)    [[ $# -eq 2 ]] || die "użycie: $0 save <nazwa>"; save "$2" ;;
  use)     [[ $# -eq 2 ]] || die "użycie: $0 use <nazwa>";  use "$2" ;;
  list)    list ;;
  current) current ;;
  *)       sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
