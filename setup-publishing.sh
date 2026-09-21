#!/bin/bash
set -e

# Publikowanie dokumentow - instalator projektu Cloudflare Pages.
# Idempotentny: możesz odpalać go dowolną liczbę razy, doprowadza konfigurację
# do stanu opisanego w scripts/publish.env.
#
# Po co: jeden projekt Pages = jedna subdomena = wiele niezależnych podfolderów
# (`<BASE_URL>/<slug>/`). Dokument wrzucasz przez scripts/publish.py i dostajesz
# link do wysłania komuś. Bez osobnej subdomeny na każdą dokumentację czy apkę.
#
# Użycie:
#   ./setup-publishing.sh            # instalacja / aktualizacja
#   ./setup-publishing.sh --status   # diagnostyka, nic nie zmienia
#   ./setup-publishing.sh --dry-run  # pokaż co by zrobił
#   ./setup-publishing.sh --uninstall

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# shellcheck source=scripts/publish.env
source "$PROJECT_ROOT/scripts/publish.env"

STATE_ROOT="$PROJECT_ROOT/$STATE_DIR"
SITE_ROOT="$STATE_ROOT/site"
MANIFEST="$STATE_ROOT/manifest.json"
CF_API="https://api.cloudflare.com/client/v4"

MODE_ACTION="install"
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --status)    MODE_ACTION="status" ;;
        --uninstall) MODE_ACTION="uninstall" ;;
        --dry-run)   DRY_RUN=1 ;;
        -h|--help)
            sed -n '4,17p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'
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

# --------------------------------------------------------------------------
# Konfiguracja

env_value() {
    # Czyta klucz z .env (bez source - .env bywa zawężony do KEY=VALUE, ale
    # nie chcemy wykonywać go shellem).
    local key="$1" file="$PROJECT_ROOT/.env"
    [ -f "$file" ] || return 0
    grep -E "^${key}=" "$file" | tail -1 | cut -d= -f2- | sed 's/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//'
}

CF_TOKEN="${CLOUDFLARE_API_TOKEN:-$(env_value CLOUDFLARE_API_TOKEN)}"
CF_ACCOUNT="${CLOUDFLARE_ACCOUNT_ID:-$(env_value CLOUDFLARE_ACCOUNT_ID)}"

token_hint() {
    cat <<'HINT'
  Brakuje danych dostępowych do Cloudflare. Jednorazowo:

    1. dash.cloudflare.com -> My Profile -> API Tokens -> Create Token -> Custom token
       uprawnienie: Account -> Cloudflare Pages -> Edit
       (Read nie wystarczy - deploy tworzy deployment, czyli jest zapisem)
    2. Account ID: 32-znakowy hex, najszybciej prosto z adresu dashboardu:
         https://dash.cloudflare.com/<TU_JEST_ACCOUNT_ID>/workers-and-pages
       Alternatywnie: dowolna domena -> Overview -> prawy panel -> Account ID.
    3. Dopisz do .env w tym repo:

         CLOUDFLARE_API_TOKEN=...
         CLOUDFLARE_ACCOUNT_ID=...

    4. Odpal ponownie: ./setup-publishing.sh

  Świadomie token, nie `wrangler login`: OAuth wranglera wygasa po cichu
  (tu już wygasł), a rutyna o 8:00 nie ma kogo poprosić o zalogowanie.
HINT
}

discover_account() {
    # Token z samym `Pages: Edit` NIE widzi listy kont (/accounts zwraca puste),
    # bo do tego trzeba `Account Settings: Read`. Jeśli jednak token to uprawnienie
    # ma, nie każemy użytkownikowi szukać ID po dashboardzie - dopisujemy je sami.
    local resp ids count
    resp="$(cf_api GET "/accounts?per_page=50" || true)"
    ids="$(printf '%s' "$resp" | python3 -c '
import json,sys
try:
    data = json.loads(sys.stdin.read() or "{}")
except ValueError:
    sys.exit(0)
for acc in (data.get("result") or []):
    print(acc.get("id", ""), acc.get("name", ""))
')"
    count="$(printf '%s' "$ids" | grep -c . || true)"
    [ "$count" = "1" ] || return 1
    CF_ACCOUNT="$(printf '%s' "$ids" | awk '{print $1}')"
    local name
    name="$(printf '%s' "$ids" | cut -d' ' -f2-)"
    echo -e "  ${GREEN}✓${NC} Account ID wykryty przez API: $CF_ACCOUNT ($name)"
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${YELLOW}[dry-run]${NC} dopisałbym CLOUDFLARE_ACCOUNT_ID do .env"
        return 0
    fi
    if grep -qE '^CLOUDFLARE_ACCOUNT_ID=' "$PROJECT_ROOT/.env" 2>/dev/null; then
        # macOS sed wymaga argumentu przy -i
        sed -i '' "s|^CLOUDFLARE_ACCOUNT_ID=.*|CLOUDFLARE_ACCOUNT_ID=$CF_ACCOUNT|" "$PROJECT_ROOT/.env"
    else
        printf '\nCLOUDFLARE_ACCOUNT_ID=%s\n' "$CF_ACCOUNT" >> "$PROJECT_ROOT/.env"
    fi
    echo -e "  ${GREEN}✓${NC} zapisany w .env"
}

require_credentials() {
    if [ -n "$CF_TOKEN" ] && [ -z "$CF_ACCOUNT" ]; then
        echo -e "${BLUE}Account ID${NC}"
        discover_account || {
            echo -e "  ${RED}✗ Token nie pozwala odpytać API o listę kont${NC}"
            echo "  (to normalne przy zakresie samego Pages: Edit - ID wklej ręcznie)"
            echo
            token_hint
            exit 1
        }
    fi
    if [ -z "$CF_TOKEN" ] || [ -z "$CF_ACCOUNT" ]; then
        echo -e "${RED}✗ Brak CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID${NC}"
        token_hint
        exit 1
    fi
}

cf_api() {
    # cf_api METODA SCIEZKA [BODY_JSON]
    local method="$1" path="$2" body="${3:-}"
    if [ -n "$body" ]; then
        curl -sS -X "$method" "$CF_API$path" \
            -H "Authorization: Bearer $CF_TOKEN" \
            -H "Content-Type: application/json" \
            --data "$body"
    else
        curl -sS -X "$method" "$CF_API$path" \
            -H "Authorization: Bearer $CF_TOKEN"
    fi
}

json_get() {
    # json_get '<json>' 'sciezka.do.pola'  (stdlib Pythona, bez jq)
    python3 -c '
import json,sys
data = json.loads(sys.stdin.read() or "{}")
for part in sys.argv[1].split("."):
    if isinstance(data, list):
        data = data[int(part)] if part.isdigit() and int(part) < len(data) else None
    elif isinstance(data, dict):
        data = data.get(part)
    else:
        data = None
    if data is None:
        break
print("" if data is None else data)
' "$1"
}

# --------------------------------------------------------------------------
# Kroki

check_deps() {
    echo -e "${BLUE}Zależności${NC}"
    local missing=0
    for tool in curl python3 node npx uv; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} $tool"
        else
            echo -e "  ${RED}✗${NC} $tool (brak)"
            missing=1
        fi
    done
    if [ "$missing" = "1" ]; then
        echo -e "${RED}Zainstaluj brakujące narzędzia i odpal ponownie.${NC}"
        echo "  uv:   brew install uv        (render Markdown -> HTML)"
        echo "  node: brew install node      (npx wrangler, deploy)"
        exit 1
    fi
}

check_token() {
    echo -e "${BLUE}Token Cloudflare${NC}"
    local resp ok
    resp="$(cf_api GET "/accounts/$CF_ACCOUNT/pages/projects?per_page=1" || true)"
    ok="$(printf '%s' "$resp" | json_get success)"
    if [ "$ok" != "True" ] && [ "$ok" != "true" ]; then
        echo -e "  ${RED}✗${NC} token odrzucony przez API"
        printf '%s\n' "$resp" | head -c 600
        echo
        echo "  Sprawdź uprawnienie Account -> Cloudflare Pages -> Edit oraz Account ID."
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} token działa (konto ${CF_ACCOUNT:0:8}…)"
}

project_exists() {
    local resp
    resp="$(cf_api GET "/accounts/$CF_ACCOUNT/pages/projects/$PAGES_PROJECT")"
    local ok
    ok="$(printf '%s' "$resp" | json_get success)"
    [ "$ok" = "True" ] || [ "$ok" = "true" ]
}

ensure_project() {
    echo -e "${BLUE}Projekt Pages: $PAGES_PROJECT${NC}"
    if project_exists; then
        local branch
        branch="$(cf_api GET "/accounts/$CF_ACCOUNT/pages/projects/$PAGES_PROJECT" | json_get result.production_branch)"
        echo -e "  ${GREEN}✓${NC} istnieje -> $BASE_URL (gałąź produkcyjna: ${branch:-?})"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${YELLOW}[dry-run]${NC} utworzyłbym projekt $PAGES_PROJECT"
        return 0
    fi
    echo "  tworzę…"
    local resp ok
    resp="$(cf_api POST "/accounts/$CF_ACCOUNT/pages/projects" \
        "{\"name\":\"$PAGES_PROJECT\",\"production_branch\":\"main\"}")"
    ok="$(printf '%s' "$resp" | json_get success)"
    if [ "$ok" != "True" ] && [ "$ok" != "true" ]; then
        echo -e "  ${RED}✗ nie udało się utworzyć projektu${NC}"
        printf '%s\n' "$resp" | head -c 600
        echo
        echo "  Najczęstsza przyczyna: nazwa (czyli subdomena $PAGES_PROJECT.pages.dev)"
        echo "  jest zajęta globalnie. Zmień PAGES_PROJECT i BASE_URL w scripts/publish.env"
        echo "  (np. kedrzu-docs) i odpal ponownie."
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} utworzony -> $BASE_URL"
}

seed_site() {
    echo -e "${BLUE}Lustro serwisu: $STATE_DIR/site/${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${YELLOW}[dry-run]${NC} założyłbym $SITE_ROOT (index.html, robots.txt, _headers, manifest.json)"
        return 0
    fi
    mkdir -p "$SITE_ROOT"
    mkdir -p "$STATE_ROOT"

    # Strona główna celowo NIE listuje dokumentów - cała ochrona opiera się na tym,
    # że linku nie da się zgadnąć ani wyklikać.
    if [ ! -f "$SITE_ROOT/index.html" ]; then
        cat > "$SITE_ROOT/index.html" <<'HTML'
<!doctype html>
<html lang="pl">
<meta charset="utf-8">
<meta name="robots" content="noindex, nofollow">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>—</title>
<style>
  body { font: 16px/1.6 -apple-system, system-ui, sans-serif; color: #444;
         display: grid; place-items: center; min-height: 100vh; margin: 0; }
</style>
<p>Nic tu nie ma.</p>
HTML
        echo -e "  ${GREEN}✓${NC} index.html (neutralny, bez listy dokumentów)"
    fi

    # Bez 404.html Pages serwuje na nieistniejacej sciezce strone glowna z kodem 200.
    # Chcemy uczciwego 404 - inaczej kazdy zgadywany slug "istnieje".
    if [ ! -f "$SITE_ROOT/404.html" ]; then
        cat > "$SITE_ROOT/404.html" <<'HTML'
<!doctype html>
<html lang="pl">
<meta charset="utf-8">
<meta name="robots" content="noindex, nofollow">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>404</title>
<style>
  body { font: 16px/1.6 -apple-system, system-ui, sans-serif; color: #444;
         display: grid; place-items: center; min-height: 100vh; margin: 0; }
</style>
<p>Nic tu nie ma.</p>
HTML
        echo -e "  ${GREEN}✓${NC} 404.html (nieistniejące ścieżki dostają 404, nie 200)"
    fi

    if [ ! -f "$SITE_ROOT/robots.txt" ]; then
        printf 'User-agent: *\nDisallow: /\n' > "$SITE_ROOT/robots.txt"
        echo -e "  ${GREEN}✓${NC} robots.txt"
    fi

    if [ ! -f "$SITE_ROOT/_headers" ]; then
        cat > "$SITE_ROOT/_headers" <<'HEADERS'
/*
  X-Robots-Tag: noindex, nofollow, noarchive
  Referrer-Policy: no-referrer
HEADERS
        echo -e "  ${GREEN}✓${NC} _headers (noindex dla całego serwisu)"
    fi

    if [ ! -f "$MANIFEST" ]; then
        printf '{"documents": []}\n' > "$MANIFEST"
        echo -e "  ${GREEN}✓${NC} manifest.json"
    fi

    # Bezpiecznik: lustro nigdy nie może trafić do publicznego repo.
    if ! grep -qx "$STATE_DIR/" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        printf '\n# Lustro publikowanych dokumentow (repo jest publiczne!)\n%s/\n' "$STATE_DIR" \
            >> "$PROJECT_ROOT/.gitignore"
        echo -e "  ${GREEN}✓${NC} .gitignore += $STATE_DIR/"
    fi
}

first_deploy() {
    echo -e "${BLUE}Pierwszy deploy${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${YELLOW}[dry-run]${NC} npx wrangler@$WRANGLER_VERSION pages deploy $STATE_DIR/site --project-name $PAGES_PROJECT"
        return 0
    fi
    run "$PROJECT_ROOT/scripts/publish.py" deploy
}

do_status() {
    echo -e "${BLUE}Publikowanie dokumentów - status${NC}"
    echo "  projekt Pages : $PAGES_PROJECT"
    echo "  adres bazowy  : $BASE_URL"
    echo "  lustro        : $SITE_ROOT"
    echo "  stan (lokalny): $MANIFEST"

    if [ -z "$CF_TOKEN" ] || [ -z "$CF_ACCOUNT" ]; then
        echo -e "  ${RED}✗${NC} brak CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID w .env"
    else
        if project_exists; then
            local branch
            branch="$(cf_api GET "/accounts/$CF_ACCOUNT/pages/projects/$PAGES_PROJECT" | json_get result.production_branch)"
            echo -e "  ${GREEN}✓${NC} projekt istnieje w Cloudflare (gałąź produkcyjna: ${branch:-?})"
        else
            echo -e "  ${YELLOW}!${NC} projektu nie ma (albo token nie ma do niego dostępu)"
        fi
    fi

    if [ -f "$MANIFEST" ]; then
        local count
        count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["documents"]))' "$MANIFEST" 2>/dev/null || echo "?")"
        echo -e "  ${GREEN}✓${NC} opublikowanych dokumentów: $count"
    else
        echo -e "  ${YELLOW}!${NC} brak lustra - odpal ./setup-publishing.sh"
    fi

    if [ -d "$STATE_ROOT/trash" ]; then
        echo "  w koszu       : $(find "$STATE_ROOT/trash" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    fi
}

do_uninstall() {
    echo -e "${BLUE}Odinstalowanie${NC}"
    echo "  Świadomie NIE kasuję ani projektu w Cloudflare, ani lustra - to Twoje dane"
    echo "  i Twoja decyzja. Żeby wycofać publikowanie w całości:"
    echo
    echo "    1. zdejmij dokumenty:  ./scripts/publish.py list   (potem unpublish po kolei)"
    echo "    2. usuń projekt:       dash.cloudflare.com -> Workers & Pages -> $PAGES_PROJECT -> Settings -> Delete"
    echo "    3. lustro lokalne:     $STATE_ROOT"
    echo "    4. token:              usuń CLOUDFLARE_* z .env i skasuj token w dashboardzie"
}

# --------------------------------------------------------------------------

case "$MODE_ACTION" in
    status)
        do_status
        ;;
    uninstall)
        do_uninstall
        ;;
    install)
        check_deps
        require_credentials
        check_token
        ensure_project
        seed_site
        first_deploy
        echo
        echo -e "${GREEN}Gotowe.${NC} Publikowanie:"
        echo "  ./scripts/publish.py add ./raport.md"
        echo "  ./scripts/publish.py add ./apka/ --spa"
        echo "  ./scripts/publish.py list"
        ;;
esac
