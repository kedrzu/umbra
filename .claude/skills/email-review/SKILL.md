---
name: email-review
description: Codzienny autopilot skrzynki Gmail (wszystkie konta) - klasyfikuje, nadaje labele, tworzy drafty i oznacza wątki jako przetworzone ściśle według zapisanego rulebooka EmailWorkflow; cokolwiek niejasne trafia do AI/Triage bez blokowania. Użyj, gdy użytkownik chce ogarnąć / wyczyścić / przejrzeć / nadrobić skrzynkę albo pyta "co mam w mailu". To codzienne narzędzie. NIE używaj do interaktywnego ustalania reguł (to /email-triage) ani do głębokiej analizy / setupu konta (to /email-analysis).
---

# Email Review

Codzienny **autopilot** skrzynki. Przetwarza nieprzetworzone wątki ściśle według rulebooka, a wszystko, czego reguły nie obejmują jednoznacznie, oznacza `AI/Triage` i **leci dalej** — nigdy nie blokuje użytkownika. Sterta `AI/Triage` jest potem czyszczona interaktywnie przez `/email-triage`.

## Zasada działania (źródło prawdy)

**Rulebook = jedyne źródło reguł.** Zbiór labelek i reguły klasyfikacji żyją w vault:
- `./obsidian/Asystent/Memory/EmailWorkflow-Personal.md` (kedrzu@gmail.com)
- `./obsidian/Asystent/Memory/EmailWorkflow-Work.md` (kedrzu@sigma.clinic)

Czytaj rulebook na początku sesji i klasyfikuj **wg niego**. Nie powielaj tu list labelek ani reguł — gdy reguła się zmienia, zmienia się tylko rulebook (robi to `/email-triage`). Ten skill **nie zapisuje reguł** — tylko je stosuje.

**Nigdy nie blokuj.** Jeśli reguła nie obejmuje maila jednoznacznie albo jest niepewność → `AI/Triage` + zapisz powód do stanu, i przejdź dalej. Decyzję podejmie użytkownik później przez `/email-triage`.

## Vault Obsidian

Wszystkie pliki pamięci i kontaktów są w vault (`./obsidian/`), NIE w folderze projektu.
- `./obsidian/Kontakty/` - profile osób (frontmatter YAML, Obsidian Bases)
- `./obsidian/Asystent/Memory/` - pamięć (EmailWorkflow-*.md, InboxReviewState.md)
- `./obsidian/Asystent/Memory/Ledger/` - rejestr spraw; **czytasz i piszesz wyłącznie przez `scripts/ledger.py`** (`docs/ledger.md`), nigdy przez Read/Edit na plikach

`./obsidian/` to symlink → do listowania używaj `Bash(ls ./obsidian/...)`, NIE Glob. Do szukania kontaktów/notatek używaj `qmd` (MCP).

## Narzędzia

| Operacja | Narzędzie |
|----------|-----------|
| Czytanie/zapis vault | `Read`, `Edit`, `Write` |
| Szukanie kontaktów/notatek | `qmd` (MCP) - NIE Glob |
| Lista plików w vault | `Bash(ls ./obsidian/...)` - NIE Glob |
| Pobranie wątków | `mcp__gmail__search_threads` (z parametrem `filter`) |
| Wyszukiwanie referencyjne (cała poczta) | `mcp__gmail__search_threads` **bez** `filter` (inbox + archiwum + `AI/Done`) |
| Treść wątku (labelki jako nazwy) | `mcp__gmail__get_thread` |
| Draft (nie wysyła) | `mcp__gmail__create_draft` |
| Status wątku (AI/Done\|AI/Triage) | `mcp__gmail__update_thread` z `status: "done"\|"triage"` (NIE przez addLabels) |
| Labele kategorii wątku | `mcp__gmail__update_thread` (addLabels/removeLabels po NAZWACH; opcjonalny `priority: P0..P3`) |
| Archiwizacja (Śmieci/Nieaktualne) | `mcp__gmail__update_thread` z `addLabels:["Nieaktualne"\|"Śmieci", …]` — MCP sam zdejmuje INBOX |
| Rejestr spraw (odłożenia, powiązania, przypomnienia) | `Bash(python3 scripts/ledger.py …)` — kontrakt w `docs/ledger.md` |
| Todoist (jedyna droga — **nie ma MCP Todoista**) | `Bash(python3 scripts/todoist.py …)`: `sync` (diff), `tasks` (odczyt z lustra), `add`, `update`, `reschedule`, `comment`, `sections` |
| Załącznik (zapis na dysk) / treść wiadomości | `mcp__gmail__save_attachment` (→ ścieżka w `.context/attachments/`, bez base64), `mcp__gmail__get_message` |
| Etykieta-kubełek | `mcp__gmail__create_label` |
| Zadanie z maila (**tylko Personal** — Work nie tworzy zadań) | `todoist.py add --case <sprawa>` (tworzy i **od razu wiąże** ze sprawą); aktualizacja istniejącego: `todoist.py reschedule` / `update` / `comment` |
| Zapis faktury PDF (główny agent) | `Write` (tmp `.b64`) + `Bash(base64 -d …)` |
| Batch w subagencie | `Agent` (`model: "sonnet"`) |

## Konta

| Konto | Email |
|-------|-------|
| Personal | kedrzu@gmail.com |
| Work | kedrzu@sigma.clinic |

## Wejście: nieprzetworzone wątki

Filtrowanie po statusie AI/Done|AI/Triage robi MCP — **nie buduj `-label:` ręcznie**:

```
mcp__gmail__search_threads(
  account: <konto>,
  query: "(in:inbox OR (in:sent newer_than:30d))",
  filter: "unprocessed"      // = bez AI/Done i bez AI/Triage
)
```

Filtrowanie działa per-wiadomość: gdy do przetworzonego wątku przyjdzie NOWA wiadomość (przychodząca lub Twoja wysłana), wątek wraca do `unprocessed`. Stare wiadomości z labelami są pomijane, nowe — nie.

## Maile wysłane (lekka ścieżka)

**Wątku NIE klasyfikujemy, jeśli jego najnowsza wiadomość jest od użytkownika** (`kedrzu@gmail.com` lub `kedrzu@sigma.clinic`). Dotyczy to zarówno wątków w pełni wychodzących (np. zadane pytanie), jak i odpowiedzi użytkownika w wątkach przychodzących. Takie wątki idą **lekką ścieżką**:

1. **Wiedza / digital twin** — wyłuskaj kandydatów do pamięci (kontakty: `ostatni_kontakt` + wpis w `## Historia kontaktów`; oraz `Projects.md`/`Work.md`/`Personal.md`/`Timeline.md`/`Insights.md`, gdy mail coś ujawnia). Zapisuje główny agent w Fazie 3 — jak zwykle.
2. **Przypomnienie (warunkowo)** — utwórz kandydata na reminder **tylko** gdy treść wskazuje, że użytkownik czeka na odpowiedź lub ma sam wykonać follow-up („czekam na odpowiedź", „dam znać", „prześlę do…", zadane pytanie bez odpowiedzi). Daty jak w Fazie 3.
3. **Status + priorytet** — oznacz jako done **z priorytetem** (`update_thread(status:"done", priority: …)`; MCP nakłada `AI/Done`, zdejmuje ew. `AI/Triage` i wymaga priorytetu). Priorytet z heurystyki: czekam na odpowiedź / mam zrobić follow-up → **P1**; zwykła konwersacja → **P2**; potwierdzenia / „do wiadomości" / wysłane FYI → **P3**. **Nie** nakładaj labeli kategorii, **nie** twórz draftów, **nigdy** triaż.
4. **Zdejmij `Wymaga odpowiedzi` (warunkowo)** — jeśli wątek ma labelkę `Wymaga odpowiedzi` i **nie czeka już na moją odpowiedź** (odpisałem merytorycznie / sprawa domknięta) → dodaj `removeLabels:["Wymaga odpowiedzi"]` do tego samego `update_thread`. Ocena **semantyczna**, nie „ostatnia wiadomość moja" — autoresponder („odpiszemy wkrótce", potwierdzenie wpłynięcia) **nie** zdejmuje wymogu. `Wymaga działania` zostaje.

> **Wyjątek — wątek należący do sprawy z rejestru:** Twoja odpowiedź często domyka sprawę. Jeśli `ledger query --ref <threadId>` coś zwraca, dopisz do raportu propozycję aktualizacji rekordu (sprawa załatwiona → `close --outcome completed`; dalej otwarta → nowe `due` + wpis w `history`). Zadania Todoist **nie ukańczasz** — to robi użytkownik, a rejestr zauważy to przy najbliższym syncu.

Wątki, w których najnowsza wiadomość jest **przychodząca**, idą normalną ścieżką klasyfikacji (niżej).

## Model wykonania: subagenci na Sonnecie

Główny agent (ten) **orkiestruje**; ciężką pracę per batch zlecaj **subagentom na Sonnecie** (`Agent`, `model: "sonnet"`, `subagent_type: "general-purpose"`). Każdy batch dostaje świeży kontekst i tańszy model.

**Podział odpowiedzialności:**
- **Subagent (Sonnet)** dla batcha (lista threadId + konto + adresy użytkownika + treść rulebooka): czyta wątki (`get_thread`) i dla każdego **najpierw sprawdza, czy najnowsza wiadomość jest od użytkownika** (`kedrzu@gmail.com` / `kedrzu@sigma.clinic`):
  - **Tak → lekka ścieżka** (sekcja „Maile wysłane"): bez klasyfikacji, bez labeli kategorii, bez draftów; `update_thread(status:"done", priority: …)` **z priorytetem z heurystyki** (czekam na odpowiedź/follow-up → P1; konwersacja → P2; FYI → P3) — MCP sam zdejmuje ew. `AI/Triage`; w raporcie zwraca tylko kandydatów do pamięci/kontaktów i ew. przypomnienia. **Jeśli wątek ma `Wymaga odpowiedzi` i nie czeka już na moją odpowiedź** (odpisałem merytorycznie; autoresponder się nie liczy) → dorzuć `removeLabels:["Wymaga odpowiedzi"]` (ocena semantyczna; `Wymaga działania` zostaje).
  - **Nie → klasyfikacja** wg rulebooka: **nakłada labele kategorii / tworzy drafty / ustawia status** przez `update_thread(status:"done"|"triage", …)` + `create_draft`. **Status nakładaj WYŁĄCZNIE parametrem `status`** — MCP sam robi rozłączność (`AI/Done` XOR `AI/Triage`); nie podawaj `AI/Done`/`AI/Triage` w addLabels/removeLabels (MCP odrzuci). **Przy `status:"done"` zawsze nadaj priorytet** — `priority: P0|P1|P2|P3` (rozłączność ogarnia MCP; poziomy → sekcja „Priorytety"). MCP **wymaga** priorytetu przy każdym `AI/Done`. **Archiwizacja = `Śmieci`/`Nieaktualne`**: wątek opuszcza INBOX wyłącznie gdy dostaje marker `Śmieci` (bezpieczny do usunięcia) i/lub `Nieaktualne` (stracił aktualność, zostaw do referencji) — dodajesz go w `addLabels`, a MCP **sam zdejmuje INBOX**. Markery nakładaj **na kategorię** (np. `Zakupy`+`Śmieci`), bo są ortogonalne. Sama kategoria (np. `Zakupy`) **nie** archiwizuje — zostaje w INBOX; MCP odrzuci `removeLabels:["INBOX"]` bez markera. Gdy reguła mówi „czasowy, jeszcze aktualny" → `update_thread(status:"done", …kategoria, priority)` **plus rekord odłożenia w raporcie** (sekcja „Odkładanie na później"); gdy reguła mówi „już nieaktualny" → `update_thread(status:"done", addLabels:["Nieaktualne", …kategoria/Śmieci], **priority**)`. **Śmieci, Nieaktualne i odłożone też dostają priorytet** (zwykle P3 dla szumu).

  Wątki z **bucketu dojrzałych spraw** (przekazane subagentowi z adnotacją „wraca z rejestru: `<powód>`") re-oceniaj wg sekcji „Odkładanie na później": dalej aktualny → `update_thread` bez zmian statusu + w raporcie nowe `due`; nieaktualny → `update_thread(status:"done", addLabels:["Nieaktualne", …], priority)` (MCP archiwizuje) + `close --outcome obsolete`; wymaga akcji → obsłuż normalnie; niepewny → `status:"triage"`. **Powód z rekordu jest częścią wejścia** — mówi, po co ten mail wraca, więc nie zgaduj tego z treści od nowa.

  **Brama adresatów (czy akcja jest moja?)** — zanim nadasz akcję (task na Personal / marker `Wymaga …` na Work), oceń, na ile mail dotyczy mnie, a na ile innych adresatów (sekcja rulebooka „Adresaci — czy akcja jest moja?"): pozycja w `to` vs `cc` (oba dostępne w `get_thread`/`get_message` najnowszej przychodzącej wiadomości), imienne zaadresowanie w treści, i czy akcja należy do mojej domeny czy kolegi (digital twin: `Work.md`, `Kontakty/`). **Akcja jasno moja** → obsłuż wg konta jak niżej (Personal: task; Work: marker `Wymaga …`). **Akcja jasno cudza** (jestem tylko w Cc/FYI, główny adresat to ktoś inny, sprawa w jego kompetencji) → **bez akcji**: sklasyfikuj + `status:"done"` z priorytetem, zostaw/archiwizuj wg kategorii. **Niejasne** (jeden z wielu w To, sprawa może być moja lub cudza) → `status:"triage"` z priorytetem. Rygor głównie na koncie Work; na Personal lekko (rzadko dotyczy). To nadal autonomiczne — brama sama rozstrzyga, nie pyta o każdy mail.

  **Akcje (Wymaga działania / Wymaga odpowiedzi) — zależnie od konta (rulebook „Akcje")** — gdy klasyfikacja daje `Wymaga działania`/`Wymaga odpowiedzi` **i brama adresatów wskazała „akcja moja"**:
  - **Personal** (`EmailWorkflow-Personal.md`, sekcja „Akcje → Todoist") — nałóż marker na mail: `update_thread(status:"done", addLabels:["Wymaga działania"|"Wymaga odpowiedzi","IMPORTANT"], priority)` (zostaje w INBOX). **Zadania NIE tworzysz sam** — zgłaszasz je w raporcie (pole `akcje`: co zrobić, proponowany klucz sprawy, termin, priorytet p1..p4, sekcja wg kategorii, Gmail-link, oraz `kandydat_na: nowa_sprawa | <id istniejącej sprawy z digestu>`). Zadania zakłada i aktualizuje **główny agent** — patrz niżej.
  - **Work** (`EmailWorkflow-Work.md`, sekcja „Akcje → markery Wymaga (BEZ tasków)") — **BEZ zadania i bez odkładania**: `update_thread(status:"done", addLabels:[<kategoria>,"Wymaga działania"|"Wymaga odpowiedzi","IMPORTANT"], priority)`. Wątek zostaje w INBOX jako marker do ręcznej obsługi; wraca do pipeline'u dopiero gdy dojdzie nowa wiadomość (filtr per-wiadomość MCP), wtedy re-ocena zdejmuje `Wymaga …` gdy sprawa domknięta.

  W obu wariantach akcja jest **autonomiczna** (bez pytania) — gdy mail wyraźnie wymaga działania, działaj od razu (CLAUDE.md, Safety & Permissions).

  **Dedup — dlaczego zadania zakłada główny agent.** Faktura i ponaglenie do tej samej faktury to jedna sprawa, nie dwie. Subagent widzi tylko swój batch, więc gdyby sam tworzył zadania, dwa batche w dobrej wierze założyłyby dwa zadania do jednej sprawy — a to jest dokładnie ten błąd, który ten system likwiduje. Dlatego subagent **rozpoznaje** sprawę i raportuje, a **jeden proces** (główny agent, widzący wszystkie raporty naraz) decyduje i zapisuje. Rozpoznanie po Twojej stronie:
  1. **Wątek już znany?** `ledger query --ref <threadId> --select id,title,refs` → trafienie = ta sama sprawa, podaj jej `id`.
  2. **Sprawa już znana?** Porównaj z **digestem spraw konta** (dostajesz go w prompcie) i `ledger find "<podmiot/numer/kwota>"` (obejmuje archiwum). Dopasowuj po podmiocie **i** okresie/numerze dokumentu/kwocie — nie po samym nadawcy, bo E.ON przysyła fakturę co miesiąc.
  3. **Sprawa zamknięta w archiwum, ale to nowy okres** (nowa faktura, nie ponaglenie) → `kandydat_na: nowa_sprawa` z nowym kluczem niosącym okres.

  **Faktury/paragony za zakupy** (Allegro i inne sklepy) → kategoria `Zakupy` + marker (model ortogonalny). **Zasada nadrzędna: o kategorii i trwałości decydują POZYCJE z załącznika, nie nadawca/temat/treść maila.** Wątek jest/zawiera fakturę z załącznikiem → **subagent ZAWSZE sam otwiera PDF** (`save_attachment` → `Read`) i ustala produkt **PRZED nadaniem kategorii** — zwłaszcza gdy nadawca/temat zdają się przesądzać kategorię (software house może fakturować iPhone, „faktura B2B" bywa zwykłym zakupem); to przypadek najwyższego ryzyka, nie bezpieczny. Nie zgaduj ze snippeta i nie odkładaj odczytu PDF na później. Brak załącznika i produkt nieznany skądinąd → treść maila; dalej niejasne → `status:"triage"`. Po ustaleniu: zakup towaru/usługi konsumenckiej → **`Zakupy`** — **NIGDY** `Finanse`/`Księgowość`, nawet gdy to faktura VAT / koszt firmowy / jest NIP. `Finanse`/`Księgowość` tylko gdy **pozycje** są bezsprzecznie **NIEzakupowe** (wyciągi, ZUS/CEIDG, podatki, subskrypcje/usługi B2B) — sam „usługowy" wygląd nadawcy nie wystarcza. Dopiero po „to zakup → `Zakupy`" rozstrzygnij marker:
  - **Trwałe dobro >100 zł** (sekcja „Faktury → folder Rachunki") → zwróć **kandydata do zapisu** PDF (threadId, messageId, attachmentId, dostawca, kwota, data, numer, produkt, kategoria, nazwa pliku; przy niejasności `save_attachment` → `Read` zapisanego PDF → odczyt tekstu). Zapis PDF+notatki robi główny agent (subagenci nie piszą do vault). Mail: po zapisaniu → `update_thread(status:"done", addLabels:["Zakupy","Nieaktualne"], priority)` (zostaje jako referencja, MCP archiwizuje).
  - **Konsumpcyjne / tanie drobne** (jedzenie, leki, kosmetyki, suplementy) — niezapisywane → `update_thread(status:"done", addLabels:["Zakupy","Śmieci"], priority)`.
  - **Faktury wFirma** (za usługę/subskrypcję, nie zakup) → `addLabels:["Śmieci"]`. Trwałość niejasna po PDF → `status:"triage"`.

  W obu przypadkach zwraca **uporządkowany raport** (per wątek: ścieżka, klasyfikacja, akcja, powód triażu, kandydaci do pamięci/kontaktów, **kandydaci faktur do zapisu w Rachunki**; na Work zamiast zadań raportuj nadane markery `Wymaga …`) **oraz**: `rekordy` — listę obiektów JSON gotowych do `ledger upsert` (nowe sprawy, dopięcia wątku do istniejącej sprawy, odłożenia, przypomnienia); `akcje` — zadania do założenia/aktualizacji (opis wyżej); `do_zamkniecia` — id spraw + `outcome` + powód. Subagent **czyta** rejestr i Todoista (`ledger query`/`find`, `todoist.py tasks`), ale **nie pisze** — ani do rejestru, ani do vault, ani do Todoista.
- **Główny agent (ten)**: pobiera listę, dzieli na batche, odpala subagentów (**kilka wywołań `Agent` w jednej wiadomości = równolegle**; różne threadId → bezpieczne równoległe labelowanie), zbiera raporty i **sam robi wszystkie zapisy**: rejestr (`ledger upsert`/`close`), zadania (`todoist.py add --case` / `reschedule` / `update` / `comment`), pamięć i pliki vault (Edit/Write).

  **Zapisywanie zadań (Personal), po zebraniu wszystkich raportów** — kolejność jest istotna, bo `--case` wymaga istniejącego rekordu:
  1. **Scal `akcje` między batchami** po kluczu sprawy. Dwie pozycje wskazujące na tę samą sprawę = jedno zadanie, nie dwa. To ten moment, w którym duplikat jest łapany.
  2. **Znana sprawa z otwartym zadaniem** → **bez nowego zadania**: `todoist.py reschedule --id <task> --due <nowy termin>` gdy zmienił się termin, `update` gdy zmienił się priorytet/treść, i **zawsze** `comment --text "<co nowego> <Gmail-link>"`. Do rekordu: `upsert` z nowym `ref` wątku, wpisem w `history` i nowym `due`.
  3. **Nowa sprawa** → najpierw `ledger upsert` (rekord), potem `todoist.py add --content … --description "<kontekst + Gmail-link>" --priority <p1..p4> --project 6Crg7HhPc5pxM22C [--section …] [--due …] --case <klucz>`. Flaga `--case` dopisuje `todoist:task:<id>` do rekordu w tym samym wywołaniu — nie rozdzielaj tych kroków ręcznie.
  4. **Zapis się nie powiódł** (brak sieci, cofnięty token) → **nie gub sprawy**: zostaw rekord z `data.pending_task: true` i powodem, a pozycję wypisz w podsumowaniu do „Do decyzji". Następny run dokończy.

  Zadania **nie ukańczasz i nie kasujesz** — `todoist.py` nie ma takich komend. Ukończenie należy do użytkownika; zauważa je Faza 0 i wtedy domykamy maila.

Batch = ~5-8 wątków. Subagentowi przekaż treść rulebooka w prompcie (albo ścieżkę do odczytu), konwencję labelek poniżej oraz **digest aktywnych spraw konta** (`ledger query --context <konto> --kind task --select id,title,due,refs,reason`) — to podstawa rozpoznawania spraw.

## Konwencja AI/Done i AI/Triage

Status nakładasz **wyłącznie** parametrem `status` w `update_thread` — nigdy ręcznie przez addLabels/removeLabels (MCP odrzuci `AI/Done`/`AI/Triage`/`AI/Defer/*` w tych polach). `AI/Done` i `AI/Triage` są **rozłączne**: MCP nakłada wybrany status i zdejmuje przeciwny. Archiwizacja (`Nieaktualne`/`Śmieci`) idzie przez `update_thread` (addLabels) — MCP sam zdejmuje INBOX. Wszystkie zmiany jednego wątku (status, priorytet, labelki) idą **jednym** `update_thread`. Odłożenie na później **nie jest labelką** — to `status:"done"` plus rekord w rejestrze.

| `status` | Label | Kiedy |
|----------|-------|-------|
| `"done"` | `AI/Done` | Wątek w pełni obsłużony wg rulebooka, **odłożony na później** (rekord w rejestrze trzyma datę powrotu) **lub** z najnowszą wiadomością od użytkownika (lekka ścieżka). Wymaga `priority`. |
| `"triage"` | `AI/Triage` | Reguła nie obejmuje wątku jednoznacznie LUB niepewność → zostaw w INBOX, zapisz powód. **Nigdy** dla wątków z najnowszą wiadomością od użytkownika |

Jeśli wątek był wcześniej `AI/Triage`, a teraz jest w pełni obsłużony: po prostu `update_thread(status:"done", priority: …)` — MCP sam zdejmie `AI/Triage`. `update_thread` nakłada label na wszystkie wiadomości wątku.

**Luka kontekstowa = prawidłowy powód `AI/Triage`** (autopilot **nie pyta** — protokół CLAUDE.md „Luki kontekstowe" dla przepływów autonomicznych): nadawca/termin/dokument nieczytelny nawet po obejrzeniu treści+PDF i research w vault → `status:"triage"` + zapisany powód, leć dalej. Rozstrzygnie i utrwali to interaktywny `/email-triage`. Nie blokuj i nie zgaduj.

## Priorytety (P/0..P/3)

**Każdy przetwarzany wątek dostaje dokładnie jeden priorytet** — bez wyjątków. Dotyczy klasyfikacji, **śmieci, Nieaktualne, odłożonych i poczty wysłanej** (lekka ścieżka). MCP **wymusza** to twardo: każde nałożenie `AI/Done` wymaga priorytetu, a etykiety są **rozłączne** — MCP sam zdejmuje poprzedni `P/*`. Priorytet podajesz parametrem `priority` z wartością **`P0`/`P1`/`P2`/`P3`** (MCP mapuje ją na label `P/0`…`P/3`), nie ręcznym labelem.

| Label | `priority` | Poziom | Znaczenie |
|-------|-----------|--------|-----------|
| `P/0` | `P0` | Krytyczny | Działanie dziś. Deadline dziś/jutro, awaria, sprawa pilna od szefa/klienta/VIP. |
| `P/1` | `P1` | Wysoki | Działanie/odpowiedź w kilka dni. Faktury z terminem, sprawy projektowe, prośby o odpowiedź. |
| `P/2` | `P2` | Normalny | Do wiadomości, bez pilnego działania. Istotne powiadomienia, potwierdzenia, info. |
| `P/3` | `P3` | Niski/szum | Można zignorować. Newslettery, promocje, auto-powiadomienia, śmieci, większość nieaktualnych. |

Domyślne poziomy per kategoria są w rulebooku (`EmailWorkflow-{konto}.md`, sekcja „Priorytety"). **Poczta wysłana (lekka ścieżka)**: czekam na odpowiedź / mam follow-up → **P1**; zwykła konwersacja → **P2**; potwierdzenia / FYI → **P3**. **Śmieci i Nieaktualne** → zwykle **P3** (chyba że to ważna rzecz odkładana do archiwum — wtedy wyżej).

## Śmieci ⊥ Nieaktualne i archiwizacja

Dwie ortogonalne labelki-markery cyklu życia maila:
- **`Nieaktualne`** — mail stracił aktualność, ale **zostawiamy** go do referencji/wyszukiwania na przyszłość.
- **`Śmieci`** — **bezpieczny do usunięcia**, bez wartości na przyszłość (sam marker — nigdy nie usuwamy automatycznie).
- Łączą się: nieaktualny **i** bezpieczny do usunięcia → obie. Nakłada się je **na kategorię** (`Zakupy`, `Finanse`, `Newsletter`…), bo kategoria i marker są ortogonalne (np. tani paragon → `Zakupy`+`Śmieci`).

**Archiwizacja = `Śmieci`/`Nieaktualne`**: wątek opuszcza INBOX **wyłącznie** gdy dostaje jeden z tych markerów — wtedy MCP **sam zdejmuje INBOX**. Dodajesz marker w `addLabels` (`update_thread`), nie zdejmujesz INBOX ręcznie. Sama kategoria (`Zakupy`/`Newsletter`/`Finanse`…) tylko taguje i **zostawia** wątek w INBOX; MCP odrzuci `removeLabels:["INBOX"]` bez markera. Mail bez `Śmieci`/`Nieaktualne` **nigdy nie jest archiwizowany sam** — także mail odłożony na później zostaje w INBOX.

## Odkładanie na później i Nieaktualne (maile z datą ważności)

Część maili jest dziś OK, ale **zdezaktualizuje się w przyszłości** (event, deadline, ważność oferty), albo są **już całkowicie nieaktualne** (event minął, stara dostawa).

- **Odłożenie** — `update_thread(status:"done", …kategoria, priority)` (wątek znika z `unprocessed`, **zostaje w INBOX**) **plus rekord w rejestrze** z datą powrotu i **powodem**:
  ```json
  {"id":"<klucz-sprawy>","kind":"task","context":"personal","source":"gmail",
   "title":"<temat>","due":"<data powrotu>","reason":"<po co wraca>",
   "refs":["gmail:personal:thread:<threadId>"]}
  ```
  Wątek wraca **dopiero gdy data minie** — przez `ledger due`. Odłożony na pół roku nie jest dotykany przez pół roku. `reason` jest obowiązkowy i ma być konkretny („czekam na dostawę", „oferta ważna do 27.08") — to on odróżnia sensowne odłożenie od zamiecenia pod dywan i to on wraca do subagenta przy dojrzeniu.
- **Nieaktualne** — stan terminalny. `update_thread(status:"done", addLabels:["Nieaktualne", …kategoria; +"Śmieci" jeśli reguła], priority)`. MCP nakłada labelki + `AI/Done` i **sam archiwizuje** (zdejmuje INBOX). Jeśli wątek miał rekord — `ledger close --outcome obsolete`.

**Odkładaj/oznaczaj Nieaktualne TYLKO gdy reguła z rulebooka to mówi.** Nie zgaduj z góry, że mail jest nieaktualny — jeśli reguła nie jest jednoznaczna → `AI/Triage` (decyzja w `/email-triage`).

**Wybór daty powrotu**: data eventu / deadline / koniec ważności oferty z treści maila. **Gdy z maila nie wynika konkretna data → fallback +14 dni.**

**Kanoniczny przykład — przesyłki i statusy zamówień**: powiadomienie o przesyłce / statusie zamówienia (nadane, w drodze, do odbioru, tracking) → odłóż do przewidywanej daty dostawy (brak daty → **+7 dni**) → po dojrzeniu zwykle już dostarczone → `Nieaktualne`+`Śmieci` (dostarczone i bez wartości). Wyraźnie stary mail (paczka na pewno dostarczona) → od razu `Nieaktualne`+`Śmieci`. Paragon/faktura/dokument zakupu → wg rulebooka (`Zakupy`+marker).

**Bucket dojrzałych spraw (`ledger due`)** — sprawy, których data powrotu właśnie minęła. Re-ocena wg rulebooka, z `reason` z rekordu jako kontekstem:
- dalej aktualny → **nowe `due`** w rekordzie (inaczej wracałby codziennie z tą samą datą), mail bez zmian;
- teraz nieaktualny → `update_thread(status:"done", addLabels:["Nieaktualne", …], priority)` (MCP archiwizuje) + `close --outcome obsolete`;
- teraz wymaga akcji → obsłuż normalnie (labele kategorii / draft / zadanie);
- niepewny → `status:"triage"` (rekord zostaje otwarty, z `due` przesuniętym na dziś+3).

## Proces

### Faza 0: Uzgodnienie z Todoistem

Zanim ruszysz skrzynkę, sprawdź **co się stało z zadaniami** — inaczej mail wróci z pytaniem o sprawę, którą użytkownik dawno załatwił.

1. `Bash: python3 scripts/todoist.py sync` → **diff** (kilka linijek, nie lista zadań).
2. Dla każdej pozycji z niepustym `tasks` (id spraw z rejestru):
   - **completed** → sprawa domknięta: `update_thread(status:"done", addLabels:["Nieaktualne"], priority)` na **wszystkich** wątkach z `refs` (MCP archiwizuje) → `ledger close --outcome completed --reason "<z komentarza, jeśli jest — inaczej: zadanie ukończone>"`.
   - **updated** → `ledger upsert` z nowym `due` (z terminu zadania) i wpisem w `history`. **Zero ruchu na mailu.**
   - **deleted** → `update_thread(status:"triage")` z powodem „zadanie usunięte, sprawa nierozstrzygnięta" → `close --outcome gone`.
   - **created** bez `tasks` → zignoruj (zadanie spoza rejestru).
3. `stale_links` z tego samego wyjścia → sprawy wskazujące na zadanie ukończone/nieistniejące, których diff nie pokazał. Obsłuż jak `completed`/`deleted` wyżej.

#### Żniwo wiedzy z ukończonych zadań

Ukończone i usunięte zadania przychodzą z polami `comments` i `changes` — **przejrzyj je zawsze, także dla zadań bez sprawy w rejestrze** (`tasks: []`), bo użytkownik zostawia tam notatki również przy zadaniach, które sam sobie założył. Brak tych pól = brak notatek; **cisza jest poprawnym wynikiem i nie generuje żadnego wpisu.**

To jest moment, w którym system się uczy. Komentarz przy zadaniu bywa cenniejszy niż sam fakt ukończenia: *„Nie będziemy już opłacać Disneya, więc ignoruj te maile"* zapobiega temu, że za tydzień znów potraktujesz ponaglenie jako `Wymaga działania` i znów założysz zadanie. Rozdziel wnioski na trzech adresatów:

| Rodzaj notatki | Rozpoznanie | Gdzie ląduje |
|---|---|---|
| **Instrukcja na przyszłość** | tryb rozkazujący do agenta albo deklaracja trwałej decyzji: „ignoruj te maile", „nie twórz już zadań na X", „od teraz zawsze…", „nie płacimy już za…" | **reguła w rulebooku** `EmailWorkflow-{konto}.md` + fakt w pamięci |
| **Notatka o wykonaniu / fakt o świecie** | „zrobione przez telefon", „konto zamknięte", „nie mogę tego zrobić, bo…" | pamięć: `Personal.md`/`Work.md`/`Projects/`, zdarzenie z datą → `Timeline.md` |
| **Instrukcja o niejasnym zakresie** | nie wiadomo, czy dotyczy tego nadawcy, całej kategorii, czy jednorazowo | fakt do pamięci + **propozycja reguły do „Do decyzji"** (nie zgaduj zakresu) |

`changes` (gdy jest) czytaj jako sygnał o **jakości Twojej własnej pracy**, nie o sprawie: `postponed: 8` → termin był źle oszacowany; `edited_by_user: true` → źle sformułowałeś treść zadania; `moved: true` → zła sekcja/kategoria. Powtarzalne wzorce dopisuj do `Insights.md`.

> **Komentarz w zadaniu sam stanowi opt-in na regułę.** To wyjątek od zasady „zmiany rulebooka zawsze na podwójny opt-in" (CLAUDE.md) i jedyny taki: użytkownik napisał tę instrukcję świadomie, na piśmie i wprost do Ciebie, a rutyna o 8:00 nie ma kogo dopytać. Zapisując regułę, **zacytuj komentarz, datę i id zadania jako źródło** w wierszu reguły i **zgłoś to w podsumowaniu** — informacyjnie, nie jako pytanie. Gdy zakres jest niejednoznaczny, regułę zostaw do „Do decyzji".

Sync nie działa (brak tokenu, błąd sieci) → **nie blokuj**: odnotuj w podsumowaniu „uzgodnienie Todoista pominięte: <powód>" i leć dalej. Uzgodnienie nadrobi następny run.

### Faza 1: Sesja i stan

1. Przeczytaj `Asystent/Memory/InboxReviewState.md` (`Read`).
   - Status `in_progress` < 1h temu → **kontynuuj automatycznie** (bez pytania), pomijając wątki z "Processed Thread IDs"; odnotuj w logu sesji "wznowiono sesję z <timestamp> (X/Y)".
   - Brak / stary (≥ 1h) / `completed` → nowa sesja.
2. Pobierz wejście dla obu kont, policz total/batche, zainicjuj stan (format niżej). Dwa buckety:
   - **nieprzetworzone**: `search_threads(filter:"unprocessed")`;
   - **dojrzałe sprawy**: `Bash: python3 scripts/ledger.py due --select id,title,due,reason,refs` — sprawy, których data powrotu minęła (sekcja „Odkładanie na później"). Wyciągnij z `refs` threadId do ponownego odczytu. Pusto → pomiń.
3. Wczytaj rulebook obu kont oraz `Preferences.md`. Pobierz **digest aktywnych spraw** per konto (`ledger query --context <konto> --kind task --select id,title,due,refs,reason`) — pójdzie do promptów subagentów jako podstawa deduplikacji. **NIE ładuj listy kontaktów** — szukaj na żądanie przez `qmd`.

### Faza 2: Pętla batchy (subagenci Sonnet)

Dla każdego batcha:
1. Weź kolejne ~5-8 nieprzetworzonych threadId (pomiń te już w "Processed Thread IDs" tej sesji). Grupowanie po nadawcy/temacie pomaga subagentowi widzieć sprawę w całości, ale **nie jest zabezpieczeniem** — przed duplikatem chroni to, że zadania zakłada dopiero główny agent po zebraniu wszystkich raportów.
2. Odpal subagenta Sonnet z: konto, lista threadId, treść rulebooka, konwencja labelek, digest spraw konta. Subagent przetwarza i zwraca raport. Batche niezależnych kont/zakresów możesz puścić równolegle.
3. Zbierz raport, **zapisz `rekordy` do rejestru** (`ledger upsert --stdin`) i wykonaj `do_zamkniecia` (`ledger close`), potem zaktualizuj `InboxReviewState.md` (`Edit`): dopisz threadId, liczniki, batch, findings, "Last Updated". **Powód triażu zapisuj w tabeli Priority/Triage Emails** (kolumna Action). Zgłoszone `akcje` **odkładaj do Fazy 3** — zadania zakładasz dopiero, gdy widzisz komplet raportów.
4. Krótki progres: `Batch N gotowy: X wątków. Kontynuuję...`

### Faza 3: Zakończenie

1. **Zadania (Personal)** — scal `akcje` ze wszystkich raportów po kluczu sprawy i wykonaj wg sekcji „Zapisywanie zadań" wyżej: znana sprawa → `reschedule`/`update`/`comment`; nowa → `ledger upsert` + `todoist.py add --case`. Policz nowe / zaktualizowane do podsumowania.
2. **Przypomnienia** — dla maili wymagających follow-up dopisz rekord do rejestru (`ledger upsert`) z `data.type: "follow-up"`, `due` = data przypomnienia, `reason` = na co czekam, `refs` = wątek. Dotyczy to też maili wysłanych z lekkiej ścieżki, gdy użytkownik czeka na odpowiedź lub ma sam zrobić follow-up. Daty: deadline w mailu → ta data; oczekiwana odpowiedź → +3-5 dni roboczych; czekanie na dokument → obietnica +1 dzień; okresowe → za tydzień.
3. **Faktury → Rachunki** — dla kandydatów z raportów subagentów (faktura trwałego dobra >100 zł): `save_attachment(account, messageId, attachmentId)` → zwraca `path` w `.context/attachments/<messageId>/<plik>` (plik na dysku, bez base64) → `Bash: mv "<path>" "./obsidian/Rachunki/<data ISO> <opis>.pdf"`; potem `Write` notatkę `.md` (szablon w rulebooku, sekcja „Faktury → folder Rachunki"). **Dedup** przed zapisem: `Bash: ls ./obsidian/Rachunki/` — plik o tej nazwie już jest → pomiń.
4. **Pamięć / digital twin** — skomituj zakolejkowane aktualizacje:
   - **Kontakty**: `qmd` po emailu nadawcy; dla znanych zaktualizuj `ostatni_kontakt` + dopisz wpis do `## Historia kontaktów` (data, typ Email, link Gmail). Dla nowych ważnych — utwórz profil w `./obsidian/Kontakty/`.
   - Inne: `Projects.md`, `Work.md`/`Personal.md`, `Timeline.md`, `Insights.md` — gdy maile coś ujawniły.
5. **Sfinalizuj stan**: status `completed`, wyczyść "Processed Thread IDs", zachowaj findings.
6. **Kontrola rejestru**: `Bash: python3 scripts/ledger.py validate`. Ostrzeżenia o tym samym wątku/zadaniu w kilku sprawach = duplikat, który powstał w tej sesji — scal rekordy (`upsert` + `close --outcome obsolete` na zdublowanym) i odnotuj w podsumowaniu.
7. **Raport sterty triażu**: policz aktualną stertę `search_threads(query:"in:inbox", filter:"triage")` na obu kontach. Jeśli duża (≈>10), poleć: "Masz N wątków w AI/Triage — odpal `/email-triage`, żeby je rozkminić razem i poprawić reguły."
8. Podsumowanie (niżej).

## Format stanu (`InboxReviewState.md`)

```markdown
# Inbox Review State

## Current Session
- **Started**: [ISO timestamp]
- **Status**: in_progress | completed
- **Current Batch**: N

## Progress
### Personal (kedrzu@gmail.com)
- Total: [n] / Processed: [n]
#### Processed Thread IDs
- [threadId] (opis)
### Work (kedrzu@sigma.clinic)
- Total: [n] / Processed: [n]
#### Processed Thread IDs
- ...

## Accumulated Findings
### Priority / Triage Emails
| Konto | Od | Temat | Akcja + powód triażu |
|-------|----|-------|----------------------|
### Drafts Created
### Labels Applied
### Memory Updates Pending

## Last Updated
[ISO timestamp]
```

## Format wyjścia

### Podsumowanie sesji
**Przetworzone:** X wątków w N batchach — Personal (X), Work (Y)

#### Priorytety / do uwagi (AI/Triage)
| Konto | Od | Temat | Streszczenie | Sugerowana akcja |
|-------|----|-------|--------------|------------------|

#### Wykonane akcje
- Drafty: [...]
- Labele: [...]
- Priorytety: P0 (a) / P1 (b) / P2 (c) / P3 (d)
- Odłożone: N (w tym przesunięte dojrzałe) / Oznaczone Nieaktualne: M
- Zadania: nowe (a) / zaktualizowane zamiast duplikatu (b) / domknięte po ukończeniu przez Ciebie (c)
- Wnioski z ukończonych zadań: N (reguły zapisane: M) — wypisz każdą zapisaną regułę jednym zdaniem z cytatem źródłowym
- Przypomnienia: [...]

#### Pamięć zaktualizowana
- Kontakty: [...] / Nowe kontakty: [...] / Inne: [...]

#### Sterta triażu
- AI/Triage: N wątków → (jeśli duża) poleć `/email-triage`

## Bezpieczeństwo

- **Nigdy nie wysyłaj** maili — tylko drafty (`create_draft`).
- **Nigdy nie usuwaj** maili/zadań/wydarzeń/notatek.
- **Nigdy nie pytaj** — autopilot bywa uruchamiany z harmonogramu (`/do-your-job`, 8:00 pon-pt), gdzie nikogo nie ma po drugiej stronie; pytanie = zawieszony run. Wątek `IMPORTANT` / ważny, którego rulebook **nie** pokrywa jednoznacznie → `update_thread(status:"triage")` z powodem zamiast pytania (zgodnie z CLAUDE.md #6 nie labelujemy ważnych maili „na czuja"; rozstrzygnie `/email-triage`). Gdy reguła pokrywa go wprost — działaj normalnie, autonomicznie.
- **Maile akcyjne** (`Wymaga działania`/`Wymaga odpowiedzi`) obsługiwane **autonomicznie, bez pytania** **i tylko gdy brama adresatów wskazała „akcja moja"** (akcja jasno cudza → bez markera; niejasna → `AI/Triage`). Mechanika **zależy od konta**: **Personal** → zadanie Todoist + rekord sprawy w rejestrze (sekcja „Akcje → Todoist" rulebooka Personal); **Work** → **BEZ zadania**, tylko marker `Wymaga …` + `status:"done"` (sekcja „Akcje → markery Wymaga" rulebooka Work).
- **Zadania: tworzysz i aktualizujesz, nigdy nie ukańczasz ani nie kasujesz.** Aktualizacja istniejącego zadania (termin, priorytet, treść, komentarz) jest wręcz oczekiwana, gdy przychodzi kolejny mail w tej samej sprawie — to jedyny sposób, żeby nie mnożyć duplikatów. Zamykanie zadań należy do użytkownika; agent tylko to zauważa (Faza 0) i domyka wtedy maila.
- **Faktury trwałych dóbr >100 zł** zapisywane są do `./obsidian/Rachunki/` (PDF + notatka) automatycznie wg rulebooka; to zapis lokalny, niczego nie wysyła.
- **Nigdy nie blokuj**: niejasne → `AI/Triage` + powód, leć dalej.
- Każdy przetworzony wątek przychodzący dostaje `AI/Done` albo `AI/Triage`; archiwizowane dostają dodatkowo `Nieaktualne`/`Śmieci`. Odłożenie na później **nie jest labelką** — `AI/Done` + rekord w rejestrze z datą powrotu.
- **Każdy przetwarzany wątek dostaje priorytet** (`priority: P0..P3`) — klasyfikacja, śmieci, Nieaktualne, odłożone i poczta wysłana. MCP wymusza priorytet przy każdym `AI/Done`.
- **Archiwizacja = `Śmieci`/`Nieaktualne`** — wątek opuszcza INBOX wyłącznie z tym markerem (MCP sam zdejmuje INBOX); kategoria sama tylko taguje i zostawia w INBOX; zdjęcie INBOX bez markera MCP odrzuci.
- **Odkładanie/Nieaktualne tylko wg reguły z rulebooka** — nie zakładaj z góry, że mail jest nieaktualny; niejasne → `AI/Triage`.
- **Rejestr wyłącznie przez `scripts/ledger.py`** — nigdy Read/Edit na plikach `.jsonl`, nigdy ręczna edycja `Otwarte.md` (jest generowany).
- Wątki z najnowszą wiadomością od użytkownika idą lekką ścieżką: zawsze `AI/Done`, **nigdy** `AI/Triage`, bez labeli kategorii i bez draftów.
- Zapisuj stan po KAŻDYM batchu (wznawianie po przerwaniu). ThreadId = źródło prawdy postępu.
- Komunikuj po polsku.
