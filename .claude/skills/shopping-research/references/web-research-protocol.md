# Protokół researchu internetowego

Obowiązuje **agenta głównego w Fazie 2** oraz **każdego subagenta researchowego** (Etap A i Etap C). Jest osobno od kontraktów subagentów, bo reguły są te same niezależnie od tego, czy subagent szuka kandydatów, ceny, czy pojedynczego kodu producenta.

*Skrócona adaptacja tych reguł żyje w `travel-planning/SKILL.md` → „Warstwa danych". Zmieniając tu — sprawdź tam.*

**Skąd się wziął.** W sesji researchu prowadnic subagent orzekł „kod PK-L-H53-550 **NIE ISTNIEJE**, potwierdzone niezależnie", a agent główny podał to użytkownikowi jako fakt. Produkt istnieje, jest w katalogu producenta i w polskich sklepach. Cała sesja miała **139 wyszukiwań i 106 pobrań** — problemem nie była ilość, tylko **kierunek** (sklepy i wyszukiwarka zamiast źródła pierwotnego) i **przedwczesny negatyw** (subagent orzekł po 8 wyszukiwaniach, czyli dokładnie na limicie, który wtedy obowiązywał). W drugiej sesji (deska do prasowania) ten sam wzorzec: 161 wyszukiwań, 9 godzin, i dopiero link przyniesiony przez użytkownika ruszył sprawę.

---

## 1. Wybór silnika — masz cztery, każdy do czegoś innego

Największy pojedynczy błąd to mielenie tego samego zapytania w tej samej wyszukiwarce. Gdy coś nie wychodzi, **zmieniasz silnik**, nie sformułowanie.

| Silnik | Do czego | Kiedy sięgasz |
|---|---|---|
| **`mcp__exa__web_search_exa`** | **domyślny do szukania produktów.** Semantyczny — opisujesz idealną stronę, nie zgadujesz słowa kluczowego. Zwraca gotową treść strony, nie sam link. Trafia w długi ogon polskich sklepów i w konkretne kody wariantów | **zaczynasz tutaj**: longlista, „czy ten wariant istnieje", niszowe sklepy, karty produktowe |
| `WebSearch` | operatory (`site:`, `filetype:`, cudzysłów), świeże newsy, szybki fakt | gdy potrzebujesz twardego operatora albo aktualności z ostatnich dni |
| **Playwright** (`mcp__playwright__*`) | strony, które blokują wszystko inne, i żywe ceny | **Allegro, Häfele, Amazon** — patrz tabela blokad w sekcji 5 |
| `Bash` + `curl` | sitemapy, XML, PDF-y, sonda katalogowa | sekcja 4 |

**Jak pytać Exę (to nie jest wyszukiwarka słów kluczowych):**
- `query` = **opis idealnej strony pełnym zdaniem**: „karta produktowa prowadnicy kulkowej GTV H53 550 mm z cichym domykiem w polskim sklepie", nie „gtv h53 550 cena".
- `objective` jest **wymagany** — napisz, co ma rankować wysoko, co odrzucić i jakie liczby wyciągnąć. Puste `objective` = słabszy wynik.
- Kod/SKU wklejaj w treść zdania (`PK-L-H53-550`), ale **nie polegaj na dokładnym dopasowaniu** — Exa dopasowuje znaczeniem. Dokładność ciągu weryfikujesz potem na stronie produktu.
- Gdy highlighty nie wystarczą → `mcp__exa__web_fetch_exa` (parametr to **`urls`**, tablica, nie `url`).

**Higiena zapytań w `WebSearch`** (diagnoza z transkryptów: mediana zapytania 57 znaków całymi zdaniami, operator w ~25% zapytań, 20% zapytań zwracało ≤2 unikalne domeny):
1. **2–5 słów kluczowych, nie zdanie.** Nadmiarowe słowa („cena", „gdzie kupić", „najlepszy") przesuwają wynik w stronę stron SEO zamiast źródeł.
2. **Sklep i domena przez `site:`, nigdy jako słowo.** `site:eakcesoria.com "H-53" 750`, nie `eakcesoria.com Sevroll H-53 100kg L-750 cena` — w drugim wariancie nazwa domeny jest zwykłym tokenem i dostaniesz dowolny inny sklep.
3. **Kod/SKU zawsze w cudzysłowie:** `"PK-L-H53-550"`. Bez cudzysłowu wyszukiwarka po cichu podmienia kod na sąsiedni i oddaje spójnie brzmiące streszczenie **o innym produkcie** (zaobserwowane: pytanie o `PK-L-H53-550`, wyniki i podsumowanie o `PK-0-H53-550`).
4. **Szukaj RODZINY, nie pojedynczego wariantu.** Obetnij ostatni człon (`"PK-L-H53"`) — zobaczysz całą serię i odczytasz, jakie długości w ogóle istnieją. Pojedynczy wariant bywa nieindeksowany, rodzina prawie nigdy.
5. **Język rynku producenta.** Turecki producent → zapytanie po turecku, niemiecki → `Vollauszug`, `Datenblatt`. Polskie zapytanie o zagranicznego producenta trafia w polskich resellerów, czyli w to, co już wiesz.
6. **`filetype:pdf` do specyfikacji i cenników.**

**Detektor pętli:** dwa zapytania pod rząd zwracające te same domeny → zmień **silnik albo kąt**, nie sformułowanie. Trzecie przeformułowanie tego samego to czysta strata budżetu.

---

## 2. Orzeczenia negatywne — trzy stopnie, nie jeden

„Nie ma" to trzy różne twierdzenia o bardzo różnym koszcie błędu. Zawsze nazywaj ten, który faktycznie udowodniłeś:

| Stopień | Brzmienie | Co musisz mieć |
|---|---|---|
| **N1 — nie znalazłem** | „Nie znalazłem [X]. Sprawdziłem: [lista]" | tylko uczciwą listę tego, co sprawdziłeś. To jest **domyślne** orzeczenie |
| **N2 — brak w sprzedaży** | „Żaden ze sprawdzonych sklepów nie ma [X] na stanie (stan na [data]): [sklep 1], [2], [3]" | ≥3 sklepy **wymienione z nazwy** + data. Mówi o **dostępności**, nie o istnieniu |
| **N3 — producent tego nie oferuje** | „[Producent] nie ma [X] w katalogu" | **dotknięcie źródła pierwotnego** (sekcja 4): sitemap / wyszukiwarka na stronie producenta / cennik lub karta katalogowa PDF — z linkiem i cytatem. Bez tego **zakazane** |

**Asymetria kosztu błędu** (ta sama logika, co guard cenowy w `SKILL.md`, Etap B): **„nie znalazłem" jest odwracalne i tanie** — użytkownik szuka dalej, dopytuje producenta, wraca do tematu. **„Nie istnieje" jest nieodwracalne i drogie** — zamyka temat, użytkownik kupuje gorszy wariant albo przeprojektowuje cały projekt. Dlatego przy jakiejkolwiek niepewności **schodzisz o stopień niżej** (N3 → N2 → N1), nigdy w górę.

**Czego NIE wolno użyć jako dowodu negatywnego:**
- **Zdania sklepu o asortymencie.** „Długość 550 mm z cichym domykiem nie jest dostępna" to informacja o **jednym sklepie** — sklep nie zna katalogu producenta i ma interes w sprzedaniu tego, co ma na półce. Cytowanie tego jako stanowiska producenta to podmiana podmiotu zdania. Dokładnie tak powstał opisany wyżej fałszywy negatyw.
- **Podsumowania wyszukiwarki, która podmieniła kod.** Brak trafienia na **dokładny** ciąg to zero informacji o istnieniu. Zanim napiszesz cokolwiek negatywnego, sprawdź, czy w wynikach w ogóle występuje dokładnie szukany ciąg — jeśli nie, masz N1.
- **Pustki w porównywarkach** (Ceneo, Allegro, Google Shopping) — indeksują to, co ktoś wystawił, nie katalog producenta.
- **Samego statusu HTTP.** 200 nie znaczy „istnieje" — patrz sekcja 4, krok 4.

**Kto może orzekać:** subagent **nigdy** nie zwraca N3. Jeśli dochodzi do wniosku, że czegoś nie ma, zwraca **`NIEROZSTRZYGNIĘTE`** + trop (czego dokładnie szukał, jakie **sąsiednie kody** widział, jaka jest domena producenta, jaki wzorzec URL-i produktowych zauważył) i kończy. N2/N3 orzeka **wyłącznie agent główny**, po sondzie katalogowej. Powód: subagent nie wie, ile już wiadomo, i systematycznie myli „skończył mi się budżet" z „tego nie ma".

---

## 3. Budżet zamiast licznika zapytań

Stary zapis „maks ~8 wyszukiwań/pobrań" powstał z realnego powodu — watchdog ubija sesje wiszące ~10 min — ale **mierzył złą rzecz**. Sesji nie zabija liczba zapytań (są szybkie), tylko **jedno pobranie, które wisi**. Za to model czyta „8" jako „po ósmym wyciągnij wniosek". Tak powstał fałszywy negatyw: dokładnie 8 wyszukiwań, 3 pobrania i werdykt „NIE ISTNIEJE".

- **Reguła anty-wiszenia — to ona chroni przed watchdogiem.** Żadne pojedyncze pobranie nie blokuje dłużej niż ~15 s. 403 / CAPTCHA / pusta treść → **pomijasz natychmiast**, bez ponawiania i bez szukania obejścia. Ten sam host nie dostaje trzeciej szansy.
- **Miękki budżet ~20 akcji, sufit ~35** — i to nie jest cel do wyczerpania.
- **Lista pokrycia zamiast licznika.** Kryterium zakończenia to odhaczone pokrycie, nie dobity licznik. Dla dossier produktu: ≥2 niezależne kanały cenowe, ≥1 źródło opinii użytkowników, ≥1 celowe zapytanie o wady, strona producenta. Czego nie odhaczyłeś → „Luki", nie wniosek.
- **Raportuj zużycie** w dossier (`Budżet i pokrycie`). Agent główny ma wtedy sygnał alarmowy: **dossier z orzeczeniem negatywnym przy niskim zużyciu i niepełnym pokryciu jest podejrzane.**
- **Dwie tury zamiast jednej długiej sesji.** Nie wydłużaj pojedynczego subagenta — to wprost karmi watchdog. Tura 1 = standardowe dossier. Gdy wraca `NIEROZSTRZYGNIĘTE` albo negatyw → agent główny odpala **turę 2: subagenta sondy katalogowej** z jednym wąskim celem. Każda sesja krótka, a łączne szukanie nieograniczone. Lekarstwem na watchdoga jest **więcej agentów po kolei**, nie mniej szukania w jednym.

---

## 4. Sonda katalogowa — „idź do źródła pierwotnego"

**Kiedy uruchamiasz:** (a) subagent zwrócił `NIEROZSTRZYGNIĘTE`, (b) chcesz orzec N2 lub N3, (c) szukasz wariantu/rozmiaru, którego sklepy nie mają, (d) widzisz, że wyszukiwarka podmienia kod, (e) użytkownik przyniósł link do producenta. Koszt: 1–3 minuty.

1. **`robots.txt` → sitemap.** `curl -s https://<domena>/robots.txt | grep -i sitemap`. Prawie każdy producent i sklep na WordPressie, Shopify czy PrestaShopie ujawnia tam `sitemap_index.xml`.
2. **Rozwiń indeks — nie zgaduj numeracji.** `curl -s <sitemap_index> | grep -o '<loc>[^<]*</loc>'` (na gtv.com.pl: 92 × `product-sitemap*.xml`). Pętla `seq 1 N` też zadziała, ale zgaduje zakres i gubi mapy spoza niego.
3. **Greppuj po WZORCU kodu, nie po pełnym kodzie:** `PK-` zamiast `PK-L-H53-550`. Dostajesz całą rodzinę i **widzisz, jakie warianty istnieją** — to mocniejsza odpowiedź niż „tak/nie" dla jednego kodu.
4. **Gdy w sitemapie pusto — zgaduj URL, ale skalibruj 404.** Producenci mają regularne wzorce: `/produkt/<KOD>/`, `/product/<kod-lowercase>`, `/Urun-Detay-End?id=<n>`. **Sam status 200 nic nie znaczy** — wiele CMS-ów oddaje 200 razem ze stroną „nie znaleziono". Dlatego **zawsze** pobierz równolegle URL z kodem celowo nieistniejącym i porównaj **status + `<title>`**. Istnienie potwierdza dopiero **różnica**:
   ```
   PK-L-H53-550 → <title>Prowadnica GTV kulkowa, H53, L=550 mm, … cichy domyk, udzwig 100 kg</title>
   PK-L-H53-999 → <title>Page Not Found - GTV</title>      # atrapa kalibrująca
   ```
5. **Wyszukiwarka na stronie producenta:** `https://<domena>/?s=<kod>` (WordPress), `/search?q=` (Shopify), `/szukaj?controller=search&s=` (PrestaShop). Znajduje to, czego Google nie zaindeksował — a kody wariantów to dokładnie ta kategoria.
6. **Katalog / cennik PDF** — najmocniejszy dowód istnienia, jaki zdobędziesz bez telefonu. `WebFetch` na PDF zwraca binarny śmieć; masz dwie działające drogi:
   ```bash
   curl -s "https://r.jina.ai/<url-pdf>" | grep -n -i "H53"      # Jina Reader: PDF → czysty tekst, bez klucza
   curl -sL -o "$TMPDIR/k.pdf" <url> && pdftotext -layout "$TMPDIR/k.pdf" - | grep -n "H53"
   ```
   Zweryfikowane: katalog `GTV-Prowadnice.pdf` przez Jinę → 40 KB tekstu z pełnymi tabelami kodów.

**Zapisz wynik sondy jednoznacznie:** znalezione kody rodziny + link do strony produktu + tytuł tej strony + tytuł strony-atrapy. Dopiero to uprawnia do N3.

---

## 5. Wyposażenie i znane blokady

Subagent researchowy ładuje narzędzia przez `ToolSearch`: **`select:mcp__exa__web_search_exa,mcp__exa__web_fetch_exa,WebSearch,WebFetch,Bash`**. Sam `WebSearch`+`WebFetch` to przyczyna, dla której w całej 15-subagentowej sesji słowo „sitemap" nie padło ani razu: **czego nie ma w narzędziach, tego model nie wymyśli** — zamiast tego dokłada dwudzieste wyszukiwanie.

| Kanał | Stan (sprawdzone 2026-09-21) | Co robić |
|---|---|---|
| **Allegro** | 403 dla `WebFetch`, `curl`, Jiny **i** crawlera Exy | **wyłącznie Playwright**; inaczej cena z Ceneo/snippetów, oznaczona jako niezweryfikowana |
| **Häfele** | Cloudflare — jak wyżej | Playwright albo karta katalogowa PDF zamiast strony |
| Amazon | często nie renderuje treści dla `WebFetch` | Playwright / Ceneo, oznacz jako niezweryfikowane |
| Ceneo, Pepper | działają przez `WebFetch` | podstawowe kanały cenowe |
| `WebFetch` na sitemap/XML | **zawodny** — streszcza i gubi URL-e (z podmapy potrafi zwrócić kilka linków do zdjęć i pominąć produkty) | zawsze `Bash` + `curl` + `grep` |
| `WebFetch` na PDF | binarny śmieć | Jina (`r.jina.ai/<url>`) albo `curl` + `pdftotext -layout` |
| Jina Reader | działa bez klucza, **20 zapytań/min**; odbija się od Cloudflare (Allegro, Häfele) | do PDF-ów i stron, które `WebFetch` kaleczy |
| Exa bez klucza | działa; limity nieudokumentowane | przy 429 z wielu subagentów naraz — zgłoś użytkownikowi, nie obchodź |

**Sandbox sieciowy:** `Bash` chodzi przez proxy z listą dozwolonych domen (`.claude/settings.json` → `sandbox.network.allowedDomains`; na stałe są tam m.in. `r.jina.ai`, `*.ceneo.pl`, `*.pepper.pl`). Domeny producenta tam nie ma — **podaj ją w wywołaniu `Bash` w `allowed_domains`**, inaczej `curl` może zawisnąć na timeout zamiast zwrócić błąd. Gdy połączenie mimo to jest odrzucane, **nie kombinuj z obejściem**: zapisz lukę („sonda katalogowa niemożliwa — domena poza allowlistą"), powiedz o tym użytkownikowi i orzekaj co najwyżej N1/N2. Pliki tymczasowe zawsze do `"$TMPDIR"`, nigdy do `/tmp`.
