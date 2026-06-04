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
| Treść wątku | `mcp__gmail__get_thread` |
| Draft (nie wysyła) | `mcp__gmail__create_draft` |
| Labele wątku | `mcp__gmail__update_thread` (addLabels/removeLabels, po NAZWACH) |
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
3. **Status** — nałóż `AI/Done`. Jeśli wątek miał `AI/Triage` — zdejmij go. **Nie** nakładaj labeli kategorii, **nie** twórz draftów, **nigdy** `AI/Triage`.

Wątki, w których najnowsza wiadomość jest **przychodząca**, idą normalną ścieżką klasyfikacji (niżej).

## Model wykonania: subagenci na Sonnecie

Główny agent (ten) **orkiestruje**; ciężką pracę per batch zlecaj **subagentom na Sonnecie** (`Agent`, `model: "sonnet"`, `subagent_type: "general-purpose"`). Każdy batch dostaje świeży kontekst i tańszy model.

**Podział odpowiedzialności:**
- **Subagent (Sonnet)** dla batcha (lista threadId + konto + adresy użytkownika + treść rulebooka): czyta wątki (`get_thread`) i dla każdego **najpierw sprawdza, czy najnowsza wiadomość jest od użytkownika** (`kedrzu@gmail.com` / `kedrzu@sigma.clinic`):
  - **Tak → lekka ścieżka** (sekcja „Maile wysłane"): bez klasyfikacji, bez labeli kategorii, bez draftów; nakłada `AI/Done`, zdejmuje ew. `AI/Triage`; w raporcie zwraca tylko kandydatów do pamięci/kontaktów i ew. przypomnienia.
  - **Nie → klasyfikacja** wg rulebooka: **nakłada labele / tworzy drafty / ustawia `AI/Done` lub `AI/Triage`** (`update_thread`, `create_draft`).

  W obu przypadkach zwraca **uporządkowany raport** (per wątek: ścieżka, klasyfikacja, akcja, powód triażu, kandydaci na przypomnienia, kandydaci do pamięci/kontaktów). Subagent NIE pisze do vault.
- **Główny agent (ten)**: pobiera listę, dzieli na batche, odpala subagentów (**kilka wywołań `Agent` w jednej wiadomości = równolegle**; różne threadId → bezpieczne równoległe labelowanie), zbiera raporty i **sam robi wszystkie zapisy do vault** (stan, przypomnienia, pamięć).

Batch = ~5-8 wątków. Subagentowi przekaż treść rulebooka w prompcie (albo ścieżkę do odczytu) + konwencję labelek poniżej.

## Konwencja AI/Done i AI/Triage

| Label | Kiedy |
|-------|-------|
| `AI/Done` | Wątek w pełni obsłużony wg rulebooka **lub** wątek z najnowszą wiadomością od użytkownika (lekka ścieżka — bez klasyfikacji) |
| `AI/Triage` | Reguła nie obejmuje wątku jednoznacznie LUB niepewność → zostaw w INBOX, zapisz powód. **Nigdy** dla wątków z najnowszą wiadomością od użytkownika |

Jeśli wątek był wcześniej `AI/Triage`, a teraz jest w pełni obsłużony: usuń `AI/Triage`, dodaj `AI/Done` (`removeLabels`/`addLabels`). `update_thread` nakłada label na wszystkie wiadomości wątku.

## Proces

### Faza 1: Sesja i stan

1. Przeczytaj `Asystent/Memory/InboxReviewState.md` (`Read`).
   - Status `in_progress` < 1h temu → zapytaj: "Znaleziono niedokończoną sesję (X/Y). Kontynuować czy od nowa?"
   - Brak / stary / `completed` → nowa sesja.
2. Pobierz wejście (`search_threads` z `filter:"unprocessed"`) dla obu kont, policz total/batche, zainicjuj stan (format niżej).
3. Wczytaj rulebook obu kont oraz `Preferences.md`. **NIE ładuj listy kontaktów** — szukaj na żądanie przez `qmd`.

### Faza 2: Pętla batchy (subagenci Sonnet)

Dla każdego batcha:
1. Weź kolejne ~5-8 nieprzetworzonych threadId (pomiń te już w "Processed Thread IDs" tej sesji).
2. Odpal subagenta Sonnet z: konto, lista threadId, treść rulebooka, konwencja labelek. Subagent przetwarza i zwraca raport. Batche niezależnych kont/zakresów możesz puścić równolegle.
3. Zbierz raport, zaktualizuj `InboxReviewState.md` (`Edit`): dopisz threadId, liczniki, batch, findings, "Last Updated". **Powód triażu zapisuj w tabeli Priority/Triage Emails** (kolumna Action). Findings z lekkiej ścieżki (maile wysłane) trafiają do reminderów i pamięci — **nie** do tabeli Priority/Triage Emails.
4. Krótki progres: `Batch N gotowy: X wątków. Kontynuuję...`

### Faza 3: Zakończenie

1. **Przypomnienia** — dla maili wymagających follow-up dopisz do `Asystent/Memory/EmailReminders.md` (`Edit`/`Write`). Dotyczy to też maili wysłanych z lekkiej ścieżki, gdy użytkownik czeka na odpowiedź lub ma sam zrobić follow-up. Format pliku i linków Gmail: patrz CLAUDE.md (sekcja EmailReminders.md). Sugeruj daty: deadline w mailu → ta data; oczekiwana odpowiedź → +3-5 dni roboczych; czekanie na dokument → obietnica +1 dzień; okresowe → za tydzień.
2. **Pamięć / digital twin** — skomituj zakolejkowane aktualizacje:
   - **Kontakty**: `qmd` po emailu nadawcy; dla znanych zaktualizuj `ostatni_kontakt` + dopisz wpis do `## Historia kontaktów` (data, typ Email, link Gmail). Dla nowych ważnych — utwórz profil w `./obsidian/Kontakty/`.
   - Inne: `Projects.md`, `Work.md`/`Personal.md`, `Timeline.md`, `Insights.md` — gdy maile coś ujawniły.
3. **Sfinalizuj stan**: status `completed`, wyczyść "Processed Thread IDs", zachowaj findings.
4. **Raport sterty triażu**: policz aktualną stertę `search_threads(query:"in:inbox", filter:"triage")` na obu kontach. Jeśli duża (≈>10), poleć: "Masz N wątków w AI/Triage — odpal `/email-triage`, żeby je rozkminić razem i poprawić reguły."
5. Podsumowanie (niżej).

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
- Przypomnienia: [...]

#### Pamięć zaktualizowana
- Kontakty: [...] / Nowe kontakty: [...] / Inne: [...]

#### Sterta triażu
- AI/Triage: N wątków → (jeśli duża) poleć `/email-triage`

## Bezpieczeństwo

- **Nigdy nie wysyłaj** maili — tylko drafty (`create_draft`).
- **Nigdy nie usuwaj** maili/zadań/wydarzeń/notatek.
- **Pytaj przed** nałożeniem labela na wątek `IMPORTANT` / ważny.
- **Nigdy nie blokuj**: niejasne → `AI/Triage` + powód, leć dalej.
- Każdy przetworzony wątek przychodzący dostaje `AI/Done` albo `AI/Triage`.
- Wątki z najnowszą wiadomością od użytkownika idą lekką ścieżką: zawsze `AI/Done`, **nigdy** `AI/Triage`, bez labeli kategorii i bez draftów.
- Zapisuj stan po KAŻDYM batchu (wznawianie po przerwaniu). ThreadId = źródło prawdy postępu.
- Komunikuj po polsku.
