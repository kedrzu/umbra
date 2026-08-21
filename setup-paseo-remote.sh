#!/bin/bash
set -e

# Zdalny dostęp do demona Paseo z apki mobilnej - instalator
# Idempotentny: możesz odpalać go dowolną liczbę razy, doprowadza konfigurację
# do stanu opisanego w scripts/paseo-remote.env.
#
# Rozwiązuje dwa problemy, które wychodzą po każdej zmianie nazwy maszyny
# w Tailscale (rename gubi jedno i drugie):
#   1) 403 "Invalid Host header" - demon trzyma allowlistę nazw w
#      config.json (daemon.hostnames), a rename zostawia tam starą nazwę
#   2) błąd TLS (OSStatus -9847) - demon mówi czystym HTTP, HTTPS terminuje
#      `tailscale serve`, którego konfiguracja jest przypięta do nazwy węzła
#
# Użycie:
#   ./setup-paseo-remote.sh                     # instalacja / aktualizacja
#   ./setup-paseo-remote.sh --status            # diagnostyka, nic nie zmienia
#   ./setup-paseo-remote.sh --dry-run           # pokaż co by zrobił
#   ./setup-paseo-remote.sh --rotate-password   # wygeneruj nowe hasło demona
#   ./setup-paseo-remote.sh --restart           # przeładuj demona po zmianach
#   ./setup-paseo-remote.sh --uninstall         # zdejmij tailscale serve
#
# UWAGA: --restart ubija demona, a więc i wszystkie działające pod nim agenty
# (łącznie z tym, który ewentualnie odpala ten skrypt). Dlatego restart NIE
# jest domyślny - zmiany w config.json wchodzą dopiero po przeładowaniu.

# This script lives at the project root; resolve it regardless of the caller's cwd.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# shellcheck source=scripts/paseo-remote.env
source "$PROJECT_ROOT/scripts/paseo-remote.env"

CONFIG_FILE="$PASEO_DIR/config.json"
ENV_FILE="$PASEO_DIR/.env"

MODE_ACTION="install"
DRY_RUN=0
ROTATE_PASSWORD=0
DO_RESTART=0

for arg in "$@"; do
    case "$arg" in
        --status)          MODE_ACTION="status" ;;
        --uninstall)       MODE_ACTION="uninstall" ;;
        --dry-run)         DRY_RUN=1 ;;
        --rotate-password) ROTATE_PASSWORD=1 ;;
        --restart)         DO_RESTART=1 ;;
        -h|--help)
            sed -n '3,27p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'
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

# --- Tailscale -----------------------------------------------------------

# Mac App Store buduje Tailscale bez CLI w bundlu, Homebrew instaluje sam CLI.
# Bierzemy pierwszy, który faktycznie gada z lokalnym tailscaled.
find_tailscale() {
    local candidate
    for candidate in \
        /Applications/Tailscale.app/Contents/MacOS/Tailscale \
        "$(command -v tailscale 2>/dev/null)"; do
        [ -n "$candidate" ] && [ -x "$candidate" ] || continue
        if "$candidate" status --json >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

TS="$(find_tailscale || true)"
if [ -z "$TS" ]; then
    echo -e "${RED}Nie znalazłem działającego CLI Tailscale.${NC}"
    echo "  Sprawdź, czy Tailscale chodzi i czy jesteś zalogowany."
    exit 1
fi

# Aktualna nazwa MagicDNS maszyny - jedyne źródło prawdy po rename.
magic_dns_name() {
    "$TS" status --json 2>/dev/null | python3 -c "
import json,sys
d = json.load(sys.stdin)
print((d.get('Self') or {}).get('DNSName','').rstrip('.'))
"
}

# tailscaled w trybie userspace (macOS GUI/App Store) sam binduje port TLS na
# adresach tailnetu. Jeśli ktoś zajmuje ten port na *:PORT, bind się nie uda,
# handshake przejmie tamten proces i dostaniesz TLS alert 80 zamiast Paseo.
port_squatter() {
    local port="$1"
    # +c 0 wyłącza obcinanie nazwy procesu do 9 znaków - bez tego sam Tailscale
    # ("IPNExtension" -> "IPNExtens") nie pasuje do wyjątku i robi fałszywy alarm.
    lsof +c 0 -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null \
        | awk 'NR>1 && $1 !~ /^(tailscaled|IPNExtension|Tailscale)/ {print $1" (pid "$2")"; exit}'
}

serve_target() {
    "$TS" serve status --json 2>/dev/null | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(''); raise SystemExit
web = d.get('Web') or {}
for host, cfg in web.items():
    for path, h in (cfg.get('Handlers') or {}).items():
        if path == '/' and h.get('Proxy'):
            print(f\"{host} -> {h['Proxy']}\")
print('', end='')
"
}

# --- config.json ---------------------------------------------------------

config_hostnames() {
    [ -f "$CONFIG_FILE" ] || { echo ""; return; }
    python3 -c "
import json,sys
c = json.load(open('$CONFIG_FILE'))
print(' '.join((c.get('daemon') or {}).get('hostnames') or []))
"
}

# Buduje docelową allowlistę: bazowe hosty + aktualna nazwa MagicDNS.
# Stare wpisy *.ts.net lecą, gdy PRUNE_STALE_TSNET=1 - to one robią te 403.
desired_hostnames() {
    local dns="$1"
    python3 - "$dns" <<PY
import sys
dns = sys.argv[1]
base = "$PASEO_BASE_HOSTNAMES".split()
prune = "$PRUNE_STALE_TSNET" == "1"
current = "$(config_hostnames)".split()

out = list(base)
if not prune:
    for h in current:
        if h not in out and h.endswith('.ts.net'):
            out.append(h)
for h in current:
    if h not in out and not h.endswith('.ts.net') and h not in base:
        out.append(h)
if dns and dns not in out:
    out.append(dns)
print(' '.join(out))
PY
}

write_hostnames() {
    local desired="$1"
    python3 - "$desired" <<PY
import json, shutil, sys
path = "$CONFIG_FILE"
desired = sys.argv[1].split()
cfg = json.load(open(path))
daemon = cfg.setdefault('daemon', {})
if daemon.get('hostnames') == desired:
    print('unchanged')
    raise SystemExit
shutil.copyfile(path, path + '.bak-paseo-remote')
daemon['hostnames'] = desired
json.dump(cfg, open(path, 'w'), indent=2, ensure_ascii=False)
open(path, 'a').write('\n')
print('updated')
PY
}

# --- Hasło ---------------------------------------------------------------

rotate_password() {
    local new
    new="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$PASSWORD_LENGTH")"
    python3 - "$new" <<PY
import os, sys
path = "$ENV_FILE"
key = "$PASSWORD_ENV_KEY"
new = sys.argv[1]
lines = []
if os.path.exists(path):
    lines = open(path).read().splitlines()
found = False
for i, line in enumerate(lines):
    if line.split('=', 1)[0].strip() == key:
        lines[i] = f"{key}={new}"
        found = True
if not found:
    lines.append(f"{key}={new}")
with open(path, 'w') as fh:
    fh.write('\n'.join(lines) + '\n')
os.chmod(path, 0o600)
PY
    echo -e "  ${GREEN}✓${NC} nowe hasło zapisane w $ENV_FILE"
    echo -e "  ${YELLOW}Odczytaj je u siebie:${NC} grep $PASSWORD_ENV_KEY $ENV_FILE"
}

# --- Akcje ---------------------------------------------------------------

do_status() {
    local dns current desired serve
    dns="$(magic_dns_name)"
    current="$(config_hostnames)"
    desired="$(desired_hostnames "$dns")"
    serve="$(serve_target)"

    echo -e "${BLUE}Paseo - zdalny dostęp: diagnostyka${NC}"
    echo
    echo "  Nazwa MagicDNS   : ${dns:-<brak>}"
    echo "  Demon nasłuchuje : 0.0.0.0:$PASEO_PORT (HTTP)"
    echo
    echo "  Allowlista hostów (config.json):"
    echo "    jest : ${current:-<brak>}"
    echo "    ma być: $desired"
    if [ "$current" = "$desired" ]; then
        echo -e "    ${GREEN}✓ aktualna${NC}"
    else
        echo -e "    ${RED}✗ nieaktualna - stąd 403 \"Invalid Host header\"${NC}"
    fi
    echo
    echo "  TLS (tailscale serve, port $TLS_PORT):"
    if [ -n "$serve" ]; then
        echo -e "    ${GREEN}✓${NC} $serve"
    else
        echo -e "    ${RED}✗ brak - stąd błąd handshake TLS (OSStatus -9847)${NC}"
    fi
    local squatter
    squatter="$(port_squatter "$TLS_PORT")"
    if [ -n "$squatter" ]; then
        echo -e "    ${RED}✗ port $TLS_PORT zajmuje $squatter - tailscaled go nie zabinduje${NC}"
    fi
    echo
    if [ -n "$dns" ]; then
        echo "  Test z tej maszyny:"
        echo "    curl -H 'Host: $dns' http://127.0.0.1:$PASEO_PORT/api/health"
    fi
}

do_install() {
    local dns desired result serve
    dns="$(magic_dns_name)"
    if [ -z "$dns" ]; then
        echo -e "${RED}Nie odczytałem nazwy MagicDNS z Tailscale.${NC}"
        exit 1
    fi

    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Paseo - zdalny dostęp przez Tailscale               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "  Maszyna: ${GREEN}$dns${NC}"
    echo

    # --- 1. Allowlista hostów ---
    echo -e "${YELLOW}Allowlista hostów demona...${NC}"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "  ${RED}Brak $CONFIG_FILE${NC}"
        exit 1
    fi
    desired="$(desired_hostnames "$dns")"
    echo "  docelowo: $desired"
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${YELLOW}[dry-run]${NC} zapis do $CONFIG_FILE"
    else
        result="$(write_hostnames "$desired")"
        if [ "$result" = "updated" ]; then
            echo -e "  ${GREEN}✓${NC} zaktualizowano (backup: $CONFIG_FILE.bak-paseo-remote)"
            NEEDS_RESTART=1
        else
            echo -e "  ${GREEN}✓${NC} już aktualna"
        fi
    fi
    echo

    # --- 2. TLS ---
    if [ "$TLS_ENABLED" = "1" ]; then
        echo -e "${YELLOW}TLS (tailscale serve)...${NC}"
        squatter="$(port_squatter "$TLS_PORT")"
        if [ -n "$squatter" ]; then
            echo -e "  ${RED}✗ port $TLS_PORT zajmuje: $squatter${NC}"
            echo "    tailscaled nie zabinduje tego portu, a handshake przejmie tamten"
            echo "    proces - dostaniesz TLS alert 80 (OSStatus -9847), nie Paseo."
            echo "    Zmień TLS_PORT w scripts/paseo-remote.env na wolny port."
            exit 1
        fi
        serve="$(serve_target)"
        if echo "$serve" | grep -q "^$dns:$TLS_PORT -> http://127.0.0.1:$PASEO_PORT$"; then
            echo -e "  ${GREEN}✓${NC} już wystawione: $serve"
        else
            run "$TS" serve --bg --https="$TLS_PORT" "$PASEO_PORT"
            if [ "$DRY_RUN" != "1" ]; then
                echo -e "  ${GREEN}✓${NC} https://$dns:$TLS_PORT -> 127.0.0.1:$PASEO_PORT"
            fi
        fi
        echo
    fi

    # --- 3. Hasło ---
    if [ "$ROTATE_PASSWORD" = "1" ]; then
        echo -e "${YELLOW}Rotacja hasła demona...${NC}"
        if [ "$DRY_RUN" = "1" ]; then
            echo -e "  ${YELLOW}[dry-run]${NC} nowe hasło -> $ENV_FILE"
        else
            rotate_password
            NEEDS_RESTART=1
        fi
        echo
    fi

    # --- 4. Restart ---
    if [ "${NEEDS_RESTART:-0}" = "1" ] || [ "$DO_RESTART" = "1" ]; then
        if [ "$DO_RESTART" = "1" ]; then
            echo -e "${YELLOW}Restart demona...${NC}"
            run osascript -e 'quit app "Paseo"'
            run sleep 3
            run open -a Paseo
            echo -e "  ${GREEN}✓${NC} demon przeładowany"
        else
            echo -e "${YELLOW}⚠ Zmiany w config.json/.env wchodzą po restarcie demona.${NC}"
            echo "  Zrób to sam (restart ubija działające agenty):"
            echo "    ./setup-paseo-remote.sh --restart"
            echo "  albo zrestartuj Paseo z menu bar."
        fi
        echo
    fi

    # --- 5. Podsumowanie ---
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                      Gotowe!                               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    if [ "$DRY_RUN" != "1" ]; then
        echo "  W apce mobilnej:"
        echo "    Host  : $dns"
        echo "    Port  : $TLS_PORT (HTTPS)"
        echo "    Hasło : grep $PASSWORD_ENV_KEY $ENV_FILE"
        echo
        echo "  Diagnostyka: ./setup-paseo-remote.sh --status"
    fi
}

do_uninstall() {
    echo -e "${YELLOW}Zdejmuję tailscale serve...${NC}"
    run "$TS" serve --https="$TLS_PORT" off || true
    echo -e "  ${GREEN}✓${NC} zdjęte"
    echo
    echo "  Allowlista hostów w $CONFIG_FILE zostaje bez zmian."
}

case "$MODE_ACTION" in
    status)    do_status ;;
    uninstall) do_uninstall ;;
    install)   do_install ;;
esac
