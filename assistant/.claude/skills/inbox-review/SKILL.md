---
name: inbox-review
description: Review and triage email inbox across all Gmail accounts. Summarize important messages, draft responses, and suggest labels. Use when the user wants to catch up on email or asks about their inbox.
---

# Inbox Review

Review email inbox across all configured Gmail accounts with batch processing for optimal context management.

**Scope:** Przetwarza wszystkie emaile bez labeli `AI/Done` lub `AI/Triage` (nie tylko nieprzeczytane).

## MCP Tools Used

| Operation | Tool |
|-----------|------|
| Read memory | `read_note` |
| Update memory | `update_ai_note`, `create_ai_note` |
| Search emails | `search_threads` |
| Read thread content | `get_thread` |
| Create draft | `create_draft` |
| Apply labels | `apply_label` (uses threadId) |

## Gmail Accounts

| Account | Email |
|---------|-------|
| Personal | kedrzu@gmail.com |
| Work | kedrzu@sigma.clinic |

## Batch Processing Configuration

| Setting | Value |
|---------|-------|
| Batch Size | 5 emails per batch |
| Max Batches | 10 per session |
| Auto-continue | Yes (process all without asking) |
| State File | `AI/Memory/InboxReviewState.md` |

## Process

### Phase 1: Session Management

1. **Check for existing session**
   - Use `read_note` to read `AI/Memory/InboxReviewState.md`
   - If status is `in_progress` and started < 1 hour ago:
     - Ask user: "Znaleziono niedokończoną sesję (X/Y emaili). Kontynuować czy zacząć od nowa?"
   - If no state file, old, or `completed` → start fresh session

2. **Initialize session state**
   - Use `search_threads` with `-label:AI/Done -label:AI/Triage` for both accounts (emails not yet processed by AI)
   - Calculate total emails and estimated batches
   - Create/update `AI/Memory/InboxReviewState.md` with initial state:
   ```markdown
   # Inbox Review State

   ## Current Session
   - **Started**: [ISO timestamp]
   - **Status**: in_progress
   - **Current Batch**: 1

   ## Progress

   ### Personal (kedrzu@gmail.com)
   - Total: [count]
   - Processed: 0

   #### Processed Thread IDs
   (none)

   ### Work (kedrzu@sigma.clinic)
   - Total: [count]
   - Processed: 0

   #### Processed Thread IDs
   (none)

   ## Accumulated Findings

   ### Priority Emails
   | Account | From | Subject | Action |
   |---------|------|---------|--------|

   ### Drafts Created
   (none)

   ### Labels Applied
   (none)

   ### Memory Updates Pending
   (none)

   ## Last Updated
   [ISO timestamp]
   ```

3. **Load AI Memory** (only on first batch)
   - Use `Glob` to find `Kontakty/*.md` - profile kontaktów z frontmatter YAML
   - Wyciągnij `email` z frontmatter każdego kontaktu do szybkiego matchowania
   - Use `read_note` to read `AI/Memory/Preferences.md` for email preferences
   - Use `read_note` to read `AI/Memory/EmailWorkflow-Personal.md` (if exists)
   - Use `read_note` to read `AI/Memory/EmailWorkflow-Work.md` (if exists)

### Phase 2: Batch Processing Loop

**Repeat for each batch until all emails processed or max batches reached:**

#### Step 1: Fetch Next Batch
- Use `search_threads` with `-label:AI/Done -label:AI/Triage` for current account
- Filter out thread IDs already in "Processed Thread IDs" list (from current session)
- Take first 5 unprocessed threads

#### Step 2: Process Batch
For each email in batch:

1. **Read thread content** using `get_thread`

2. **Identify priority** by checking:
   - Sender importance - matchuj email nadawcy z polem `email` w frontmatter `Kontakty/*.md`
   - Subject keywords (urgent, important, deadline, action required)
   - Thread context and length
   - Calendar invites or meeting-related

3. **Categorize**:
   - **Priority** - Needs attention today
   - **FYI** - Informational, no action needed
   - **Low Priority** - Can wait / promotional
   - **Potential Spam** - Newsletters to potentially unsubscribe

4. **For priority emails**:
   - Summarize key points (2-3 bullets max)
   - Suggest action (reply, schedule, delegate, archive)
   - Draft responses if needed using `create_draft`

5. **Apply labels** per EmailWorkflow rules (ask before applying to important threads)

6. **Mark as processed** using `apply_label` with threadId (from `search_threads` or `get_thread`):
   - Priority/needs attention → apply `AI/Triage`
   - FYI/Low Priority/Spam → apply `AI/Done`

7. **Track findings** for state file:
   - Add to Priority Emails table if priority
   - Note drafts created
   - Note labels applied
   - Queue memory updates (new contacts, project updates, etc.)

#### Step 3: Save Batch State
After processing each batch, use `update_ai_note` to update `AI/Memory/InboxReviewState.md`:
- Add processed thread IDs to list
- Update processed counts
- Increment current batch number
- Append new findings to Accumulated Findings sections
- Update "Last Updated" timestamp

#### Step 4: Continue or Complete
- If more unprocessed emails remain → continue to next batch
- If all emails processed OR max batches reached → proceed to Phase 3

**Between batches, output brief progress:**
```
Batch [N] complete: [X] emails processed. Continuing...
```

### Phase 3: Session Completion

1. **Zapisz przypomnienia** dla emaili wymagających follow-up
   - Use `read_note` to read `AI/Memory/EmailReminders.md`
   - Use `update_ai_note` (or `create_ai_note`) to add reminders
   - Format linku Gmail:
     - Personal: `https://mail.google.com/mail/u/kedrzu@gmail.com/#inbox/{threadId}`
     - Work: `https://mail.google.com/mail/u/kedrzu@sigma.clinic/#inbox/{threadId}`
   - Sugeruj daty na podstawie:
     - Deadline w emailu → użyj tej daty
     - Oczekiwana odpowiedź → +3-5 dni roboczych
     - Czekanie na dokument → obiecana data + 1 dzień
     - Okresowe sprawdzenie → za tydzień

2. **Commit pending memory updates**

   **Kontakty (Kontakty/):**
   - Dla znanych kontaktów: aktualizuj `ostatni_kontakt` w frontmatter YAML
   - Dodaj wpis do `## Historia kontaktów` z datą, typem (Email) i linkiem Gmail:
     ```markdown
     ### 2025-02-04 | Email | Re: Temat wiadomości
     - **Źródło**: Email (kedrzu@gmail.com)
     - **Thread ID**: `abc123xyz`
     - **Link**: [Otwórz w Gmail](https://mail.google.com/mail/u/kedrzu@gmail.com/#inbox/abc123xyz)

     Streszczenie konwersacji...

     ---
     ```
   - Dla nowych kontaktów: utwórz plik w `Kontakty/` z frontmatter YAML

   **Inne pliki:**
   Use `read_note` then `update_ai_note` for:
   - `AI/Memory/Projects.md` - Project updates mentioned in emails
   - `AI/Memory/Work.md` / `AI/Memory/Personal.md` - Context learned
   - `AI/Memory/Timeline.md` - Important dates discovered
   - `AI/Memory/Insights.md` - Patterns noticed (communication styles, timing)

3. **Finalize state file**
   Update `AI/Memory/InboxReviewState.md`:
   - Set status to `completed`
   - Clear "Processed Thread IDs" (no longer needed)
   - Keep "Accumulated Findings" as session record

4. **Generate final summary** (see Output Format below)

## Output Format

### Session Summary

**Processed:** [X] emails across [N] batches
**Accounts:** Personal ([X] emails), Work ([Y] emails)

### Personal Inbox

#### Priority
| From | Subject | Summary | Suggested Action |
|------|---------|---------|------------------|
| ... | ... | ... | ... |

#### FYI
- [Brief list of informational emails]

#### Low Priority
- [Count] promotional/newsletter emails

### Work Inbox
[Same structure]

### Actions Taken
- **Drafts created:** [list]
- **Labels applied:** [list]
- **Reminders set:** [list]

### Memory Updated
- **Kontakty zaktualizowane:** [lista osób - aktualizacja ostatni_kontakt i historia]
- **Nowe kontakty:** [lista nowych profili w Kontakty/]
- **Inne:** [Brief list of what was updated in AI Memory]

## EmailReminders.md Format

Struktura pliku `AI/Memory/EmailReminders.md`:

```markdown
# Email Reminders

Przypomnienia o emailach wymagających działania.

## Oczekujące

### YYYY-MM-DD (Dzień tygodnia)
- [ ] **[Konto]** Temat emaila
  - Od: sender@example.com
  - Link: [Otwórz w Gmail](https://mail.google.com/mail/u/EMAIL/#inbox/THREAD_ID)
  - Kontekst: Dlaczego wymaga follow-up
  - Dodano: YYYY-MM-DD

## Rozwiązane

### Miesiąc YYYY
- [x] ~~**[Konto]** Temat~~ - Rozwiązane YYYY-MM-DD
```

Konta: `[Personal]` dla kedrzu@gmail.com, `[Praca]` dla kedrzu@sigma.clinic

## AI Processing Labels

Po przetworzeniu każdego emaila, zastosuj odpowiedni label:

| Label | Kiedy stosować |
|-------|----------------|
| `AI/Triage` | Email wymaga uwagi użytkownika (priority, wymaga decyzji) |
| `AI/Done` | Email w pełni obsłużony (FYI, low priority, spam) |

**Zasada:** Emaile z `AI/Triage` lub `AI/Done` nie będą ponownie przetwarzane w kolejnych sesjach.

## Important Rules

- Never send emails, only create drafts
- Ask before applying labels to important threads
- **Always apply `AI/Triage` or `AI/Done` label** after processing each email
- Save state after EVERY batch (enables resume on interruption)
- Queue memory updates, commit only at session end
- Thread IDs are the source of truth for progress (not counts)
- Zapisuj przypomnienia tylko dla emaili naprawdę wymagających follow-up
- Note any emails that might need unsubscribe review
