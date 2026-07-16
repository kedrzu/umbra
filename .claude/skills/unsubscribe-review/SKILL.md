---
name: unsubscribe-review
description: Find unwanted newsletter subscriptions and help unsubscribe. Searches for promotional emails, identifies unsubscribe options, and asks for approval before taking action. Use when user wants to clean up subscriptions.
---

# Unsubscribe Review

Find and clean up unwanted email subscriptions across all accounts.

## MCP Tools Used

| Operation | Tool |
|-----------|------|
| Read memory | `read_note` |
| Search promotional emails | `search_threads` |
| Get unsubscribe link | `get_unsubscribe_info` |
| Update memory | `create_ai_note` |

## Gmail Accounts

| Account | Email |
|---------|-------|
| Personal | kedrzu@gmail.com |
| Work | kedrzu@sigma.clinic |

## Vault Obsidian

**WAŻNE**: Wszystkie pliki pamięci są w vault Obsidian (`./obsidian/`), NIE w lokalnym folderze projektu!

## Process

0. **Check AI Memory** for context (pliki w vault Obsidian)
   - Użyj `Glob` z pattern `Kontakty/*.md` i `Read` aby przeczytać profile kontaktów - nie sugeruj wypisywania się od znanych osób
   - Użyj `Read` dla `./obsidian/Asystent/Memory/EmailWorkflow-Personal.md` i `./obsidian/Asystent/Memory/EmailWorkflow-Work.md` - zrozum kategorie labelowania
   - Użyj `Read` dla `./obsidian/Asystent/Memory/Preferences.md` - sprawdź preferencje unsubscribe

1. **Search for promotional emails** in each account
   - Query: `category:promotions OR label:promotions`
   - Query: `unsubscribe` (finds emails with unsubscribe links)
   - Query: `from:newsletter OR from:noreply OR from:no-reply`
   - Look at last 30 days of emails

2. **Group by sender** and count frequency
   - Identify repeat senders
   - Note which are opened vs unopened
   - Calculate "spam score" based on frequency and engagement

3. **Extract unsubscribe information**:
   - Check List-Unsubscribe header
   - Find unsubscribe links in email body
   - Note one-click vs multi-step unsubscribe

4. **Categorize subscriptions**:
   - **Definitely Spam** - Never opened, frequent sender
   - **Probably Unwanted** - Rarely opened, can unsubscribe
   - **Maybe Keep** - Occasionally opened
   - **Keep** - Regularly engaged with

5. **Present findings to user** with recommendations

6. **For each unsubscribe**:
   - **ASK FOR APPROVAL** before taking any action
   - Explain what will happen
   - Execute only after confirmation

## Output Format

### Subscription Analysis

#### Account: Personal

| Sender | Frequency | Last Opened | Recommendation | Unsubscribe Method |
|--------|-----------|-------------|----------------|-------------------|
| ... | ... | ... | ... | ... |

#### Account: Work
[Same structure]

### Recommended Unsubscribes

1. **[Sender Name]** - [Reason]
   - Unsubscribe method: [one-click / link / email]
   - Proceed? [Waiting for approval]

2. ...

### Summary
- Total subscriptions analyzed: [count]
- Recommended to unsubscribe: [count]
- Estimated emails saved per month: [estimate]

## Important Rules

- **ALWAYS ask for approval** before unsubscribing
- Present options clearly with consequences
- Don't unsubscribe from anything work-related without explicit approval
- Keep a record of unsubscribed senders in Asystent/Memory
- Label processed emails for tracking
- **Luka kontekstowa** (protokół CLAUDE.md „Luki kontekstowe"): nadawca z pogranicza, gdzie nie wiesz, czy subskrypcja jest chciana (a `qmd`/`Read` pamięci nie rozstrzyga) → dopytaj (skill i tak pyta o zgodę) i **utrwal** rozstrzygnięcie jako preferencję (`Preferences.md`/`Insights.md`), żeby następnym razem nie pytać.
