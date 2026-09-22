---
name: publish
description: Publikuje dokument w internecie i zwraca link do wysłania komuś - pojedynczy plik HTML/Markdown, notatkę z vaulta albo cały folder z dokumentacją (HTML + CSS + obrazki + dane). Używaj ZAWSZE, gdy użytkownik chce coś komuś pokazać, wysłać, udostępnić albo prosi o link: "wyślij stolarzowi dokumentację", "daj mi link do tego raportu", "wrzuć to do sieci", "opublikuj to", "podeślij to Kasi", "zrób z tego stronę", "chcę to pokazać wykonawcy", "muszę to komuś przesłać, ale to duże", a także gdy sam właśnie wygenerowałeś dokument (raport, zestawienie, dokumentację) i naturalnym następnym krokiem jest danie użytkownikowi linku. Użyj też, gdy materiał już opublikowany się zmienił i trzeba go odświeżyć pod tym samym adresem, gdy trzeba sprawdzić co jest opublikowane, albo coś zdjąć z sieci. Użytkownik NIE robi tego ręcznie - agent publikuje sam.
---

# Publikowanie dokumentów

Jeden projekt Cloudflare Pages = jedna subdomena = wiele niezależnych podfolderów. Dokument ląduje pod `https://kedrzu.pages.dev/<slug>/` i tyle — link można wysłać mailem, wkleić do SMS-a, podać przez telefon.

Narzędzie: `python3 scripts/publish.py` (w repo `umbra`). Pełny kontrakt: `docs/publishing.md` — zajrzyj tam po szczegóły mechaniki (układ katalogów, limity, odtwarzanie po awarii). Tutaj jest to, co decyduje o *dobrej* publikacji.

## Najpierw: czy to już gdzieś wisi?

```bash
python3 scripts/publish.py find <ścieżka|nazwa|fragment>
```

To pierwszy krok, nie formalność. Jeśli materiał był już publikowany, a Ty zrobisz nową publikację, powstanie **drugi link do tej samej rzeczy** — i ten, który użytkownik wysłał stolarzowi tydzień temu, po cichu pokaże nieaktualną wersję. Dlatego `add` bez `--slug` na znanym źródle **aktualizuje** istniejącą publikację pod tym samym adresem. Pozwól mu to zrobić.

Pamięć o tym, co gdzie wisi, jest w dwóch miejscach: `published/manifest.json` (indeks) i `.publish.json` **przy samym źródle** (jedzie razem z projektem, przeżywa utratę lustra). Skrypt zapisuje je sam.

## Adres (slug) — Twoja decyzja, nie skryptu

`--slug` jest brany dosłownie. Nie ma pod spodem żadnej automatycznej losowości; jeśli chcesz adresu nie do zgadnięcia, **dolosuj sufiks sam** i podaj go w `--slug`.

| Sytuacja | Adres | Dlaczego |
|----------|-------|----------|
| Dokumentacja dla wykonawcy, instrukcja, oferta, materiał, który ktoś przepisze z kartki albo poda przez telefon | `--slug garderoba` | czytelny, łatwy do podania i zapamiętania; nie ma czego chronić |
| Treść, której nie chcesz dać przypadkowemu zgadywaczowi: wyniki, sprawy osobiste, wewnętrzne ustalenia, cokolwiek z nazwiskami | `--slug wyniki-$(python3 -c 'import secrets;print(secrets.token_hex(4))')` | adres przestaje być odgadywalny; to jedyna ochrona, jaką ma ten serwis |

Cały serwis ma `noindex`, `robots.txt: Disallow` i stronę główną, która **nie listuje** dokumentów, więc wyszukiwarki tego nie pokażą. Ale to nie jest autoryzacja — **kto ma link, ten wejdzie**.

Gdy nie masz pewności, a użytkownik jest przy klawiaturze, zapytaj jednym zdaniem: *„adres czytelny `/garderoba/` czy nie do zgadnięcia?"*. Gdy działasz bez niego (rutyna, tryb autonomiczny) — wybierz nieodgadywalny, bo błąd w tę stronę jest odwracalny, a w drugą nie.

**Nieodgadywalnego sluga nie wpisuj do plików repo `umbra` — ono jest publiczne na GitHubie.** Adres w `CLAUDE.md`, `docs/` czy w skillu to adres podany całemu światu, co zabija jedyną ochronę, jaką ma taki dokument. Slug żyje w `published/manifest.json` (gitignorowany) i w markerze przy źródle; w commitowanych plikach używaj wyłącznie adresów, które i tak mogą być czytelne dla każdego.

**Czego nie publikujemy w ogóle**, nawet pod losowym adresem, dopóki użytkownik wyraźnie tego nie każe: dane pacjentów i cokolwiek z kontekstu `sigma.clinic`, dokumenty tożsamości, dane finansowe (numery kont, faktury z pełnymi danymi), dane osobowe osób trzecich z `Kontakty/`. Jeśli materiał to zawiera, powiedz to i zaproponuj wycięcie wrażliwej części albo tryb za Cloudflare Access.

## Co dokładnie opublikować

Zanim skopiujesz folder w całości, **zobacz, co w nim jest**. Odbiorca ma dostać dokument, a nie warsztat.

- **Jest samodzielny `index.html`?** (obrazki wklejone w base64, style w `<style>`) → publikuj **sam ten plik**. Szybciej, czyściej, bez śmieci.
- **Dokument potrzebuje zasobów** (`rys/`, `assets/`, CSS, fonty) → publikuj **folder**; skrypt pomija `__pycache__`, `.git`, `node_modules`, `.DS_Store` i pliki z kropką, a `--ignore WZORZEC` dokłada własne wyjątki.
- **Skrypty generujące, dane źródłowe, notatki robocze** → zostaw, chyba że odbiorca ich potrzebuje. Stolarzowi przyda się `formatki.csv`, ale `model.py` czy `build_doc.py` to szum. Gdy nie wiesz — to dobry moment na jedno pytanie do użytkownika.
- **Markdown** (np. notatka z vaulta) jest renderowany do samodzielnego HTML-a: front-matter zdejmowany, `[[wikilinki]]` zamieniane na tekst, `![[obrazki]]` dociągane. Dla czytelnika z zewnątrz to jest to, czego chcesz.

## Przepływ

```bash
# 1. czy już wisi
python3 scripts/publish.py find garderoba

# 2a. nowa publikacja pod wybranym adresem
python3 scripts/publish.py add ./obsidian/.../dokumentacja/index.html \
    --slug garderoba --title "Garderoba - dokumentacja techniczna"

# 2b. odświeżenie tego, co już wisi (ten sam link!)
python3 scripts/publish.py update garderoba          # ze źródła zapamiętanego przy publikacji
python3 scripts/publish.py add ./dokumentacja/       # to samo: zna źródło, aktualizuje w miejscu

# 3. sprawdzenie na żywo (patrz niżej)
curl -sS -o /dev/null -w '%{http_code}\n' https://kedrzu.pages.dev/garderoba/

# pomocnicze
python3 scripts/publish.py list                      # co jest opublikowane, bez ruchu sieciowego
python3 scripts/publish.py info <slug>               # metadane + lista plików
python3 scripts/publish.py unpublish <slug>          # zdjęcie z sieci; treść ląduje w published/trash/
```

`add`/`update`/`unpublish` same robią deploy. Przy serii publikacji dawaj `--no-deploy` i jeden `python3 scripts/publish.py deploy` na końcu — darmowy plan ma 500 deployów miesięcznie.

## Zawsze sprawdź, że link naprawdę działa

`Deployment complete` od wranglera nie oznacza, że adres odpowiada. Dwie rzeczy potrafią zaskoczyć: **świeży projekt** propaguje się kilkadziesiąt sekund (edge zwraca wtedy `522`), a **cache edge'a** potrafi jeszcze przez chwilę serwować starą odpowiedź. Odpal `curl` na docelowym URL-u i dopiero gdy zobaczysz `200`, podaj link użytkownikowi. Przy aktualizacji sprawdź, czy widać nową treść (`curl -s <url> | grep <coś-nowego>`), a nie tylko kod 200.

## Po publikacji: zapisz to, co jutro będzie potrzebne

Marker `.publish.json` i manifest zapisują się same, ale **notatka projektu w vaulcie o tym nie wie**. Dopisz link tam, gdzie żyje projekt (`obsidian/Projekty/<Nazwa>/<Nazwa>.md`, profil osoby w `Kontakty/`, jeśli to jej wysłałeś) — jednym wierszem: co, pod jakim adresem, od kiedy. Dzięki temu za miesiąc, gdy padnie „zaktualizuj stolarzowi dokumentację", nie szukasz po omacku.

W odpowiedzi do użytkownika podaj **sam link i jedno zdanie** o tym, co pod nim jest. Dorzuć, jak to zdjąć (`unpublish <slug>`), gdy publikujesz coś jednorazowego.

## Gdy coś nie działa

| Objaw | Co się dzieje |
|-------|---------------|
| `Brak CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID` | pierwsze uruchomienie na tej maszynie — odeślij użytkownika do `./setup-publishing.sh`, który wypisuje dokładną instrukcję wyklikania tokenu. Bez tego nie da się nic opublikować i nie ma sensu próbować dalej |
| `Slug '<x>' jest juz zajety` | ten adres należy do innego materiału — wybierz inny albo, jeśli to ta sama rzecz, użyj `update <slug>` |
| `Folder ... nie ma index.html` | Pages nie wiedziałoby, co pokazać pod adresem dokumentu. Wskaż konkretny plik zamiast folderu albo dorzuć `index.html` |
| Link zwraca `522` tuż po pierwszym deployu | nowy projekt jeszcze się propaguje; poczekaj kilkadziesiąt sekund i sprawdź ponownie |
| Stara treść mimo udanego deployu | cache edge'a — sprawdź z `-H 'Cache-Control: no-cache'` albo z parametrem `?cb=<losowe>` |
| `uwaga: nie zapisano .../.publish.json` | skrypt nie miał prawa zapisu przy źródle (typowo: vault w iCloud pod piaskownicą). Slug pamięta wtedy **tylko manifest** — dopisz marker narzędziem `Write` (format w `docs/publishing.md`), inaczej po utracie lustra nie odtworzysz adresu |

## Czego tu nie robimy

- **Nie kasujemy.** `unpublish` przenosi treść do `published/trash/`; podkomendy `delete` nie ma. Czyszczenie kosza to decyzja użytkownika.
- **Nie zmieniamy adresu** istniejącej publikacji. Link, który ktoś już dostał, ma dalej działać — nowa treść idzie pod ten sam slug.
- **Nie publikujemy z własnej inicjatywy** materiałów, o które nikt nie prosił. Powstanie linku nie jest wysyłką, ale wypuszczenie czegoś do internetu to decyzja użytkownika.
