---
name: daily-planning
description: Morning planning routine. Generates the daily dashboard, reviews inbox, and helps plan the day interactively. Use at the start of a work day or when user asks to plan their day.
---

# Daily Planning

Comprehensive morning planning routine.

## Process

1. **Generate Daily Dashboard**
   - Run the `/daily-dashboard` skill first
   - This creates the Obsidian note with all data

2. **Present Day Overview**
   - Summarize calendar highlights
   - Flag any scheduling conflicts
   - Note back-to-back meetings

3. **Review Task Priorities**
   - What's overdue?
   - What's due today?
   - What should be today's focus?

4. **Quick Inbox Check**
   - Any urgent emails requiring immediate response?
   - Any meeting-related emails (agendas, prep needed)?

5. **Interactive Planning**
   - Ask: "Any tasks you want to add for today?"
   - Ask: "Anything I should know about today's meetings?"
   - Ask: "Any priorities I should factor in?"

6. **Generate Focus Recommendation**
   Based on everything gathered:
   - Suggest 1-3 focus areas for the day
   - Recommend time blocks for deep work (if calendar allows)
   - Flag potential context switches

7. **Digital Twin Memory Update**
   Every planning session should contribute to the digital twin:
   - New context → `Projects.md`, `Work.md`, `Personal.md`
   - Observed patterns → `Preferences.md`, `Insights.md`
   - Important dates mentioned → `Timeline.md`
   - People context → `People.md`

## Output Format

### Good morning! Here's your day at a glance:

**Schedule**: [X] meetings, [Y] hours of available time
**Tasks**: [X] due today, [Y] overdue
**Emails**: [X] unread across accounts

### Key Events
[Top 3-5 most important events with brief context]

### Priority Tasks
[Top 3-5 tasks to focus on]

### Recommended Focus
Based on your schedule, I suggest:
1. [Focus area 1 with reasoning]
2. [Focus area 2 with reasoning]

### Questions for You
- [Interactive questions to refine the plan]

---

*Dashboard created at: `Inbox/Dashboard-[date].md`*

## Important Notes

- This skill is interactive - engage with the user
- Adapt recommendations based on calendar density
- Remember context from previous sessions via AI Memory
- Keep the planning focused and actionable
