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
| Labele / draft | `mcp__gmail__update_thread` (opcjonalny `priority: P0..P3`), `mcp__gmail__create_draft` |
| Tworzenie etykiety-kubełka | `mcp__gmail__create_label` |
| Odłożenie z datą / nieaktualne / cleanup | `mcp__gmail__defer_thread`, `mcp__gmail__mark_outdated`, `mcp__gmail__cleanup_defer_labels` |
| Pytania do użytkownika | `AskUserQuestion` |
| Czytanie/zapis vault | `Read`, `Edit`, `Write` |
| Szukanie kontaktów | `qmd` (MCP) |
| Batch w subagencie | `Agent` (`model: "sonnet"`) |

## Wybór trybu (wg dojrzałości rulebooka)

Na start przeczytaj rulebook konta. Następnie:

- **Tryb projektowania (cold-start)** — gdy rulebook jest pusty / "Do zdefiniowania" / ma znikomo reguł (np. Work):
  1. Pobierz próbkę (`search_threads`, różne `query`: `in:inbox`, `is:sent`, `is:important`; ~100-200 wątków). Streszczanie próbki możesz zlecić subagentom Sonnet.
  2. Zgrupuj nadawców i typy, pokaż statystyki (top nadawcy, kategorie, wzorce czasowe).
  3. Zaproponuj **wstępny system labelek + tabelę reguł** dla tego konta. **Zawsze** włącz priorytety `Priorytet/P0..P3` (P0 krytyczny → P3 szum; sekcja „Priorytety" rulebooka) i zasadę **„archiwizacja tylko z kubełkiem"** — każda reguła zdejmująca INBOX musi wskazywać etykietę użytkownika (nie sam `CATEGORY_*`), a reguła klasyfikująca wątek przychodzący — priorytet.
  4. Zapis tabeli reguł → przez **podwójne opt-in**. Potem możesz przejść do trybu łączonego, żeby zobaczyć reguły w akcji.

- **Tryb łączony** — gdy rulebook jest dojrzały (np. Personal):
  1. Wejście: `search_threads(query:"(in:inbox OR (in:sent newer_than:30d))", filter:"pending")` (nieukończone, **łącznie ze stertą AI/Triage**). Dodatkowo wciągnij **dojrzałe defery**: `search_threads(query:"in:inbox", filter:"defer-due")` — wątki, których data efektywna minęła, do re-oceny (sekcja „Defer i Nieaktualne").
  2. Przetwarzaj batche przez **subagentów Sonnet** (jak `/email-review`): objęte regułą maile subagent obsługuje sam (labele/draft/`AI/Done`); niepewne **tylko streszcza** i zwraca jako kandydatów do triażu. **Wątki z najnowszą wiadomością od użytkownika** (`kedrzu@gmail.com` / `kedrzu@sigma.clinic`) idą **lekką ścieżką jak w `/email-review`** (wiedza + ew. reminder, `AI/Done`, bez klasyfikacji) — nie podlegają triażowi ani nauce reguł.
  3. Niepewne rozstrzygaj interaktywnie **jak `/email-triage`**: grupuj po wzorcu → `AskUserQuestion` → **podwójne opt-in** → zapis reguły (dopisz/edytuj wiersz `| Typ | Akcja |`, bump daty) + wykonanie akcji na grupie. Po akceptacji na **każdym** obsłużonym wątku **zdejmij `AI/Triage` i nałóż `AI/Done`** (`removeLabels:["AI/Triage"]`, `addLabels:["AI/Done"]`) — sterta triażu ma realnie maleć. **Zawsze nadaj priorytet** (`priority: P0..P3`) — MCP wymaga go przy każdym `AI/Done`, więc też przy śmieciach, Nieaktualne, deferach i poczcie wysłanej (lekka ścieżka: czekam na odpowiedź/follow-up → P1, konwersacja → P2, FYI → P3). **Archiwizując zawsze dołóż etykietę-kubełek** (`create_label`, gdy żadna nie pasuje — MCP odrzuci zdjęcie INBOX bez kubełka). Wśród opcji decyzji uwzględnij **Defer** (`defer_thread(until, priority)`) i **Nieaktualne** (`mark_outdated(priority)`) — oba **wymagają priorytetu** — patrz sekcja „Defer i Nieaktualne". Dojrzałe defery re-oceniaj tak samo (re-defer na nową datę / Nieaktualne / obsłuż / zostaw).
  4. Na koniec sesji: `cleanup_defer_labels` na koncie (usuwa puste `AI/Defer/<data>`).

## Defer i Nieaktualne (maile z datą ważności)

Dwie labelki dla maili, które tracą aktualność w czasie (jak w `/email-review` i `/email-triage`):
- **Defer** (`defer_thread(account, threadId, until, priority)`) — odłożenie z **efektywną datą**: MCP nakłada `AI/Defer/<until>` + `AI/Done` + `Priorytet/<P>`, wątek wraca dopiero gdy data minie (`filter:"defer-due"`). Data = event/deadline/ważność oferty; brak konkretnej → +14 dni. `priority` **wymagany**.
- **Nieaktualne** (`mark_outdated(account, threadId, priority)`) — stan terminalny: `Nieaktualne` + `AI/Done` + `Priorytet/<P>` + archiwum, czyści `AI/Triage`/`AI/Defer/*`. `priority` **wymagany** (zwykle P3).

W **trybie projektowania** uwzględnij te labelki w proponowanym systemie i regułach (np. „newslettery eventowe → Defer do daty eventu"). Kanoniczny przykład pełnego cyklu: **przesyłki i statusy zamówień** (nadane / w drodze / do odbioru / tracking) → `Defer` do przewidywanej dostawy (brak daty → **+7 dni**) → po dojrzeniu zwykle już dostarczone → `Nieaktualne`; sam stary mail → od razu `Nieaktualne`; paragon/faktura → zachowaj. Słownik akcji w regułach: `Defer:<efektywna data>` i `Nieaktualne + archiwizuj`. **Defer/Nieaktualne tylko wg reguły** — nie zakładaj nieaktualności z góry; niejasne → triaż.

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
- Po obsłużeniu wątku z triażu zawsze zdejmij `AI/Triage` i nałóż `AI/Done`. Maile wysłane → lekka ścieżka, nigdy `AI/Triage`.
- **Każdy przetwarzany wątek dostaje priorytet** (`Priorytet/P0..P3`) — klasyfikacja, śmieci, Nieaktualne, defer i poczta wysłana. MCP wymusza priorytet przy każdym `AI/Done` (`update_thread`/`defer_thread`/`mark_outdated`). **Archiwizacja zawsze z kubełkiem** użytkownika (MCP blokuje zdjęcie INBOX bez niej; `CATEGORY_*` to nie kubełek).
- Bądź interaktywny — pytaj o preferencje, nie narzucaj rozwiązań.
- To proces iteracyjny, nie jednorazowy.
- Komunikuj po polsku.
