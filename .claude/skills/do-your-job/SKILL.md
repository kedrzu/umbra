---
name: do-your-job
description: Run the full assistant routine. Reviews inbox, generates daily dashboard, checks tasks, and provides comprehensive daily assistance. The "magic button" for full assistant mode.
---

# Full Assistant Routine

Run the complete assistant workflow.

## Default Routine (Morning)

When run without arguments or with `all`:

### 1. Generate Daily Dashboard
First, create today's dashboard note in Obsidian.
- Gather calendar events across all accounts
- Pull priority tasks from Todoist
- Check email counts and priorities
- Write to `Inbox/Dashboard-[date].md`

### 2. Inbox Review
Review emails across all accounts:
- Identify priority messages
- Summarize important emails
- Draft responses for urgent items
- Flag potential unsubscribes

### 3. Task Check
Review Todoist status:
- Overdue tasks
- Due today
- High priority items

### 4. Present Unified Summary
Combine all findings into actionable summary:
- Top 3 priorities for the day
- Urgent items needing attention
- Suggested focus areas

### 5. Digital Twin Memory Update (CRITICAL)
Update AI Memory with ALL new context learned. This is essential to being a useful assistant:

| Source | What to Capture | Memory File |
|--------|-----------------|-------------|
| Email | New contacts, people info | `People.md` |
| Email | Project mentions, updates | `Projects.md` |
| Calendar | Attendees, event patterns | `People.md`, `Insights.md` |
| Tasks | Project progress | `Projects.md` |
| All | Work/personal context | `Work.md`, `Personal.md` |
| All | Important dates | `Timeline.md` |
| All | Behavioral patterns | `Preferences.md`, `Insights.md` |

**Goal**: After each routine, the digital twin should know more than before.

## Arguments

Pass arguments to focus on specific areas:

| Argument | What it does |
|----------|--------------|
| `all` | Full routine (default) |
| `email` | Focus on inbox review only |
| `calendar` | Focus on schedule only |
| `tasks` | Focus on Todoist only |
| `dashboard` | Generate dashboard only |
| `quick` | Brief status check, no dashboard |

## Output Format

### Assistant Report - [Date]

#### Dashboard
Created: `Inbox/Dashboard-[date].md`

#### Schedule Summary
- [X] events today
- [Key events with times]
- [Any conflicts or tight transitions]

#### Task Summary
- [X] due today, [Y] overdue
- **Top priorities**:
  1. [Task 1]
  2. [Task 2]
  3. [Task 3]

#### Email Summary
| Account | Unread | Priority |
|---------|--------|----------|
| Personal | X | Y |
| Work | X | Y |

**Needs attention**:
- [Priority email 1]
- [Priority email 2]

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
- [x] Dashboard created
- [x] [Drafts created, if any]
- [x] Memory updated with [what]

#### Questions
- [Any clarifying questions for the user]

---

*Routine completed at [timestamp]*

## Important Notes

- This is the "main" skill - orchestrates everything
- Adapt based on time of day (morning vs afternoon)
- Be proactive but not overwhelming
- Ask permission before creating tasks/events
- Update memory with anything significant learned
