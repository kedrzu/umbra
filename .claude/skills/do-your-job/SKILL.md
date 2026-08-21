---
name: do-your-job
description: Run the full assistant routine. Processes the inbox first, then generates the daily dashboard, checks tasks, and provides comprehensive daily assistance. The "magic button" for full assistant mode.
---

# Full Assistant Routine

Run the complete assistant workflow.

## Vault Obsidian

**WAŻNE**: Wszystkie pliki pamięci i kontaktów są w vault Obsidian (`./obsidian/`), NIE w lokalnym folderze projektu!

Foldery w vault:
- `./obsidian/Kontakty/` - profile osób (frontmatter YAML dla Obsidian Bases)
- `./obsidian/Asystent/Memory/` - pamięć systemowa
- `./obsidian/Inbox/` - dashboardy (np. `./obsidian/Inbox/Dashboard-YYYY-MM-DD.md`)

## Tryb nienadzorowany (ZAWSZE)

Ta rutyna **nigdy nie zadaje pytań i nigdy nie czeka na odpowiedź** - także gdy odpalasz ją ręcznie. Powód: głównym trybem uruchomienia jest harmonogram (Paseo, 8:00 pon-pt, `./setup-morning-routine.sh`), gdzie nie ma nikogo po drugiej stronie, a agent zatrzymany na pytaniu = **failed run bez powiadomienia**.

Zasady:
- **Zero pytań w trakcie i na końcu.** Wszystko, co wymagałoby decyzji użytkownika, ląduje w sekcji **„Do decyzji"** dzisiejszego Dashboardu (i w podsumowaniu).
- **Argument `unattended`** jest akceptowany (tak odpala harmonogram) i nic nie zmienia - to zachowanie domyślne.
- **Luka kontekstowa nie blokuje**: mail → `AI/Triage` z zapisanym powodem (rozstrzygnie `/email-triage`); wszystko inne → „Do decyzji" + zapis tego, co już wiadomo, do pamięci.
- **Co robisz autonomicznie**: zadania Todoist wg reguł CLAUDE.md/rulebooków — **tworzenie nowych oraz aktualizowanie istniejących** (termin, priorytet, treść, komentarz), gdy przychodzi kolejny mail w tej samej sprawie; labelki i statusy maili wg rulebooka; drafty; zapisy do vault (`Asystent/`, `Kontakty/`, `Inbox/`, `Rachunki/`); prowadzenie rejestru spraw (`scripts/ledger.py`) i zamykanie spraw przy jednoznacznym dowodzie.
- **Czego NIE robisz nigdy**: nie tworzysz wydarzeń kalendarza (CLAUDE.md #6) - propozycja terminu idzie do „Do decyzji"; nie wysyłasz maili; **nie ukańczasz i nie kasujesz** zadań (to robi użytkownik, a rejestr to zauważa); nie labelujesz „na czuja" maili ważnych/`IMPORTANT` - takie idą do `AI/Triage`.

### Kontrakt ostatniej wiadomości (powiadomienie push)

Paseo wysyła na telefon **pierwsze 220 znaków ostatniej wiadomości agenta**. Dlatego ostatnia wiadomość **zaczyna się od jednego samodzielnego zdania podsumowującego**, a dopiero pod nim idzie pełny raport. Przykład pierwszej linii:

> `Rutyna 8:00: 4 spotkania, 7 zadań na dziś (2 zaległe), 18 maili przetworzonych, 3 do decyzji → Inbox/Dashboard-2026-07-27.md`

Bez markdownu w tym zdaniu (push i tak go usuwa), bez „Cześć!", bez pytań.

## Default Routine (Morning)

When run without arguments, with `all` or with `unattended`:

### 1. Email Review (NAJPIERW)
Run `/email-review` (codzienny autopilot) across all accounts. Zaczyna od **uzgodnienia z Todoistem** (`python3 scripts/todoist.py sync` → diff): zadania, które ukończyłeś, domykają swoje maile, zanim cokolwiek innego się wydarzy. Dalej:
- Classify/label/draft per the EmailWorkflow rulebook, mark processed via `update_thread(status:"done")`
- Flag ambiguous threads via `update_thread(status:"triage")` without blocking
- Save reminders for emails needing follow-up
- Faktury trwałych dóbr >100 zł → `Rachunki/` w vault

**Kolejność jest istotna**: skrzynka musi być przetworzona **przed** budowaniem Dashboardu, żeby dashboard opisywał realny stan po triażu (świeże taski, świeże przypomnienia, aktualna sterta `AI/Triage`), a nie surowy inbox sprzed rutyny.

### 2. Task Check
`python3 scripts/todoist.py tasks --today --overdue --select id,title,due,data.priority` (odczyt z lustra odświeżonego w kroku 1, bez wywołań API):
- Overdue tasks
- Due today
- High priority items

### 3. Daily Briefing
Run `/daily-briefing` to create today's dashboard:
- Gather calendar events across all accounts
- Pull priority tasks from Todoist
- Podsumuj wynik kroku 1 (ile przetworzone, co wymaga uwagi, jak duża jest sterta `AI/Triage`)
- Review matured cases and reminders: `python3 scripts/ledger.py due`
- Write to `Inbox/Dashboard-[date].md` (z sekcją „Do decyzji")

Jeśli sterta `AI/Triage` urosła - odnotuj w „Do decyzji" rekomendację `/email-triage` (nie odpalaj go sam, jest interaktywny).

### 4. Present Unified Summary
Combine all findings into actionable summary:
- Top 3 priorities for the day
- Urgent items needing attention
- Suggested focus areas
- „Do decyzji" - to, czego nie wolno było rozstrzygnąć autonomicznie

### 5. Digital Twin Memory Update (CRITICAL)
Update AI Memory with ALL new context learned. This is essential to being a useful assistant:

| Source | What to Capture | Memory File (w vault Obsidian) |
|--------|-----------------|--------------------------------|
| Email | New contacts, people info | `Kontakty/*.md` |
| Email | Project mentions, updates | `Asystent/Memory/Projects.md` |
| Calendar | Attendees, event patterns | `Kontakty/*.md`, `Asystent/Memory/Insights.md` |
| Tasks | Project progress | `Asystent/Memory/Projects.md` |
| All | Work/personal context | `Asystent/Memory/Work.md`, `Asystent/Memory/Personal.md` |
| All | Important dates | `Asystent/Memory/Timeline.md` |
| All | Behavioral patterns | `Asystent/Memory/Preferences.md`, `Asystent/Memory/Insights.md` |

**Goal**: After each routine, the digital twin should know more than before.

## Arguments

Pass arguments to focus on specific areas:

| Argument | What it does |
|----------|--------------|
| `all` | Full routine (default) |
| `unattended` | To samo co `all` - argument harmonogramu, zachowanie i tak jest bezpytaniowe |
| `email` | Focus on inbox review only |
| `calendar` | Focus on schedule only |
| `tasks` | Focus on Todoist only |
| `briefing` | Run daily briefing only |
| `quick` | Brief status check, no briefing |

## Output Format

Pierwsza linia ostatniej wiadomości = jednozdaniowe podsumowanie (patrz „Kontrakt ostatniej wiadomości"), poniżej:

### Assistant Report - [Date]

#### Email Summary
| Account | Przetworzone | Do triażu | Wymaga działania |
|---------|--------------|-----------|------------------|
| Personal | X | Y | Z |
| Work | X | Y | Z |

**Needs attention**:
- [Priority email 1]
- [Priority email 2]

#### Task Summary
- [X] due today, [Y] overdue
- **Top priorities**:
  1. [Task 1]
  2. [Task 2]
  3. [Task 3]

#### Dashboard
Created: `Inbox/Dashboard-[date].md`

#### Schedule Summary
- [X] events today
- [Key events with times]
- [Any conflicts or tight transitions]

#### Focus Recommendations

Based on your day, I suggest:

1. **[Focus Area 1]**
   - Why: [reasoning]
   - Time: [suggested time block]

2. **[Focus Area 2]**
   - Why: [reasoning]

3. **[Focus Area 3]**
   - Why: [reasoning]

#### Actions Taken
- [x] Skrzynka przetworzona ([X] wątków)
- [x] Dashboard created
- [x] [Drafts created, if any]
- [x] Memory updated with [what]

#### Do decyzji
- [Kwestia, której nie wolno było rozstrzygnąć autonomicznie - co to jest, gdzie na to trafiłeś, jakie są opcje]
- [Propozycja wydarzenia w kalendarzu - termin + kontekst, do ręcznego utworzenia]
- [Sterta AI/Triage: X wątków → `/email-triage`]

---

*Routine completed at [timestamp]*

## Important Notes

- This is the "main" skill - orchestrates everything
- Kolejność jest częścią kontraktu: **email-review → taski → briefing**
- Adapt based on time of day (morning vs afternoon)
- Be proactive but not overwhelming
- **Nigdy nie zadawaj pytań** - patrz „Tryb nienadzorowany (ZAWSZE)"; otwarte kwestie → „Do decyzji"
- **Luki kontekstowe** wg protokołu CLAUDE.md „Luki kontekstowe", ale w tej rutynie **nic nie blokuje**: najpierw sam sprawdź materiał i vault (`qmd`, `Read` digital twina), a gdy dalej niejasne - mail → `AI/Triage` z powodem, reszta → „Do decyzji"
- Update memory with anything significant learned
