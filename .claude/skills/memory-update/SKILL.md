---
name: memory-update
description: Explicitly update the AI's memory with new information. Use when user shares important context they want remembered, or when assistant learns something that should be preserved. Stores in AI/Memory/ folder.
---

# Memory Update

Update AI memory with: $ARGUMENTS

This skill explicitly updates the **Digital Twin** - the comprehensive model of the user's life.

## Memory Files Overview

| File | Purpose |
|------|---------|
| `People.md` | Everyone in user's life - deep profiles with relationships, context, history |
| `Projects.md` | All initiatives - personal & professional, with full context and timeline |
| `Work.md` | Professional context - company, role, team, goals, career |
| `Personal.md` | Personal life - family, interests, health, values, goals |
| `Preferences.md` | Behavioral patterns - communication, scheduling, decision-making |
| `Insights.md` | Observations - patterns, connections, predictions |
| `Timeline.md` | Life events - milestones, important dates, anniversaries |

## Process

1. **Analyze the Information**
   - What category does this fit?
     - Person info → `AI/Memory/People.md`
     - Project context → `AI/Memory/Projects.md`
     - Work context → `AI/Memory/Work.md`
     - Personal context → `AI/Memory/Personal.md`
     - User preference → `AI/Memory/Preferences.md`
     - Pattern/observation → `AI/Memory/Insights.md`
     - Important date → `AI/Memory/Timeline.md`
   - Is this new or an update to existing?
   - Does this connect to other information? (cross-reference!)

2. **Read Current Memory File**
   - Use `read_note` to get current content
   - Find the right section for the update
   - Check if entry already exists

3. **Format the Update**
   - Follow the template format for that file
   - Include date of update
   - Be specific and concise
   - Link to related entries if applicable

4. **Write the Update**
   - Use `update_ai_note` to save changes
   - Preserve existing content
   - Add new entry or update existing

5. **Confirm to User**
   - What was stored
   - Where it was stored
   - How it will be used

## Memory File Formats

### People.md
```markdown
## [Person Name]
- **Relationship**: [type]
- **Context**: [how user knows them]
- **Key Details**: [relevant info]
- **Communication Preferences**: [if known]
- **Last Mentioned**: [date]
```

### Projects.md
```markdown
## [Project Name]
- **Status**: [active/paused/completed]
- **Type**: [work/personal/side-project]
- **Description**: [brief description]
- **Key Context**: [important details]
- **Related People**: [[links]]
- **Last Updated**: [date]
```

### Preferences.md
```markdown
## [Preference Category]
- [Specific preference observed]
- [Another preference]
```

### Insights.md
```markdown
## [Insight Title]
**Observed**: [date]
**Context**: [what led to this]
**Pattern**: [the insight]
**Implications**: [how to use this]
```

## Output Format

### Memory Updated

**Category**: [People/Projects/Preferences/Insights]
**File**: `AI/Memory/[filename].md`
**Action**: [Added new entry / Updated existing entry]

**What was saved**:
> [Summary of the information stored]

**How this helps**:
[Brief explanation of how this memory will be used]

## Important Rules

- Always read the file first before updating
- Preserve existing content
- Use consistent formatting
- Include dates
- Be specific - vague memories aren't useful
- Don't store sensitive info like passwords
