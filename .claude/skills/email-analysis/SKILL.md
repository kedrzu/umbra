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

## ⚠️ Podwójne opt-in (jak w /email-triage)

Każdy zapis reguły — i w trybie projektowania, i w trybie łączonym — przechodzi przez **podwójne opt-in**: (1) użytkownik mówi co zrobić, (2) agent powtarza konkretnie proponowane reguły + akcje na mailach i **czeka na wyraźne "OK"**. Feedback ≠ zgoda; agent poprawia i pyta ponownie. Nic nie ląduje w rulebooku ani na mailach bez akceptacji.

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
| Dojrzałe defery | `mcp__gmail__search_threads` (`filter:"defer-due"`) |
| Treść wątku | `mcp__gmail__get_thread` |
| Status (AI/Done\|AI/Triage) / labele / draft | `mcp__gmail__update_thread` (`status: "done"\|"triage"` dla statusu; addLabels/removeLabels dla kategorii; opcjonalny `priority: P0..P3`), `mcp__gmail__create_draft` |
| Tworzenie etykiety-kubełka | `mcp__gmail__create_label` |
| Odłożenie z datą / archiwizacja / cleanup | `mcp__gmail__defer_thread`, `mcp__gmail__update_thread` (addLabels `Nieaktualne`/`Śmieci` → MCP zdejmuje INBOX), `mcp__gmail__cleanup_defer_labels` |
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
  1. Wejście: `search_threads(query:"(in:inbox OR (in:sent newer_than:30d))", filter:"pending")` (nieukończone, **łącznie ze stertą AI/Triage**). Dodatkowo wciągnij **dojrzałe defery**: `search_threads(query:"in:inbox", filter:"defer-due")` — wątki, których data efektywna minęła, do re-oceny (sekcja „Defer i Nieaktualne").
  2. Przetwarzaj batche przez **subagentów Sonnet** (jak `/email-review`): objęte regułą maile subagent obsługuje sam (labele kategorii/draft/`status:"done"`); niepewne **tylko streszcza** i zwraca jako kandydatów do triażu. **Wątki z najnowszą wiadomością od użytkownika** (`kedrzu@gmail.com` / `kedrzu@sigma.clinic`) idą **lekką ścieżką jak w `/email-review`** (wiedza + ew. reminder, `status:"done"`, bez klasyfikacji) — nie podlegają triażowi ani nauce reguł.
  3. Niepewne rozstrzygaj interaktywnie **jak `/email-triage`**: grupuj po wzorcu → `AskUserQuestion` → **podwójne opt-in** → zapis reguły (dopisz/edytuj wiersz `| Typ | Akcja |`, bump daty) + wykonanie akcji na grupie. Po akceptacji na **każdym** obsłużonym wątku oznacz done przez `update_thread(status:"done", priority: …)` — MCP nakłada `AI/Done` i **sam zdejmuje `AI/Triage`** oraz `AI/Defer/*` (nie podawaj tych labelek ręcznie — odrzuci); sterta triażu ma realnie maleć. **Zawsze nadaj priorytet** (`priority: P0..P3`) — MCP wymaga go przy każdym `AI/Done`, więc też przy śmieciach, Nieaktualne, deferach i poczcie wysłanej (lekka ścieżka: czekam na odpowiedź/follow-up → P1, konwersacja → P2, FYI → P3). **Archiwizacja = `Śmieci`/`Nieaktualne`**: wątek opuszcza INBOX wyłącznie z markerem dodanym w `addLabels` (MCP sam zdejmuje INBOX); kategoria sama tylko taguje i zostawia w INBOX (MCP odrzuci `removeLabels:["INBOX"]` bez markera). Wśród opcji decyzji uwzględnij **Defer** (`defer_thread(until, priority)`) i **Nieaktualne/Śmieci** (`update_thread(status:"done", addLabels:["Nieaktualne"|"Śmieci", …], priority)`) — wszystkie **wymagają priorytetu** — patrz sekcja „Defer i Nieaktualne". Dojrzałe defery re-oceniaj tak samo (re-defer na nową datę / Nieaktualne±Śmieci / obsłuż / zostaw).
  4. Na koniec sesji: `cleanup_defer_labels` na koncie (usuwa puste `AI/Defer/<data>`).

## Defer i Nieaktualne (maile z datą ważności)

Dwie labelki dla maili, które tracą aktualność w czasie (jak w `/email-review` i `/email-triage`):
- **Defer** (`defer_thread(account, threadId, until, priority)`) — odłożenie z **efektywną datą**: MCP nakłada `AI/Defer/<until>` + `AI/Done` + `P/<n>`, wątek wraca dopiero gdy data minie (`filter:"defer-due"`). Data = event/deadline/ważność oferty; brak konkretnej → +14 dni. `priority` **wymagany**.
- **Nieaktualne / Śmieci** (`update_thread(status:"done", addLabels:["Nieaktualne"|"Śmieci", …kategoria], priority)`) — archiwizacja: MCP nakłada markery + `AI/Done` + `P/<n>`, **sam zdejmuje INBOX**, czyści `AI/Triage`/`AI/Defer/*`. `Nieaktualne` = stracił aktualność, zostaw do referencji; `Śmieci` = bezpieczny do usunięcia; razem = oba. `priority` **wymagany** (zwykle P3).

W **trybie projektowania** uwzględnij te labelki w proponowanym systemie i regułach (np. „newslettery eventowe → Defer do daty eventu"). Kanoniczny przykład pełnego cyklu: **przesyłki i statusy zamówień** (nadane / w drodze / do odbioru / tracking) → `Defer` do przewidywanej dostawy (brak daty → **+7 dni**) → po dojrzeniu zwykle już dostarczone → `Nieaktualne`+`Śmieci`; sam stary mail → od razu `Nieaktualne`+`Śmieci`; paragon/faktura za zakup → `Zakupy`+marker (zapisany do Obsidian → `Nieaktualne`, konsumpcyjny → `Śmieci`). Słownik akcji w regułach: `Defer:<efektywna data>`, `Nieaktualne [+ Śmieci] + archiwizuj`, `Śmieci + archiwizuj`. **Defer/Nieaktualne/Śmieci tylko wg reguły** — nie zakładaj nieaktualności z góry; niejasne → triaż.

## Akcje → Todoist i Faktury → Rachunki (przez opt-in)

Jak w `/email-review`, ale **przez podwójne opt-in**:
- **Akcje → Todoist** (rulebook „Akcje → Todoist"): maile `Wymaga działania`/`Wymaga odpowiedzi` → task Todoist (projekt/sekcja wg konta, priorytet, ew. termin) + `TODO/<id>` + defer; re-check dojrzałych deferów z `TODO/<id>` (COMPLETED → `update_thread(status:"done", addLabels:["Nieaktualne"], priority)`; OPEN → re-defer; GONE → triaż). W **trybie projektowania** uwzględnij `TODO/<id>` w proponowanym systemie labelek.
- **Faktury → Rachunki** (rulebook „Faktury → folder Rachunki"): faktura trwałego dobra >100 zł → zapis PDF + notatki do `./obsidian/Rachunki/`.

Propozycje i wykonanie zawsze po wyraźnej zgodzie użytkownika.

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

- **Podwójne opt-in** na każdy zapis reguły i akcję. Feedback ≠ zgoda.
- **Nigdy nie wysyłaj** maili — tylko drafty. **Nigdy nie usuwaj.**
- Po obsłużeniu wątku z triażu zawsze `update_thread(status:"done", …)` (MCP zdejmie `AI/Triage`). Status `AI/Done`/`AI/Triage` ustawiasz wyłącznie parametrem `status` — nigdy ręcznie. Maile wysłane → lekka ścieżka, nigdy `AI/Triage`.
- **Każdy przetwarzany wątek dostaje priorytet** (`P/0..P/3`) — klasyfikacja, śmieci, Nieaktualne, defer i poczta wysłana. MCP wymusza priorytet przy każdym `AI/Done` (`update_thread`/`defer_thread`). **Archiwizacja = `Śmieci`/`Nieaktualne`** — wątek opuszcza INBOX wyłącznie z tym markerem (MCP sam zdejmuje INBOX); kategoria sama tylko taguje; zdjęcie INBOX bez markera MCP odrzuci.
- Bądź interaktywny — pytaj o preferencje, nie narzucaj rozwiązań.
- To proces iteracyjny, nie jednorazowy.
- Komunikuj po polsku.
