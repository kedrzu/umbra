---
name: memory-update
description: Explicitly update the AI's memory with new information. Use when user shares important context they want remembered, or when assistant learns something that should be preserved. Stores in AI/Memory/ folder.
---

# Memory Update

Update AI memory with: $ARGUMENTS

This skill explicitly updates the **Digital Twin** - the comprehensive model of the user's life.

## MCP Tools Used

| Operation | Tool |
|-----------|------|
| Read existing memory | `read_note` |
| Create/update AI memory | `create_ai_note` |
| Search for related notes | `qmd_query` |

## Memory Structure

```
AI/Memory/
├── People.md           # Index of all people (brief list with links)
├── People/             # Individual person files (detailed profiles)
│   ├── _TEMPLATE.md    # Template for new person files
│   └── Jan-Kowalski.md
├── Projects.md         # Index of all projects (brief list with links)
├── Projects/           # Individual project files (detailed profiles)
│   ├── _TEMPLATE.md    # Template for new project files
│   └── Project-Alpha.md
├── Work.md             # Professional context
├── Personal.md         # Personal life context
├── Preferences.md      # Behavioral patterns
├── Insights.md         # Observations and patterns
└── Timeline.md         # Life events and milestones
```

## Process

1. **Analyze the Information**
   - What category does this fit?
     - Person info → `People.md` (index) + `People/Imie-Nazwisko.md` (details)
     - Project context → `Projects.md` (index) + `Projects/Nazwa-Projektu.md` (details)
     - Work context → `Work.md`
     - Personal context → `Personal.md`
     - User preference → `Preferences.md`
     - Pattern/observation → `Insights.md`
     - Important date → `Timeline.md`
     - Email workflow strategy → `EmailWorkflow-Personal.md` or `EmailWorkflow-Work.md`
   - Is this new or an update to existing?
   - Does this connect to other information? (cross-reference!)

2. **For People or Projects**

   **If new person/project:**
   - Create individual file in `People/` or `Projects/` using template
   - Add entry to index file (`People.md` or `Projects.md`)
   - Use kebab-case for filenames: `Jan-Kowalski.md`, `Project-Alpha.md`

   **If updating existing:**
   - Find and update the individual file
   - Update index if status changed

3. **For Other Memory Files**
   - Read current file
   - Find the right section
   - Add or update entry

4. **Cross-Reference**
   - Link people to projects they're involved in
   - Link projects to people on the team
   - Use Obsidian wiki-links: `[[People/Jan-Kowalski|Jan Kowalski]]`

5. **Confirm to User**
   - What was stored
   - Where it was stored
   - How it will be used

## File Templates

### Person Index Entry (in `People.md`)
```markdown
- [[People/Jan-Kowalski|Jan Kowalski]] - Tech Lead, zespół backend
```

### Person Detail File (`People/Jan-Kowalski.md`)
```markdown
# Jan Kowalski

- **Relacja**: Kolega z pracy, zespół backend
- **Skąd się znamy**: Pracujemy razem od 2022
- **Kontekst**: Prowadzi projekt X, ekspert od Kubernetes

## Komunikacja
- **Preferowany kanał**: Email, Slack
- **Styl**: Krótkie maile, odpowiada szybko rano

## Projekty wspólne
- [[Projects/Project-Alpha|Project Alpha]] - Tech Lead

## Powiązania
- [[People/Anna-Nowak|Anna Nowak]] - jego manager

## Ważne
- Ma córkę (Zuzia, ~5 lat)
- Interesuje się bieganiem

## Historia
- 2024-01: Rozpoczęliśmy współpracę przy Project Alpha
- 2024-06: Awansował na tech leada

## Notatki
- **Ostatni kontakt**: 2025-01-28 (email o deadline)

---
*Ostatnia aktualizacja: 2025-01-28*
```

### Project Index Entry (in `Projects.md`)
```markdown
- [[Projects/Project-Alpha|Project Alpha]] - Migracja legacy, deadline 2025-03-15
```

### Project Detail File (`Projects/Project-Alpha.md`)
```markdown
# Project Alpha

- **Typ**: Praca / kluczowy projekt
- **Status**: Aktywny, faza 2
- **Priorytet**: Wysoki

## Kontekst
Migracja systemu legacy do nowej architektury, budżet 500k.

## Zespół
- [[People/Jan-Kowalski|Jan Kowalski]] - Tech Lead
- [[People/Anna-Nowak|Anna Nowak]] - PM
- Ja - Backend developer

## Timeline
- **Start**: 2024-01
- **Deadline**: 2025-03-15

## Ryzyka
- Zależność od zewnętrznego API

## Historia decyzji
- 2024-11: Wybrano technologię X (powód: lepsza wydajność)
- 2025-01: Przesunięto deadline z lutego (powód: scope creep)

## Postęp
- 2025-01-28: Zakończono fazę 1

---
*Ostatnia aktualizacja: 2025-01-28*
```

## Output Format

### Memory Updated

**Category**: [People/Projects/Work/Personal/Preferences/Insights/Timeline]
**Files updated**:
- `AI/Memory/[path]`

**Action**: [Created new / Updated existing]

**What was saved**:
> [Summary of the information stored]

**Cross-references added**:
- [Links to related entries if applicable]

**How this helps**:
[Brief explanation of how this memory will be used]

## Important Rules

- **People & Projects**: Always use index + individual files
- **Naming**: Use kebab-case for filenames (e.g., `Jan-Kowalski.md`)
- **Cross-reference**: Link between people and projects
- **Templates**: Use `_TEMPLATE.md` files as starting point
- Always read the file first before updating
- Preserve existing content
- Use consistent formatting
- Include dates
- Be specific - vague memories aren't useful
- Don't store sensitive info like passwords
