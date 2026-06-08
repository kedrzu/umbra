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
- `./obsidian/Asystent/Memory/` - pamięć (EmailWorkflow-*.md, EmailReminders.md, InboxReviewState.md)

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
| Odłożenie wątku z datą | `mcp__gmail__update_thread` (account, threadId, `deferUntil`=`RRRR-MM-DD`, `priority` wymagany) |
| Archiwizacja (Śmieci/Nieaktualne) | `mcp__gmail__update_thread` z `addLabels:["Nieaktualne"\|"Śmieci", …]` — MCP sam zdejmuje INBOX |
| Sprzątanie pustych labelek defer | `mcp__gmail__cleanup_defer_labels` (account) |
| Załącznik (zapis na dysk) / treść wiadomości | `mcp__gmail__save_attachment` (→ ścieżka w `.context/attachments/`, bez base64), `mcp__gmail__get_message` |
| Etykieta-kubełek / link `TODO/<id>` | `mcp__gmail__create_label` |
| Task z maila / sekcje / sprawdzenie ukończenia | `mcp__todoist__add-tasks`, `mcp__todoist__find-sections`, `mcp__todoist__fetch-object`, `mcp__todoist__find-completed-tasks`, `mcp__todoist__find-tasks` |
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
3. **Status + priorytet** — oznacz jako done **z priorytetem** (`update_thread(status:"done", priority: …)`; MCP nakłada `AI/Done`, zdejmuje ew. `AI/Triage`/`AI/Defer/*` i wymaga priorytetu). Priorytet z heurystyki: czekam na odpowiedź / mam zrobić follow-up → **P1**; zwykła konwersacja → **P2**; potwierdzenia / „do wiadomości" / wysłane FYI → **P3**. **Nie** nakładaj labeli kategorii, **nie** twórz draftów, **nigdy** triaż.
4. **Zdejmij `Wymaga odpowiedzi` (warunkowo)** — jeśli wątek ma labelkę `Wymaga odpowiedzi` i **nie czeka już na moją odpowiedź** (odpisałem merytorycznie / sprawa domknięta) → dodaj `removeLabels:["Wymaga odpowiedzi"]` do tego samego `update_thread`. Ocena **semantyczna**, nie „ostatnia wiadomość moja" — autoresponder („odpiszemy wkrótce", potwierdzenie wpłynięcia) **nie** zdejmuje wymogu. `Wymaga działania` zostaje.

> **Wyjątek — wątek z labelką `TODO/*` (powiązany task):** zamiast gołego `status:"done"` zrób **re-check ukończenia taska** (Twoja odpowiedź często domyka zadanie) — wg rulebooka „Akcje → Todoist": `fetch-object(type:"task")`/`find-completed-tasks` → COMPLETED → `update_thread(status:"done", addLabels:["Nieaktualne"], priority)` (MCP archiwizuje); OPEN → `update_thread(deferUntil:"NOWA data", priority)`.

Wątki, w których najnowsza wiadomość jest **przychodząca**, idą normalną ścieżką klasyfikacji (niżej).

## Model wykonania: subagenci na Sonnecie

Główny agent (ten) **orkiestruje**; ciężką pracę per batch zlecaj **subagentom na Sonnecie** (`Agent`, `model: "sonnet"`, `subagent_type: "general-purpose"`). Każdy batch dostaje świeży kontekst i tańszy model.

**Podział odpowiedzialności:**
- **Subagent (Sonnet)** dla batcha (lista threadId + konto + adresy użytkownika + treść rulebooka): czyta wątki (`get_thread`) i dla każdego **najpierw sprawdza, czy najnowsza wiadomość jest od użytkownika** (`kedrzu@gmail.com` / `kedrzu@sigma.clinic`):
  - **Tak → lekka ścieżka** (sekcja „Maile wysłane"): bez klasyfikacji, bez labeli kategorii, bez draftów; `update_thread(status:"done", priority: …)` **z priorytetem z heurystyki** (czekam na odpowiedź/follow-up → P1; konwersacja → P2; FYI → P3) — MCP sam zdejmuje ew. `AI/Triage`; w raporcie zwraca tylko kandydatów do pamięci/kontaktów i ew. przypomnienia. **Jeśli wątek ma `Wymaga odpowiedzi` i nie czeka już na moją odpowiedź** (odpisałem merytorycznie; autoresponder się nie liczy) → dorzuć `removeLabels:["Wymaga odpowiedzi"]` (ocena semantyczna; `Wymaga działania` zostaje).
  - **Nie → klasyfikacja** wg rulebooka: **nakłada labele kategorii / tworzy drafty / ustawia status** przez `update_thread(status:"done"|"triage", …)` + `create_draft`. **Status nakładaj WYŁĄCZNIE parametrem `status`** — MCP sam robi rozłączność (`AI/Done` XOR `AI/Triage`, zdejmuje `AI/Defer/*`); nie podawaj `AI/Done`/`AI/Triage` w addLabels/removeLabels (MCP odrzuci). **Przy `status:"done"` zawsze nadaj priorytet** — `priority: P0|P1|P2|P3` (rozłączność ogarnia MCP; poziomy → sekcja „Priorytety"). MCP **wymaga** priorytetu przy każdym `AI/Done`. **Archiwizacja = `Śmieci`/`Nieaktualne`**: wątek opuszcza INBOX wyłącznie gdy dostaje marker `Śmieci` (bezpieczny do usunięcia) i/lub `Nieaktualne` (stracił aktualność, zostaw do referencji) — dodajesz go w `addLabels`, a MCP **sam zdejmuje INBOX**. Markery nakładaj **na kategorię** (np. `Zakupy`+`Śmieci`), bo są ortogonalne. Sama kategoria (np. `Zakupy`) **nie** archiwizuje — zostaje w INBOX; MCP odrzuci `removeLabels:["INBOX"]` bez markera. Gdy reguła mówi „czasowy, jeszcze aktualny" → `update_thread(deferUntil: efektywna data; brak daty → +14 dni, **priority**)`; gdy reguła mówi „już nieaktualny" → `update_thread(status:"done", addLabels:["Nieaktualne", …kategoria/Śmieci], **priority**)`. **Śmieci, Nieaktualne i defer też dostają priorytet** (zwykle P3 dla szumu).

  Wątki z **bucketu `defer-due`** (przekazane subagentowi z adnotacją) re-oceniaj wg sekcji „Defer i Nieaktualne": dalej aktualny → `update_thread(deferUntil:"NOWA data", priority)`; nieaktualny → `update_thread(status:"done", addLabels:["Nieaktualne", …], priority)` (MCP archiwizuje); wymaga akcji → obsłuż normalnie (`status:"done"`); niepewny → `status:"triage"`. Defer i archiwizacja **wymagają** priorytetu.

  **Akcje → Todoist (Wymaga działania / Wymaga odpowiedzi)** — gdy klasyfikacja daje `Wymaga działania` lub `Wymaga odpowiedzi`, wykonaj cykl z rulebooka (sekcja „Akcje → Todoist"): `add-tasks` (content = co zrobić; description = kontekst + Gmail-link; `priority` p1..p4 z mapy P0→p1…P3→p4, nie poniżej p3; `deadlineDate` jeśli twardy termin; `projectId`+`sectionId` wg konta/kategorii) → `create_label TODO/<id>` → `update_thread(addLabels:["Wymaga działania"|"Wymaga odpowiedzi","TODO/<id>","IMPORTANT"], priority)` **bez `status` i bez zdjęcia INBOX** → `update_thread(deferUntil: until, priority)` (termin → ta data clamp ≥ dziś+1; brak terminu → dziś+7). **Idempotencja**: najpierw sprawdź, czy wątek ma już `TODO/*` (z `get_thread`) lub czy istnieje task z tym threadId (`find-tasks(searchText:<threadId>)`) — jeśli tak, nie twórz drugiego, tylko dokończ defer. Tworzenie taska jest **autonomiczne** (bez pytania) — gdy mail wyraźnie wymaga działania, twórz od razu (CLAUDE.md, Safety & Permissions).

  **Re-check tasków (bucket `defer-due`)** — wątek z labelką `TODO/<id>` (odczyt `<id>` z labelek wątku) re-oceniaj wg „Akcje → Todoist": `fetch-object(type:"task", id)` (fallback `find-completed-tasks`) → COMPLETED → `update_thread(status:"done", addLabels:["Nieaktualne"], priority)` (MCP archiwizuje); OPEN → `update_thread(deferUntil:"NOWA data", priority)`; GONE (task zniknął) → `status:"triage"` + powód. Dla wątków z `TODO/*` ten re-check ma pierwszeństwo przed zwykłą re-oceną defer-due.

  **Faktury/paragony za zakupy** (Allegro i inne sklepy) → kategoria `Zakupy` + marker (model ortogonalny). **Zasada nadrzędna: wykryto fakturę/paragon → NAJPIERW przeskanuj treść, ustal ZA CO jest** (gdy nie wynika z treści maila → `save_attachment` → `Read` zapisanego PDF). Zakup towaru/usługi konsumenckiej → **`Zakupy`** — **NIGDY** `Finanse`/`Księgowość`, nawet gdy to faktura VAT / koszt firmowy / jest NIP. `Finanse`/`Księgowość` tylko dla dokumentów **NIEzakupowych** (wyciągi, ZUS/CEIDG, podatki, faktury B2B za usługi). Dopiero po „to zakup → `Zakupy`" rozstrzygnij marker:
  - **Trwałe dobro >100 zł** (sekcja „Faktury → folder Rachunki") → zwróć **kandydata do zapisu** PDF (threadId, messageId, attachmentId, dostawca, kwota, data, numer, produkt, kategoria, nazwa pliku; przy niejasności `save_attachment` → `Read` zapisanego PDF → odczyt tekstu). Zapis PDF+notatki robi główny agent (subagenci nie piszą do vault). Mail: po zapisaniu → `update_thread(status:"done", addLabels:["Zakupy","Nieaktualne"], priority)` (zostaje jako referencja, MCP archiwizuje).
  - **Konsumpcyjne / tanie drobne** (jedzenie, leki, kosmetyki, suplementy) — niezapisywane → `update_thread(status:"done", addLabels:["Zakupy","Śmieci"], priority)`.
  - **Faktury wFirma** (za usługę/subskrypcję, nie zakup) → `addLabels:["Śmieci"]`. Trwałość niejasna po PDF → `status:"triage"`.

  W obu przypadkach zwraca **uporządkowany raport** (per wątek: ścieżka, klasyfikacja, akcja, powód triażu, kandydaci na przypomnienia, kandydaci do pamięci/kontaktów, **kandydaci faktur do zapisu w Rachunki**, **utworzone taski Todoist** `TODO/<id>`). Subagent NIE pisze do vault (taski/labelki/defer robi przez MCP, ale pliki vault — nie).
- **Główny agent (ten)**: pobiera listę, dzieli na batche, odpala subagentów (**kilka wywołań `Agent` w jednej wiadomości = równolegle**; różne threadId → bezpieczne równoległe labelowanie), zbiera raporty i **sam robi wszystkie zapisy do vault** (stan, przypomnienia, pamięć).

Batch = ~5-8 wątków. Subagentowi przekaż treść rulebooka w prompcie (albo ścieżkę do odczytu) + konwencję labelek poniżej.

## Konwencja AI/Done i AI/Triage

Status nakładasz **wyłącznie** parametrem `status` w `update_thread` — nigdy ręcznie przez addLabels/removeLabels (MCP odrzuci `AI/Done`/`AI/Triage`/`AI/Defer/*` w tych polach). `AI/Done` i `AI/Triage` są **rozłączne**: MCP nakłada wybrany status, zdejmuje przeciwny **oraz** wszystkie `AI/Defer/*`. Defer to prop `deferUntil` w `update_thread`; archiwizacja (`Nieaktualne`/`Śmieci`) idzie przez `update_thread` (addLabels) — MCP sam zdejmuje INBOX. Wszystkie zmiany jednego wątku (status, defer, priorytet, labelki) idą **jednym** `update_thread`.

| `status` | Label | Kiedy |
|----------|-------|-------|
| `"done"` | `AI/Done` | Wątek w pełni obsłużony wg rulebooka **lub** wątek z najnowszą wiadomością od użytkownika (lekka ścieżka). Wymaga `priority`. |
| `"triage"` | `AI/Triage` | Reguła nie obejmuje wątku jednoznacznie LUB niepewność → zostaw w INBOX, zapisz powód. **Nigdy** dla wątków z najnowszą wiadomością od użytkownika |

Jeśli wątek był wcześniej `AI/Triage`, a teraz jest w pełni obsłużony: po prostu `update_thread(status:"done", priority: …)` — MCP sam zdejmie `AI/Triage`. `update_thread` nakłada label na wszystkie wiadomości wątku.

## Priorytety (P/0..P/3)

**Każdy przetwarzany wątek dostaje dokładnie jeden priorytet** — bez wyjątków. Dotyczy klasyfikacji, **śmieci, Nieaktualne, deferów i poczty wysłanej** (lekka ścieżka). MCP **wymusza** to twardo: każde nałożenie `AI/Done` (przez `update_thread`, też przy `deferUntil`) wymaga priorytetu, a etykiety są **rozłączne** — MCP sam zdejmuje poprzedni `P/*`. Priorytet podajesz parametrem `priority` z wartością **`P0`/`P1`/`P2`/`P3`** (MCP mapuje ją na label `P/0`…`P/3`), nie ręcznym labelem.

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

**Archiwizacja = `Śmieci`/`Nieaktualne`**: wątek opuszcza INBOX **wyłącznie** gdy dostaje jeden z tych markerów — wtedy MCP **sam zdejmuje INBOX**. Dodajesz marker w `addLabels` (`update_thread`), nie zdejmujesz INBOX ręcznie. Sama kategoria (`Zakupy`/`Newsletter`/`Finanse`…) tylko taguje i **zostawia** wątek w INBOX; MCP odrzuci `removeLabels:["INBOX"]` bez markera. Mail bez `Śmieci`/`Nieaktualne` **nigdy nie jest archiwizowany sam**. (`deferUntil` nie zdejmuje INBOX.)

## Defer i Nieaktualne (maile z datą ważności)

Część maili jest dziś OK, ale **zdezaktualizuje się w przyszłości** (event, deadline, ważność oferty), albo są **już całkowicie nieaktualne** (event minął, stara dostawa).

- **Defer** — odłożenie z **efektywną datą**. Użyj `mcp__gmail__update_thread(account, threadId, deferUntil:"<until>", priority)`. MCP nakłada `AI/Defer/<until>` + `AI/Done` (wątek znika z `unprocessed`) i zdejmuje ewentualny `AI/Triage`. Wątek **wraca dopiero gdy data minie** — przez `filter:"defer-due"`. Mail odłożony na pół roku nie jest dotykany przez pół roku.
- **Nieaktualne** — stan terminalny. Użyj `update_thread(status:"done", addLabels:["Nieaktualne", …kategoria; +"Śmieci" jeśli reguła], priority)`. MCP nakłada labelki + `AI/Done`, **sam archiwizuje** (zdejmuje INBOX), czyści `AI/Triage` i wszystkie `AI/Defer/*`.

**Defer/Nieaktualne nakładaj TYLKO gdy reguła z rulebooka to mówi.** Nie zgaduj z góry, że mail jest nieaktualny — jeśli reguła nie jest jednoznaczna → `AI/Triage` (decyzja w `/email-triage`).

**Wybór daty efektywnej** (forward path): data eventu / deadline / koniec ważności oferty z treści maila. **Gdy z maila nie wynika konkretna data → fallback +14 dni.**

**Kanoniczny przykład — przesyłki i statusy zamówień**: powiadomienie o przesyłce / statusie zamówienia (nadane, w drodze, do odbioru, tracking) → `Defer` do przewidywanej daty dostawy (brak daty → **+7 dni**) → po dojrzeniu zwykle już dostarczone → `Nieaktualne`+`Śmieci` (dostarczone i bez wartości). Wyraźnie stary mail (paczka na pewno dostarczona) → od razu `Nieaktualne`+`Śmieci`. Paragon/faktura/dokument zakupu → wg rulebooka (`Zakupy`+marker).

**Bucket `defer-due` (dojrzałe defery)** — wątki, których data efektywna właśnie minęła. Re-ocena wg rulebooka:
- dalej aktualny → `update_thread(deferUntil:"NOWA data", priority)` (**re-defer** — inaczej wątek wracałby codziennie ze starą datą);
- teraz nieaktualny → `update_thread(status:"done", addLabels:["Nieaktualne", …], priority)` (MCP archiwizuje);
- teraz wymaga akcji → obsłuż normalnie (labele kategorii / draft, `status:"done"`);
- niepewny → `status:"triage"`.

## Proces

### Faza 1: Sesja i stan

1. Przeczytaj `Asystent/Memory/InboxReviewState.md` (`Read`).
   - Status `in_progress` < 1h temu → zapytaj: "Znaleziono niedokończoną sesję (X/Y). Kontynuować czy od nowa?"
   - Brak / stary / `completed` → nowa sesja.
2. Pobierz wejście dla obu kont, policz total/batche, zainicjuj stan (format niżej). Dwa buckety:
   - **nieprzetworzone**: `search_threads(filter:"unprocessed")`;
   - **dojrzałe defery**: `search_threads(query:"in:inbox", filter:"defer-due")` — wątki, których data efektywna minęła i wracają do re-oceny (sekcja „Defer i Nieaktualne"). Pusto → pomiń.
3. Wczytaj rulebook obu kont oraz `Preferences.md`. **NIE ładuj listy kontaktów** — szukaj na żądanie przez `qmd`.

### Faza 2: Pętla batchy (subagenci Sonnet)

Dla każdego batcha:
1. Weź kolejne ~5-8 nieprzetworzonych threadId (pomiń te już w "Processed Thread IDs" tej sesji).
2. Odpal subagenta Sonnet z: konto, lista threadId, treść rulebooka, konwencja labelek. Subagent przetwarza i zwraca raport. Batche niezależnych kont/zakresów możesz puścić równolegle.
3. Zbierz raport, zaktualizuj `InboxReviewState.md` (`Edit`): dopisz threadId, liczniki, batch, findings, "Last Updated". **Powód triażu zapisuj w tabeli Priority/Triage Emails** (kolumna Action). Findings z lekkiej ścieżki (maile wysłane) trafiają do reminderów i pamięci — **nie** do tabeli Priority/Triage Emails.
4. Krótki progres: `Batch N gotowy: X wątków. Kontynuuję...`

### Faza 3: Zakończenie

1. **Przypomnienia** — dla maili wymagających follow-up dopisz do `Asystent/Memory/EmailReminders.md` (`Edit`/`Write`). Dotyczy to też maili wysłanych z lekkiej ścieżki, gdy użytkownik czeka na odpowiedź lub ma sam zrobić follow-up. Format pliku i linków Gmail: patrz CLAUDE.md (sekcja EmailReminders.md). Sugeruj daty: deadline w mailu → ta data; oczekiwana odpowiedź → +3-5 dni roboczych; czekanie na dokument → obietnica +1 dzień; okresowe → za tydzień.
2. **Faktury → Rachunki** — dla kandydatów z raportów subagentów (faktura trwałego dobra >100 zł): `save_attachment(account, messageId, attachmentId)` → zwraca `path` w `.context/attachments/<messageId>/<plik>` (plik na dysku, bez base64) → `Bash: mv "<path>" "./obsidian/Rachunki/<data ISO> <opis>.pdf"`; potem `Write` notatkę `.md` (szablon w rulebooku, sekcja „Faktury → folder Rachunki"). **Dedup** przed zapisem: `Bash: ls ./obsidian/Rachunki/` — plik o tej nazwie już jest → pomiń.
3. **Pamięć / digital twin** — skomituj zakolejkowane aktualizacje:
   - **Kontakty**: `qmd` po emailu nadawcy; dla znanych zaktualizuj `ostatni_kontakt` + dopisz wpis do `## Historia kontaktów` (data, typ Email, link Gmail). Dla nowych ważnych — utwórz profil w `./obsidian/Kontakty/`.
   - Inne: `Projects.md`, `Work.md`/`Personal.md`, `Timeline.md`, `Insights.md` — gdy maile coś ujawniły.
4. **Sfinalizuj stan**: status `completed`, wyczyść "Processed Thread IDs", zachowaj findings.
5. **Sprzątanie labelek defer**: wywołaj `cleanup_defer_labels` na obu kontach — usuwa puste `AI/Defer/<data>` (po re-deferach/oznaczeniach). Zapamiętaj licznik do podsumowania.
6. **Raport sterty triażu**: policz aktualną stertę `search_threads(query:"in:inbox", filter:"triage")` na obu kontach. Jeśli duża (≈>10), poleć: "Masz N wątków w AI/Triage — odpal `/email-triage`, żeby je rozkminić razem i poprawić reguły."
7. Podsumowanie (niżej).

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
- Odłożone (Defer): N (w tym re-defery dojrzałych) / Oznaczone Nieaktualne: M / Puste labelki defer usunięte: K
- Przypomnienia: [...]

#### Pamięć zaktualizowana
- Kontakty: [...] / Nowe kontakty: [...] / Inne: [...]

#### Sterta triażu
- AI/Triage: N wątków → (jeśli duża) poleć `/email-triage`

## Bezpieczeństwo

- **Nigdy nie wysyłaj** maili — tylko drafty (`create_draft`).
- **Nigdy nie usuwaj** maili/zadań/wydarzeń/notatek.
- **Pytaj przed** nałożeniem labela na wątek `IMPORTANT` / ważny.
- **Taski Todoist z maili akcyjnych** (`Wymaga działania`/`Wymaga odpowiedzi`) tworzy się **autonomicznie, bez pytania** — gdy mail wyraźnie wymaga działania (CLAUDE.md, Safety & Permissions). Powiązanie przez `TODO/<id>`, śledzenie cyklem defer (sekcja „Akcje → Todoist" rulebooka). Nadal **nie** modyfikujemy ani **nie ukończamy** istniejących tasków — to robi użytkownik.
- **Faktury trwałych dóbr >100 zł** zapisywane są do `./obsidian/Rachunki/` (PDF + notatka) automatycznie wg rulebooka; to zapis lokalny, niczego nie wysyła.
- **Nigdy nie blokuj**: niejasne → `AI/Triage` + powód, leć dalej.
- Każdy przetworzony wątek przychodzący dostaje `AI/Done`, `AI/Triage` albo `AI/Defer/<data>` (przez `update_thread(deferUntil)`); archiwizowane dostają dodatkowo `Nieaktualne`/`Śmieci`.
- **Każdy przetwarzany wątek dostaje priorytet** (`priority: P0..P3`) — klasyfikacja, śmieci, Nieaktualne, defer i poczta wysłana. MCP wymusza priorytet przy każdym `AI/Done` (w tym przy `deferUntil`).
- **Archiwizacja = `Śmieci`/`Nieaktualne`** — wątek opuszcza INBOX wyłącznie z tym markerem (MCP sam zdejmuje INBOX); kategoria sama tylko taguje i zostawia w INBOX; zdjęcie INBOX bez markera MCP odrzuci.
- **Defer/Nieaktualne tylko wg reguły z rulebooka** — nie zakładaj z góry, że mail jest nieaktualny; niejasne → `AI/Triage`.
- Wątki z najnowszą wiadomością od użytkownika idą lekką ścieżką: zawsze `AI/Done`, **nigdy** `AI/Triage`, bez labeli kategorii i bez draftów.
- Zapisuj stan po KAŻDYM batchu (wznawianie po przerwaniu). ThreadId = źródło prawdy postępu.
- Komunikuj po polsku.
