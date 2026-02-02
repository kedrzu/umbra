---
name: inbox-review
description: Review and triage email inbox across all Gmail accounts. Summarize important messages, draft responses, and suggest labels. Use when the user wants to catch up on email or asks about their inbox.
---

# Inbox Review

Review email inbox across all configured Gmail accounts.

## MCP Tools Used

| Operation | Tool |
|-----------|------|
| Read memory | `read_note` |
| Search emails | `search_threads` |
| Read thread content | `get_thread` |
| Create draft | `create_draft` |
| Apply labels | `modify_labels` |
| Update memory | `create_ai_note` |

## Gmail Accounts

| Account | Email |
|---------|-------|
| Personal | kedrzu@gmail.com |
| Work | kedrzu@sigma.clinic |

## Process

1. **Check AI Memory** first
   - Use `read_note` to read `AI/Memory/People.md` for known contacts
   - Use `read_note` to read `AI/Memory/Preferences.md` for email handling preferences
   - Use `read_note` to read `AI/Memory/EmailWorkflow-Personal.md` for personal account labeling strategy (if exists)
   - Use `read_note` to read `AI/Memory/EmailWorkflow-Work.md` for work account labeling strategy (if exists)

2. **Search for unread emails** in each account
   - Use `search_threads` with query `is:unread` for kedrzu@gmail.com (Personal)
   - Use `search_threads` with query `is:unread` for kedrzu@sigma.clinic (Work)
   - Group results by account (Personal / Work)

3. **Identify priority messages** by checking:
   - Sender importance (known contacts from Memory)
   - Subject keywords (urgent, important, deadline, action required)
   - Thread context and length
   - Calendar invites or meeting-related

4. **Categorize emails**:
   - **Priority** - Needs attention today
   - **FYI** - Informational, no action needed
   - **Low Priority** - Can wait / promotional
   - **Potential Spam** - Newsletters to potentially unsubscribe

5. **For priority emails**:
   - Summarize key points (2-3 bullets max)
   - Suggest action (reply, schedule, delegate, archive)
   - Draft responses if needed using `create_draft`

6. **Apply email workflow strategy** (if defined)
   - Check if `EmailWorkflow-Personal.md` or `EmailWorkflow-Work.md` exists
   - Use `modify_labels` to apply labels per EmailWorkflow rules
   - Ask before applying labels to important threads
   - If no workflow defined, suggest running `/email-analysis`

7. **Suggest additional labels** for organization not covered by workflow

8. **Zapisz przypomnienia** dla emaili wymagających follow-up
   - Jeśli email wymaga działania w przyszłości, zaproponuj datę przypomnienia
   - Użyj `read_note` aby przeczytać `AI/Memory/EmailReminders.md`
   - Użyj `update_ai_note` (lub `create_ai_note` jeśli nie istnieje) aby dodać przypomnienie
   - Uwzględnij: datę przypomnienia, konto źródłowe, temat, link do wątku, kontekst
   - Format linku Gmail: `https://mail.google.com/mail/u/{email}/#inbox/{threadId}`
     - Personal: `https://mail.google.com/mail/u/kedrzu@gmail.com/#inbox/{threadId}`
     - Work: `https://mail.google.com/mail/u/kedrzu@sigma.clinic/#inbox/{threadId}`
   - Sugeruj daty na podstawie:
     - Deadline w emailu → użyj tej daty
     - Oczekiwana odpowiedź → +3-5 dni roboczych
     - Czekanie na dokument → obiecana data + 1 dzień
     - Okresowe sprawdzenie → za tydzień
   - Sprawdź aktualną datę żeby przypomnienia miały sens

9. **Update Digital Twin Memory** (REQUIRED)
   Use `read_note` then `create_ai_note` to update AI Memory files:
   - `AI/Memory/People.md` - New contacts, updated info about known people
   - `AI/Memory/Projects.md` - Project updates mentioned in emails
   - `AI/Memory/Work.md` / `AI/Memory/Personal.md` - Context learned
   - `AI/Memory/Timeline.md` - Important dates discovered
   - `AI/Memory/Insights.md` - Patterns noticed (communication styles, timing)

## Output Format

### Personal Inbox ([count] unread)

#### Priority
| From | Subject | Summary | Suggested Action |
|------|---------|---------|------------------|
| ... | ... | ... | ... |

#### FYI
- [Brief list of informational emails]

#### Low Priority
- [Count] promotional/newsletter emails

### Work Inbox ([count] unread)
[Same structure]

### Drafts Created
- [List of drafts created with brief description]

### Suggested Actions
- [ ] [Specific follow-up actions]

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

## Important Rules

- Never send emails, only create drafts
- Ask before applying labels to important threads
- Update AI/Memory/People.md with new important contacts
- Note any emails that might need unsubscribe review
- Zapisuj przypomnienia tylko dla emaili naprawdę wymagających follow-up
