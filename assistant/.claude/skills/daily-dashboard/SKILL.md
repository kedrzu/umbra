---
name: daily-dashboard
description: Generate a daily dashboard note in Obsidian with today's schedule, tasks, emails needing attention, and focus areas. Creates or updates Inbox/Dashboard-YYYY-MM-DD.md.
---

# Daily Dashboard

Generate today's dashboard note in Obsidian.

## Process

1. **Get current date and time**

2. **Gather calendar events** for today
   - Use `list-events` for today's date across all accounts
   - Group by: Personal / Work / Shared
   - Include: time, title, location, attendees

3. **Get priority tasks** from Todoist
   - Due today or overdue
   - High priority (P1, P2)
   - Sort by priority then due time

4. **Check priority emails** (brief scan)
   - Unread count per account
   - Any urgent/important flagged

5. **Read AI Memory** for context
   - Check `AI/Memory/Projects.md` for active projects
   - Check `AI/Memory/Insights.md` for relevant patterns
   - Look for follow-ups or reminders

6. **Generate focus suggestions** based on:
   - Calendar density (busy day = less deep work)
   - Upcoming deadlines
   - Overdue tasks
   - Project priorities

7. **Create/update dashboard note**
   - Path: `Inbox/Dashboard-YYYY-MM-DD.md`
   - Use `create_user_note` for new note
   - Include generation timestamp

## Dashboard Template

```markdown
# Dashboard - [Full Date]

## Today's Schedule

### Personal
| Time | Event | Location |
|------|-------|----------|
| ... | ... | ... |

### Work
| Time | Event | Location |
|------|-------|----------|
| ... | ... | ... |

### Shared
| Time | Event | Location |
|------|-------|----------|
| ... | ... | ... |

## Priority Tasks

- [ ] [P1] [Task name] - due [time/today/overdue]
- [ ] [P2] [Task name] - due [time/today/overdue]
- ...

## Emails Needing Attention

### Personal ([count] unread)
- [Brief summary of important emails]

### Work ([count] unread)
- [Brief summary of important emails]

## Focus Areas

Based on your schedule and priorities:
1. [First focus recommendation]
2. [Second focus recommendation]
3. [Third focus recommendation]

## Reminders

- [Context from AI Memory - follow-ups, deadlines, etc.]
- [Anything the assistant should remind the user about]

---
*Generated at [timestamp]*
```

## Output

After generating the dashboard:
1. Confirm the note was created
2. Provide a brief verbal summary of the day
3. Highlight anything that needs immediate attention

## Digital Twin Memory Update

While gathering data, actively capture information for the digital twin:
- New calendar attendees → `People.md`
- Project-related events → `Projects.md`
- Patterns in scheduling → `Preferences.md` or `Insights.md`
- Important upcoming dates → `Timeline.md`

This is not optional - every dashboard run should contribute to building the user's digital twin.
