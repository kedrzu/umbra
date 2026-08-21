---
name: email-analysis
description: Kompleksowy przebieg po skrzynce, który JEDNOCZEŚNIE przetwarza maile (jak /email-review) i interaktywnie triażuje oraz uczy się nowych reguł (jak /email-triage), albo - dla nowego/pustego konta - od zera projektuje system labelek i reguł. Użyj na głęboką sesję mailową, do ustawienia reguł dla konta od podstaw, do dużego nadrobienia połączonego z nauką, albo gdy reguł praktycznie jeszcze nie ma. NIE do codziennego szybkiego nadrabiania (to /email-review) ani do samego rozkminiania istniejącej sterty AI/Triage (to /email-triage).
---

# Email Analysis

Najcięższe z trójki narzędzi mailowych. Robi **dwie rzeczy naraz**: przetwarza wszystko, co nieukończone, i **na bieżąco** triażuje oraz uczy reguł te maile, których rulebook jeszcze nie obejmuje. Dla konta bez reguł (np. Work) przełącza się w tryb projektowania systemu od zera.

Relacja do pozostałych:
- przetwarzanie maili objętych regułami → dokładnie jak **`/email-review`**,
- interaktywne rozstrzyganie niepewnych + zapis reguł → dokładnie jak **`/email-triage`** (w tym **podwójne opt-in**).

Ten skill tylko **orkiestruje** te dwa zachowania w jednym przebiegu i dokłada tryb cold-start.

## ⚠️ Podwójne opt-in — TYLKO na zmianę reguły (jak w /email-triage)

Opt-in dotyczy **wyłącznie zapisu/edycji reguły** rulebooka (i w trybie projektowania — całego proponowanego systemu labelek/reguł): (1) użytkownik mówi co zrobić, (2) agent powtarza konkretnie proponowane reguły i **czeka na wyraźne "OK"**. Feedback ≠ zgoda; agent poprawia i pyta ponownie. **Akcje na mailach/taskach wg istniejących reguł są autonomiczne** — labele, zadania, odkładanie, archiwizacja, programowe sprawdzenie stanu zadań (`todoist.py sync`) — bez pytania o każdy mail. Reguły nie lądują w rulebooku bez akceptacji; akcje wg istniejących reguł — owszem.

## Konta i rulebook

| Konto | Email | Rulebook |
|-------|-------|----------|
| Personal | kedrzu@gmail.com | `./obsidian/Asystent/Memory/EmailWorkflow-Personal.md` |
| Work | kedrzu@sigma.clinic | `./obsidian/Asystent/Memory/EmailWorkflow-Work.md` |

**Analizuj konta osobno** — workflow personal i work są zupełnie różne.

## Narzędzia

| Operacja | Narzędzie |
|----------|-----------|
| Pobranie wątków | `mcp__gmail__search_threads` (`filter:"pending"`) |
| Dojrzałe sprawy | `Bash(python3 scripts/ledger.py due …)` — rejestr, kontrakt w `docs/ledger.md` |
| Treść wątku (labelki jako nazwy) | `mcp__gmail__get_thread` |
| Wyszukiwanie referencyjne (cała poczta) | `mcp__gmail__search_threads` **bez** `filter` (inbox + archiwum + `AI/Done`) |
| Status (AI/Done\|AI/Triage) / labele / draft | `mcp__gmail__update_thread` (`status: "done"\|"triage"` dla statusu; addLabels/removeLabels dla kategorii; opcjonalny `priority: P0..P3`), `mcp__gmail__create_draft` |
| Tworzenie etykiety-kubełka | `mcp__gmail__create_label` |
| Odłożenie z datą / archiwizacja | `mcp__gmail__update_thread` (`status:"done"`, `priority`; addLabels `Nieaktualne`/`Śmieci` → MCP zdejmuje INBOX) + rekord w rejestrze (`ledger upsert`/`close`) |
| Pytania do użytkownika | `AskUserQuestion` |
| Czytanie/zapis vault | `Read`, `Edit`, `Write` |
| Szukanie kontaktów | `qmd` (MCP) |
| Batch w subagencie | `Agent` (`model: "sonnet"`) |

## Wybór trybu (wg dojrzałości rulebooka)

Na start przeczytaj rulebook konta. Następnie:

- **Tryb projektowania (cold-start)** — gdy rulebook jest pusty / "Do zdefiniowania" / ma znikomo reguł (np. Work):
  1. Pobierz próbkę (`search_threads`, różne `query`: `in:inbox`, `is:sent`, `is:important`; ~100-200 wątków). Streszczanie próbki możesz zlecić subagentom Sonnet.
  2. Zgrupuj nadawców i typy, pokaż statystyki (top nadawcy, kategorie, wzorce czasowe).
  3. Zaproponuj **wstępny system labelek + tabelę reguł** dla tego konta. **Zawsze** włącz priorytety `P/0..P/3` (P0 krytyczny → P3 szum; sekcja „Priorytety" rulebooka), dwa markery cyklu życia **`Nieaktualne`** (stracił aktualność, zostaw do referencji) i **`Śmieci`** (bezpieczny do usunięcia) oraz zasadę **„archiwizacja = `Śmieci`/`Nieaktualne`"** — wątek opuszcza INBOX wyłącznie z którymś z tych markerów (kategoria sama tylko taguje, zostaje w INBOX), a reguła klasyfikująca wątek przychodzący wskazuje priorytet.
  4. Zapis tabeli reguł → przez **podwójne opt-in**. Potem możesz przejść do trybu łączonego, żeby zobaczyć reguły w akcji.

- **Tryb łączony** — gdy rulebook jest dojrzały (np. Personal):
  1. Wejście: `search_threads(query:"(in:inbox OR (in:sent newer_than:30d))", filter:"pending")` (nieukończone, **łącznie ze stertą AI/Triage**). Dodatkowo wciągnij **dojrzałe sprawy**: `python3 scripts/ledger.py due --select id,title,due,reason,refs` — sprawy, których data powrotu minęła, do re-oceny (sekcja „Odkładanie i Nieaktualne").
  2. Przetwarzaj batche przez **subagentów Sonnet** (jak `/email-review`): objęte regułą maile subagent obsługuje sam (labele kategorii/draft/`status:"done"`); niepewne **tylko streszcza** i zwraca jako kandydatów do triażu. **Wątki z najnowszą wiadomością od użytkownika** (`kedrzu@gmail.com` / `kedrzu@sigma.clinic`) idą **lekką ścieżką jak w `/email-review`** (wiedza + ew. reminder, `status:"done"`, bez klasyfikacji) — nie podlegają triażowi ani nauce reguł.
  3. **Niepewne = maile bez reguły** rozstrzygaj interaktywnie **jak `/email-triage`**, ale opt-in dotyczy **tylko reguły**: grupuj po wzorcu → `AskUserQuestion` → **podwójne opt-in na regułę** → zapis reguły (dopisz/edytuj wiersz `| Typ | Akcja |`, bump daty) + wykonanie akcji na grupie. Wątki **pasujące do istniejącej reguły** subagent obsłużył już autonomicznie w kroku 2 — nie wracają tu do pytania. Nie pytaj o każdy mail „czy załatwione" — stan zadań ustalaj programowo (`python3 scripts/todoist.py sync` → `completed`/`stale_links`); komentarze i zmiany przy ukończonych zadaniach przerabiaj na wiedzę jak w `/email-review` (sekcja „Żniwo wiedzy z ukończonych zadań”). Po akceptacji na **każdym** obsłużonym wątku oznacz done przez `update_thread(status:"done", priority: …)` — MCP nakłada `AI/Done` i **sam zdejmuje `AI/Triage`** (nie podawaj tych labelek ręcznie — odrzuci); sterta triażu ma realnie maleć. **Zawsze nadaj priorytet** (`priority: P0..P3`) — MCP wymaga go przy każdym `AI/Done`, więc też przy śmieciach, Nieaktualne, odłożonych i poczcie wysłanej (lekka ścieżka: czekam na odpowiedź/follow-up → P1, konwersacja → P2, FYI → P3). **Archiwizacja = `Śmieci`/`Nieaktualne`**: wątek opuszcza INBOX wyłącznie z markerem dodanym w `addLabels` (MCP sam zdejmuje INBOX); kategoria sama tylko taguje i zostawia w INBOX (MCP odrzuci `removeLabels:["INBOX"]` bez markera). Wśród opcji decyzji uwzględnij **Odłóż** (`update_thread(status:"done", priority)` + rekord w rejestrze z `due`/`reason`) i **Nieaktualne/Śmieci** (`update_thread(status:"done", addLabels:["Nieaktualne"|"Śmieci", …], priority)`) — wszystkie **wymagają priorytetu** — patrz sekcja „Odkładanie i Nieaktualne". Dojrzałe sprawy re-oceniaj tak samo (nowa data / Nieaktualne±Śmieci / obsłuż / zostaw).
  4. Na koniec sesji: `python3 scripts/ledger.py validate` — ostrzeżenia o tym samym wątku/zadaniu w kilku sprawach oznaczają duplikat do scalenia.

## Odkładanie i Nieaktualne (maile z datą ważności)

Dwie ścieżki dla maili, które tracą aktualność w czasie (jak w `/email-review` i `/email-triage`):
- **Odłożenie** (`update_thread(status:"done", priority)` + rekord w rejestrze) — wątek znika z `unprocessed`, **zostaje w INBOX**, a data powrotu i `reason` żyją w rejestrze; wraca dopiero gdy data minie (`ledger due`). Data = event/deadline/ważność oferty; brak konkretnej → +14 dni. `priority` **wymagany**.
- **Nieaktualne / Śmieci** (`update_thread(status:"done", addLabels:["Nieaktualne"|"Śmieci", …kategoria], priority)`) — archiwizacja: MCP nakłada markery + `AI/Done` + `P/<n>`, **sam zdejmuje INBOX**, czyści `AI/Triage`. `Nieaktualne` = stracił aktualność, zostaw do referencji; `Śmieci` = bezpieczny do usunięcia; razem = oba. `priority` **wymagany** (zwykle P3). Wątek miał rekord → `ledger close --outcome obsolete`.

W **trybie projektowania** uwzględnij te ścieżki w proponowanym systemie i regułach (np. „newslettery eventowe → odłóż do daty eventu"). Kanoniczny przykład pełnego cyklu: **przesyłki i statusy zamówień** (nadane / w drodze / do odbioru / tracking) → odłóż do przewidywanej dostawy (brak daty → **+7 dni**) → po dojrzeniu zwykle już dostarczone → `Nieaktualne`+`Śmieci`; sam stary mail → od razu `Nieaktualne`+`Śmieci`; paragon/faktura za zakup → `Zakupy`+marker (zapisany do Obsidian → `Nieaktualne`, konsumpcyjny → `Śmieci`). Słownik akcji w regułach: `Odłóż:<efektywna data>`, `Nieaktualne [+ Śmieci] + archiwizuj`, `Śmieci + archiwizuj`. **Odkładanie/Nieaktualne/Śmieci tylko wg reguły** — nie zakładaj nieaktualności z góry; niejasne → triaż.

## Akcje i Faktury → Rachunki (autonomicznie wg reguł)

Jak w `/email-review` i **tak samo autonomiczne** — gdy wątek pasuje do reguły, wykonaj od razu, bez pytania. Mechanika akcji **zależy od konta**: Personal → task Todoist; Work → tylko marker `Wymaga …` (bez tasków):
- **Brama adresatów** (rulebook „Adresaci — czy akcja jest moja?", rygor głównie na Work): przed akcją oceń pozycję w `to`/`cc`, imienne zaadresowanie i przynależność akcji do mojej domeny vs kolegi. Jasno cudza → bez akcji; niejasna → `AI/Triage`; jasno moja → obsłuż wg konta niżej.
- **Akcje — zależnie od konta** (rulebook, sekcja „Akcje"): maile `Wymaga działania`/`Wymaga odpowiedzi`, **których akcja jest moja**:
  - **Personal** (rulebook „Akcje → Todoist") → **autonomicznie**, po deduplikacji: `ledger query --ref <threadId>` + `ledger find "<podmiot/numer/kwota>"`. Znana sprawa z otwartym zadaniem → **bez nowego zadania**, tylko `todoist.py reschedule`/`update`/`comment` i dopięcie wątku do rekordu; nowa sprawa → `ledger upsert` (rekord), potem `todoist.py add --case <klucz>` (projekt/sekcja wg kategorii, priorytet, ew. termin). Stan zadań: `todoist.py sync` (COMPLETED → `update_thread(status:"done", addLabels:["Nieaktualne"], priority)` + `ledger close`; otwarte → nowe `due`; usunięte → triaż). W **trybie projektowania** **nie** proponuj labelek wiążących mail z zadaniem — od tego jest rejestr.
  - **Work** (rulebook „Akcje → markery Wymaga (BEZ tasków)") → **BEZ taska**: `update_thread(status:"done", addLabels:[<kategoria>,"Wymaga działania"|"Wymaga odpowiedzi","IMPORTANT"], priority)`. Marker do ręcznej obsługi; wraca do pipeline'u przy nowej wiadomości. W **trybie projektowania** dla konta Work **nie** proponuj integracji zadań.
- **Faktury → Rachunki** (rulebook „Faktury → folder Rachunki"): o kategorii i trwałości decydują **pozycje z załącznika, nie nadawca/temat/treść maila**. Faktura/paragon z załącznikiem → **otwórz PDF (`save_attachment`→`Read`) i ustal produkt PRZED kategorią** (subagent klasyfikujący fakturę otwiera PDF sam, nie zgaduje ze snippeta) — zwłaszcza gdy nadawca/temat „przesądzają" kategorię; brak załącznika → treść, dalej niejasne → triaż. Zakup → `Zakupy` (nie `Finanse`/`Księgowość`, nawet z NIP/VAT/kosztem firmowym; sam „usługowy" wygląd nadawcy nie wystarcza); trwałe dobro >100 zł → **autonomicznie** zapis PDF + notatki do `./obsidian/Rachunki/`.

Wyraźnej zgody (podwójny opt-in) wymaga **tylko zapis nowej/zmienionej reguły** — nie akcje wg reguł już istniejących.

## Model wykonania

Główny agent orkiestruje + prowadzi interakcję (`AskUserQuestion`, podwójne opt-in) i robi **wszystkie zapisy do vault**. Ciężkie czytanie/klasyfikację/streszczanie batchy zleca **subagentom na Sonnecie** (`Agent`, `model:"sonnet"`). Subagenci nie pytają użytkownika i nie piszą reguł — to robi główny agent.

## Format wyjścia

### Analiza konta: [Personal/Work] — tryb: [projektowanie/łączony]
- **Statystyki** (próbka): liczba maili, top nadawcy, kategorie, wzorce.
- **Przetworzone**: ile wątków, ile `AI/Done`, ile rozstrzygnięto interaktywnie, ile lekką ścieżką (wysłane).
- **Nowe/zmienione reguły**: lista (Typ → Akcja).
- **Akcje na mailach**: labele/drafty/archiwizacje, priorytety (P0/P1/P2/P3), ile `AI/Triage` → `AI/Done` (zdjęty triage), ile Defer / Nieaktualne, ile pustych labelek defer usuniętych.
- **Pozostało w triażu**: ile zostało w `AI/Triage` (tylko świadomie odłożone).
- **Pytania do użytkownika**: otwarte kwestie.

## Bezpieczeństwo

- **Luka kontekstowa** (protokół CLAUDE.md „Luki kontekstowe"): nadawca / organizacja / wewnętrzny termin / dokument, który **zmienia klasyfikację lub akcję**, a jest nieczytelny nawet po obejrzeniu maila i PDF oraz research w vault (qmd/Read digital twina) → **dopytaj użytkownika w trakcie sesji** i **utrwal** (osoba → `Kontakty/`, kontekst zawodowy → `Work.md`, reszta → `Insights.md`). To **inna rzecz niż podwójne opt-in na regułę**: tu **rozumiesz świat**, żeby dobrze sklasyfikować; tam **zmieniasz rulebook**. Rozumienie kontekstu nie wymaga opt-in.
- **Podwójne opt-in TYLKO na zapis reguły** (w trybie projektowania — całego systemu reguł). Akcje na mailach/taskach wg istniejących reguł są autonomiczne — nie pytaj o każdy mail „czy załatwione". Feedback ≠ zgoda (dla reguł).
- **Nigdy nie wysyłaj** maili — tylko drafty. **Nigdy nie usuwaj**; nie modyfikuj ani nie ukańczaj istniejących tasków.
- Po obsłużeniu wątku z triażu zawsze `update_thread(status:"done", …)` (MCP zdejmie `AI/Triage`). Status `AI/Done`/`AI/Triage` ustawiasz wyłącznie parametrem `status` — nigdy ręcznie. Maile wysłane → lekka ścieżka, nigdy `AI/Triage`.
- **Każdy przetwarzany wątek dostaje priorytet** (`P/0..P/3`) — klasyfikacja, śmieci, Nieaktualne, odłożone i poczta wysłana. MCP wymusza priorytet przy każdym `AI/Done`. **Archiwizacja = `Śmieci`/`Nieaktualne`** — wątek opuszcza INBOX wyłącznie z tym markerem (MCP sam zdejmuje INBOX); kategoria sama tylko taguje; zdjęcie INBOX bez markera MCP odrzuci.
- Bądź interaktywny — pytaj o preferencje, nie narzucaj rozwiązań.
- To proces iteracyjny, nie jednorazowy.
- Komunikuj po polsku.
