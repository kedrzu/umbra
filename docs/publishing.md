# Publikowanie dokumentów — Cloudflare Pages

Prosty sposób, żeby wrzucić dokument (HTML, Markdown, albo cały folder z apką) do internetu i dostać **link do wysłania komuś**. Jedna subdomena, wiele niezależnych podfolderów:

```
https://kedrzu.pages.dev/raport-remont-7f3a91/
https://kedrzu.pages.dev/kosztorys-2b1d04/
```

Bez osobnego projektu i osobnej subdomeny na każdą dokumentację — to był warunek wyjściowy.

## Zasady

- **Rozmawiasz z CLI, nie z plikami.** `scripts/publish.py` to stabilny kontrakt; układ katalogów pod spodem może się zmienić. Nie edytuj `published/` ręcznie (jedyny wyjątek: podmiana treści w `site/<slug>/` + `publish.py deploy`).
- **Nic nie jest kasowane.** Jak w `ledger.py` i `todoist.py` nie ma podkomendy `delete`. `unpublish` przenosi dokument do `published/trash/` i zdejmuje go z serwera — treść zostaje na dysku.
- **Adres wybiera wywołujący.** `--slug` jest brany dosłownie; skrypt nie dokleja własnej losowości. Czytelny `/garderoba/` dla rzeczy, które ktoś przepisze z kartki; `/wyniki-7f3a91c4/` z **samodzielnie dolosowanym** sufiksem dla treści, która nie powinna być do zgadnięcia. To ocena treści — dlatego zapada u wywołującego, nie w konfiguracji.
- **Ochroną jest nieodgadywalność linku, nie autoryzacja.** Serwis ma `robots.txt`, nagłówek `X-Robots-Tag: noindex` i stronę główną, która **nie listuje** dokumentów, ale kto ma link, ten wejdzie. Nie publikuj tu rzeczy, których ujawnienie byłoby katastrofą (na to jest Cloudflare Access, patrz „Czego tu nie ma").
- **Adres jest stabilny.** Nie ma zmiany sluga — raz wysłany link ma dalej działać. Nowa treść pod tym samym adresem → `update` (albo `add` tego samego źródła, patrz niżej).

## Układ

```
published/                    # w .gitignore — repo kedrzu/umbra jest PUBLICZNE
├── manifest.json             # spis slugów — ZOSTAJE lokalnie
├── trash/                    # zdjęte i nadpisane wersje — ZOSTAJĄ lokalnie
└── site/                     # JEDYNY katalog wysyłany na Pages
    ├── index.html            # neutralna strona główna, bez listy dokumentów
    ├── robots.txt            # Disallow: /
    ├── _headers              # noindex, nofollow, noarchive dla /*
    ├── _redirects            # generowany: fallback SPA dla slugów z --spa
    └── <slug>/…              # jeden dokument = jeden podfolder
```

Manifest i kosz leżą **poza** `site/` świadomie: manifest to lista wszystkich slugów, więc wysłany na serwer oddałby pod `/manifest.json` dokładnie to, co ma być nie do zgadnięcia.

Cloudflare Pages deployuje cały katalog jako jeden serwis — dlatego źródłem prawdy jest lokalne lustro. Wrangler liczy hashe i wysyła tylko brakujące pliki, więc dorzucenie jednego dokumentu nie przeładowuje reszty.

## Komendy

```bash
publish.py find garderoba                     # ZAWSZE najpierw: czy to już wisi i pod czym
publish.py add ./dokumentacja/ --slug garderoba --title "Garderoba - dokumentacja"
publish.py add ./wyniki.md --slug "wyniki-$(python3 -c 'import secrets;print(secrets.token_hex(4))')"
publish.py add ./apka/ --spa                  # folder z zasobami; --spa = routing po stronie klienta
publish.py add ./dok/ --ignore '*.py' --ignore rys   # pomiń warsztat (śmieci budowania i tak lecą)
publish.py add ./duzy.md --no-deploy          # tylko do lustra, deploy zbiorczy później

publish.py list                               # tabela (bez ruchu sieciowego)
publish.py info <slug>                        # metadane + lista plików

publish.py update <slug>                      # odśwież z zapamiętanego źródła
publish.py update <slug> ./inny-plik.md       # ...albo z nowego (stara wersja -> trash/)
publish.py unpublish <slug>                   # zdjęcie z serwera, treść -> trash/
publish.py deploy                             # redeploy całego lustra (naprawczy)
```

Bez `--slug` slug bierze się z nazwy pliku/folderu, a jeśli **to źródło już było publikowane** — z jego dotychczasowego adresu. To domyślne zachowanie jest celowe: publikacja tej samej rzeczy drugi raz ma odświeżyć istniejący link, a nie wypuścić drugi, konkurencyjny. Jawny `--slug` jest silniejszy i zakłada nową publikację (chyba że wskazuje dokładnie tę istniejącą).

| Wejście | Co się dzieje |
|---------|---------------|
| `.md` / `.markdown` | render do **samodzielnego** HTML-a (osadzony CSS, jasny/ciemny motyw, tabele, podświetlanie kodu). Front-matter zdejmowany, tytuł z `title:` albo pierwszego `#` |
| `.html` / `.htm` | kopiowany 1:1; tytuł z `<title>`; pliki, do których odwołuje się względnie (obrazki, CSS), są dociągane obok |
| folder | kopiowany w całości; wymaga `index.html` albo `index.md`/`README.md`; każdy `.md` w środku renderowany obok oryginału. Pomijane zawsze: `__pycache__`, `*.pyc`, `node_modules`, `.git`, `.venv`, `.DS_Store` i pliki z kropką; `--ignore WZORZEC` dokłada własne |

Markdown z vaulta: `[[wikilinki]]` zamieniane na czysty tekst (na zewnątrz prowadziłyby donikąd), `![[obrazek.png]]` szukany obok notatki, a potem po nazwie w `obsidian/`, i kopiowany do folderu dokumentu.

## Ponowna publikacja i pamięć sluga

Pytanie „pod jakim adresem to wisiało?" wraca za każdym razem, gdy materiał się zmienił. Odpowiadają na nie dwa miejsca:

| Gdzie | Co trzyma | Po co osobno |
|-------|-----------|--------------|
| `published/manifest.json` | indeks wszystkich publikacji (slug, tytuł, źródło, `ignore`, daty) | szybkie `list`/`find` bez ruchu sieciowego |
| `.publish.json` **przy źródle** | slug, URL i wzorce `ignore` tego materiału | jedzie razem z projektem i **przeżywa utratę lustra** — `add` odtworzy z niego wpis i wróci pod stary adres |

Marker zapisuje się sam. Jeśli źródło jest tylko do odczytu (albo proces nie ma prawa zapisu w tamtym katalogu), skrypt **wypisze ostrzeżenie na stderr** zamiast milczeć — wtedy dopisz plik innym narzędziem, bo inaczej slug pamięta wyłącznie manifest.

## Wymagania

- `CLOUDFLARE_API_TOKEN` i `CLOUDFLARE_ACCOUNT_ID` w `.env` (token: dashboard → My Profile → API Tokens → Custom, uprawnienie **Account → Cloudflare Pages → Edit**).
  Świadomie token, nie `wrangler login`: OAuth wranglera wygasa po cichu (w tym systemie już wygasł), a rutyna o 8:00 nie ma kogo poprosić o zalogowanie.
- `npx` (wrangler odpalany przez `npx wrangler@4`, nic nie instalujemy na stałe) i `uv` (render Markdowna przez `uv run --with markdown-it-py --with pygments`; gdy biblioteki brakuje, `publish.py` sam wchodzi przez `uv` — zanim cokolwiek powstanie na dysku).
- Konfiguracja: `scripts/publish.env`. Instalacja i diagnostyka: `./setup-publishing.sh`, `--status`, `--dry-run`, `--uninstall`.

## Zakres tokena (i czego nie da się zawęzić)

Uprawnienia Pages są **account-scoped** (`com.cloudflare.api.account`) — Cloudflare **nie pozwala** ograniczyć tokena do jednego projektu Pages. `Cloudflare Pages: Edit` daje dostęp do wszystkich projektów Pages na danym koncie (tworzenie, edycja, kasowanie, deploye, domeny). `Pages: Read` nie wystarczy — direct upload tworzy deployment, czyli jest zapisem.

Czego token **nie** daje: DNS, stref, Workerów, R2, KV, Zero Trust, ustawień konta, maila. To już jest wąskie — ale jeśli chcesz twardej izolacji „tylko ten jeden serwis":

1. **Osobne konto Cloudflare** (darmowe, to samo logowanie, *Add account* w dashboardzie), w którym żyje wyłącznie ten projekt. Token account-scoped na to konto = de facto token na jeden projekt. Wtedy w `.env` zmienia się tylko `CLOUDFLARE_ACCOUNT_ID`.
2. **TTL tokena** (*TTL* przy tworzeniu) i opcjonalnie filtr IP — token wygaśnie sam, zamiast żyć wiecznie.

**Projekt możesz założyć ręcznie** w dashboardzie (Workers & Pages → Create → Pages → Direct Upload) — `setup-publishing.sh` wykrywa istniejący projekt i go nie dotyka. Muszą się tylko zgadzać `PAGES_PROJECT` i `BASE_URL` w `scripts/publish.env`.

Uwaga na **gałąź produkcyjną**: deployment trafia na adres produkcyjny tylko wtedy, gdy jego gałąź jest gałęzią produkcyjną projektu; inaczej ląduje jako *preview* pod losowym `<hash>.<projekt>.pages.dev`, a link, który komuś wysłałeś, pokazuje starą treść. Dlatego `publish.py deploy` **odpytuje API o `production_branch`** projektu i używa jej, zamiast zakładać `main` — projekt założony ręcznie może mieć inną. `./setup-publishing.sh --status` wypisuje wykrytą gałąź.

## Limity i awarie

| Rzecz | Wartość |
|-------|---------|
| Deploye (plan darmowy) | 500/miesiąc — przy wsadach używaj `--no-deploy` i jednego `deploy` na końcu |
| Pliki w projekcie | 20 000, max 25 MiB na plik |
| Nazwa projektu | jest subdomeną i musi być **globalnie** unikalna w Cloudflare; kolizja → zmień `PAGES_PROJECT` i `BASE_URL` w `scripts/publish.env` |

**Utrata `published/`** = utrata możliwości redeployu (Cloudflare trzyma kopię ostatniego deployu, ale lustro odtwarza się tylko z oryginałów). Źródła zwykle żyją w vaulcie — `manifest.json` trzyma ścieżkę do pliku źródłowego każdego dokumentu (`source`), więc odtworzenie to ponowne `add` z tej ścieżki.

## Czego tu nie ma

- **Autoryzacji.** Gdyby trafił tu dokument naprawdę wrażliwy, dokładamy tryb `--private`: osobna ścieżka za Cloudflare Access (email OTP, darmowe do 50 osób).
- **Zmiany sluga.** Świadomie — link ma być stabilny. Zamiast tego `unpublish` + `add`.
- **Kasowania.** `trash/` rośnie; sprzątasz sam, gdy chcesz.
