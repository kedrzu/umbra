# Kontrakt subagenta — sourcing znanej pozycji (gdzie kupić, za ile)

Siostrzany kontrakt do `deep-dive-agent.md`. Tamten odpowiada na pytanie **„który produkt wybrać"**.
Ten odpowiada na **„gdzie kupić to, co już wybrane, i ile to naprawdę kosztuje z dostawą"**.

Używasz go, gdy przedmiot jest **znany** (konkretny SKU albo jednoznaczna specyfikacja techniczna) i cała
wartość researchu leży w kanale, cenie, dostępności i koszcie przesyłki. Typowo: lista materiałowa projektu,
uzupełnianie zapasu, kompletowanie koszyka z wielu pozycji.

Główny agent czyta ten plik, wstawia **jedną grupę pozycji** i odpala subagenta na Sonnecie
(`Agent`, `model: "sonnet"`, `subagent_type: "general-purpose"`). Grupy odpalaj równolegle, ale **falami po ~6** —
Exa bez klucza ma nieudokumentowane limity i kilkanaście równoległych sesji potrafi wygenerować 429.

**Grupuj pozycje po sklepie-kandydacie, nie po funkcji w projekcie.** Sens sourcingu to minimalizacja liczby
przesyłek, więc subagent, który dostaje „wszystkie wkręty i konfirmaty" naraz, może znaleźć jeden sklep na całość.
Subagent, który dostaje jeden wkręt, tego nie zobaczy.

---

## Szablon promptu dla subagenta

> To jest **zadanie badawcze**: sourcing zakupowy konkretnych, już wybranych pozycji. Nie wybierasz produktu
> i nie rekomendujesz alternatyw „lepszych" — masz znaleźć **gdzie kupić dokładnie to** (albo pełnoprawny
> zamiennik, gdy pozycja jest opisana generycznie), **za ile**, **z jakim kosztem dostawy** i **czy jest na stanie**.
> Zwróć ustrukturyzowaną tabelę źródeł. Postawa sceptyczna: cena na liście produktów bywa inna niż w koszyku,
> a „dostępny" bywa „na zamówienie 3 tygodnie".
>
> **Pozycje do zbadania:** [lista: nazwa/SKU + ilość + jednostka + uwagi techniczne z BOM]
> **Rynek:** Polska, ceny brutto w PLN.
> **Dostawa do:** [kod pocztowy + miasto] — koszt wysyłki **jest częścią wyniku**, nie przypisem.
> **Kontekst projektu:** [do czego to jest, co musi pasować, czego nie wolno zamienić]
>
> **Jak pracować:**
> - **Zrób research sam i zwróć tabelę jako swoją finalną odpowiedź.** Nie deleguj dalej, nie zlecaj podzadań
>   w tle, nie odsyłaj „zajmę się tym" — masz oddać gotowy wynik w tej odpowiedzi.
> - **Narzędzia:** załaduj przez `ToolSearch` zapytaniem
>   `select:mcp__exa__web_search_exa,mcp__exa__web_fetch_exa,WebSearch,WebFetch,Bash`.
>   **Szukanie zaczynaj od Exy** — jest semantyczna (opisujesz idealną stronę pełnym zdaniem, `objective`
>   jest wymagany) i trafia w długi ogon polskich sklepów oraz w konkretne kody wariantów tam, gdzie
>   `WebSearch` po cichu podmienia kod na sąsiedni. `Bash` jest **niezbędny**, nie opcjonalny: `WebFetch`
>   streszcza i gubi XML, a na PDF-ach zwraca binarny śmieć — cenniki, katalogi i sitemapy bierzesz przez
>   `curl` + `grep` / `pdftotext` (albo `curl -s https://r.jina.ai/<url-pdf>`).
> - **Obowiązkowo załaduj skill `web-search`** (`Skill` z `skill: "web-search:web-search"`) — protokół researchu
>   w sieci, obowiązuje w całości. Trzy reguły, które obowiązują nawet gdyby załadowanie się nie udało:
>   (1) **nigdy nie orzekasz, że coś nie istnieje** — patrz niżej; (2) w `WebSearch` kod/SKU zawsze
>   w cudzysłowie, a sklep przez `site:`, nie jako słowo w zapytaniu; (3) 403/CAPTCHA → pomijasz host
>   natychmiast, bez ponawiania.
> - **ALLEGRO POMIJASZ.** Allegro zwraca 403/CAPTCHA dla `WebFetch`, `curl`, Jiny **i** crawlera Exy, a jedyne
>   wejście (Playwright) jest zarezerwowane dla agenta głównego, bo to jedna współdzielona przeglądarka.
>   Twoje zadanie: zebrać **ceny poza Allegro** oraz **listę nazw/SKU do sprawdzenia na Allegro** w sekcji
>   „Do sweepu Allegro". Nie zgaduj cen allegrowych ze snippetów.
> - **Budżet i pokrycie zamiast licznika zapytań.** Miękko ~20 akcji, sufit ~35 — ale kryterium zakończenia
>   jest **pokrycie**, nie liczba:
>   **≥3 niezależne sklepy z ceną i kosztem wysyłki**, **≥1 potwierdzenie dostępności** (stan magazynowy albo
>   termin realizacji), **≥1 dotknięcie strony producenta** (że SKU/specyfikacja się zgadza).
>   Czego nie odhaczyłeś → „Luki", nie wniosek. **Reguła anty-wiszenia:** żadne pobranie dłużej niż ~15 s,
>   blokujący host bez ponawiania — to ona chroni sesję przed watchdogiem (~10 min), nie oszczędzanie zapytań.
>   Pola nieustalone oznacz „b.d.".
> - **Nie wolno Ci orzec, że produkt/wariant/kod nie istnieje.** Jeśli nie znajdujesz — zwróć
>   **`NIEROZSTRZYGNIĘTE`** + trop: czego dokładnie szukałeś, jakie **sąsiednie kody** widziałeś, jaka jest
>   domena producenta, jaki wzorzec URL-i produktowych zauważyłeś. Rozstrzygnie to agent główny sondą
>   katalogową. Zdanie sklepu „ten wariant nie jest dostępny" to informacja o **jednym sklepie**, nigdy
>   o producencie — jeśli je cytujesz, zacytuj też sklep.
>
> **Reguły specyficzne dla sourcingu — tu leży cała wartość:**
> - **Koszt całkowity, nie cena półkowa.** Dla każdego sklepu podaj: cena jednostkowa brutto, cena za podaną
>   ilość, **koszt wysyłki pod wskazany adres**, **próg darmowej dostawy**, i **sumę do zapłaty**. Sklep
>   z ceną niższą o 8% i wysyłką 35 zł przy jednej pozycji zwykle przegrywa — pokaż to liczbą, nie intuicją.
> - **Gabaryt decyduje o wysyłce.** Sprawdź, czy pozycja mieści się w paczkomacie. Wszystko dłuższe niż ~60 cm
>   (prowadnice, profile, rury, listwy) idzie kurierem gabarytowym i bywa dopłatą 30–80 zł, a część sklepów
>   w ogóle odmawia wysyłki. Zaznacz to wprost.
> - **Opakowania zbiorcze.** Przy dużych ilościach (wkręty, konfirmaty, kołki) sprawdź ceny za 100/250/500/1000
>   szt. i **przelicz na sztukę**. Opakowanie zbiorcze potrafi być tańsze od potrzebnej ilości na sztuki.
>   Podaj, ile realnie trzeba kupić opakowań i ile zostanie zapasu.
> - **Progi ilościowe i hurt.** Przy zamówieniu wartym setki złotych z jednej pozycji sprawdź, czy sklep ma
>   cennik hurtowy, rabat ilościowy albo opcję zapytania B2B. Odnotuj, nawet jeśli wymaga kontaktu.
> - **Zamienniki przy pozycjach generycznych.** Gdy BOM opisuje pozycję cechami („kątownik stalowy 40×40×2,
>   2 otwory", „wkręt 4×16 łeb Ø8"), podaj **konkretny produkt z linkiem**, nie kategorię — z potwierdzeniem,
>   że wymiary się zgadzają. Gdzie cecha jest krytyczna (łeb stożkowy vs walcowy, długość, gwint), powiedz
>   wprost, czy znaleziony produkt ją spełnia, czy tylko „prawdopodobnie".
> - **Dostępność z datą.** „Na stanie" bez daty odczytu jest bezwartościowe. Podaj stan i datę; gdzie sklep
>   pokazuje liczbę sztuk — zapisz liczbę, bo przy dużych ilościach to bywa blokada.
> - **Wiarygodność sprzedawcy** — krótko: czy to sklep branżowy z adresem i NIP, czy przypadkowy marketplace.
>   Nie rozpisuj się; to sourcing, nie recenzja.
>
> **Zwróć dokładnie taką strukturę (Markdown):**
>
> ```markdown
> ## Sourcing: [nazwa grupy]
>
> ### Źródła (najlepsze pierwsze)
>
> | Pozycja | Produkt (konkretny) | Sklep | Link | Cena jedn. | Ilość | Razem | Wysyłka | Darmowa od | Gabaryt | Dostępność (data) |
> |---|---|---|---|---|---|---|---|---|---|---|
> | [poz. z BOM] | [pełna nazwa + SKU] | [sklep] | [url] | [zł] | [n] | [zł] | [zł] | [zł] | [paczkomat/kurier gab.] | [stan, RRRR-MM-DD] |
>
> ### Najlepszy koszyk dla tej grupy
> - **[Sklep X]** — wszystkie/część pozycji: [suma towaru] + [wysyłka] = **[suma]**
> - Alternatywa: [Sklep Y] — [suma], sens ma tylko jeśli [warunek]
> - Czego ten sklep NIE ma: [lista pozycji do dokupienia gdzie indziej]
>
> ### Do sweepu Allegro (agent główny sprawdzi Playwrightem)
> - `[dokładna fraza wyszukiwania / SKU]` — cena poza Allegro do pobicia: [zł], oczekiwany wariant: [opis]
>
> ### Uwagi techniczne
> - [rozbieżności ze specyfikacją BOM, ryzyka dopasowania, rzeczy do zweryfikowania przed zamówieniem]
>
> ### Budżet i pokrycie
> - [N akcji] · odhaczone: [sklepy z ceną i wysyłką / dostępność / strona producenta] · **brakuje:** [lista]
> - orzeczenia: [brak | NIEROZSTRZYGNIĘTE: (trop)]
>
> ### Luki
> - [czego uczciwie nie udało się ustalić]
> ```
>
> Zwróć wyłącznie tę strukturę — będzie zestawiona z innymi grupami przez agenta głównego.

---

## Wskazówki dla agenta głównego

- **Wstaw pełną specyfikację pozycji z BOM, łącznie z uwagami.** Kolumna „uwagi" w liście materiałowej często
  zawiera warunek dopasowania („nie dłuższe — bok skrzyni 16 mm", „łeb stożkowy od strony łożysk"), bez którego
  subagent kupi rzecz niepasującą. Subagent nie dziedziczy Twojego kontekstu.
- **Podaj kod pocztowy dostawy.** Bez niego koszt wysyłki jest fikcją, a to jest połowa wyniku.
- **Nie każ subagentom chodzić po Allegro.** Playwright MCP to jedna przeglądarka; równoległe sesje się
  zderzają. Allegro sweepujesz sam, **seryjnie**, po zebraniu list „Do sweepu Allegro" ze wszystkich grup.
- **Konsolidacja koszyka to Twoja robota, nie ich.** Każdy subagent optymalizuje swoją grupę; dopiero Ty widzisz,
  że pozycje z trzech grup są w jednym sklepie i razem przekraczają próg darmowej dostawy. Licz to jako
  **problem koszykowy** (suma towaru + suma przesyłek), nie jako 30 niezależnych minimów.
- **Czytaj „Budżet i pokrycie" jako detektor przedwczesnego wniosku.** Grupa z orzeczeniem negatywnym przy
  niskim zużyciu i niepełnym pokryciu to **sygnał**, że subagent skończył za wcześnie, a nie wynik.
- **Na każde `NIEROZSTRZYGNIĘTE` odpal turę 2 — subagenta sondy katalogowej** (sekcja 4 protokołu:
  robots.txt → sitemap_index → podmapy → grep po wzorcu rodziny kodu → sonda URL skalibrowana atrapą →
  wyszukiwarka producenta → cennik PDF). N2/N3 orzekasz wyłącznie Ty, po sondzie.
- **Obsłuż maruderów.** Subagent może paść na watchdogu (~10 min) albo zwrócić placeholder. Wtedy: odpal
  ponownie z tropem, a po drugim niepowodzeniu zbadaj tę grupę sam. Lista zakupowa z dziurą to nie lista.
