---
name: inbox-review
description: Review and triage email inbox across all Gmail accounts. Summarize important messages, draft responses, and suggest labels. Use when the user wants to catch up on email or asks about their inbox.
---

# Inbox Review

Review email inbox across all configured Gmail accounts.

## Process

1. **Check AI Memory** first
   - Read `AI/Memory/People.md` for known contacts
   - Read `AI/Memory/Preferences.md` for email handling preferences

2. **Search for unread emails** in each account
   - Use `search_threads` with query `is:unread` for each account
   - Group by account (Personal / Work)

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

6. **Suggest labels** for organization

7. **Update Digital Twin Memory** (REQUIRED)
   After processing emails, update AI Memory files:
   - `People.md` - New contacts, updated info about known people
   - `Projects.md` - Project updates mentioned in emails
   - `Work.md` / `Personal.md` - Context learned
   - `Timeline.md` - Important dates discovered
   - `Insights.md` - Patterns noticed (communication styles, timing)

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

## Important Rules

- Never send emails, only create drafts
- Ask before applying labels to important threads
- Update AI/Memory/People.md with new important contacts
- Note any emails that might need unsubscribe review
