---
name: research
description: Research a topic using the Obsidian knowledge vault. Searches across all notes, synthesizes information, and creates a research summary. Use when user asks about a topic, needs background info, or wants to understand something in their vault.
---

# Research

Research a topic: $ARGUMENTS

## Vault Obsidian

**WAŻNE**: Wszystkie pliki pamięci i notatek są w vault Obsidian (`./obsidian/`), NIE w lokalnym folderze projektu!

Przeszukujesz vault Obsidian używając:
- `qmd` MCP - semantic + keyword search
- `Read`, `Glob` - bezpośredni dostęp do plików

Foldery w vault:
- `./obsidian/Kontakty/` - profile osób
- `./obsidian/Asystent/Memory/` - pamięć systemowa
- `./obsidian/Asystent/Research/` - zapisane raporty badawcze

## Process

1. **Understand the Query**
   - What is the user trying to learn?
   - What type of information would be helpful?
   - Any specific context or constraints?

2. **Search the Vault**
   - Use `qmd_query` for hybrid search (semantic + keyword)
   - Try multiple query variations:
     - Direct topic search
     - Related terms
     - People/projects that might be connected
   - Use `qmd_search` for exact keyword matches if needed

3. **Retrieve Relevant Notes**
   - Use `read_note` to get full content of promising results
   - Look for connections between notes
   - Check linked notes (Obsidian wiki-links)

4. **Check AI Memory** (wszystkie pliki w vault Obsidian)
   - `Kontakty/*.md` - relevant people
   - `Asystent/Memory/Projects.md` - related projects
   - `Asystent/Memory/Insights.md` - past observations

5. **Synthesize Findings**
   - Combine information from multiple sources
   - Identify patterns and connections
   - Note contradictions or gaps

6. **Create Research Summary** (optional)
   - If substantial findings, create `Asystent/Research/[topic]-[date].md`
   - Preserves research for future reference

## Output Format

### Research: [Topic]

#### Summary
[2-3 paragraph synthesis of findings]

#### Key Points
- [Important finding 1]
- [Important finding 2]
- [Important finding 3]

#### Sources
| Note | Relevance | Key Quote/Info |
|------|-----------|----------------|
| [[Note 1]] | High | "..." |
| [[Note 2]] | Medium | "..." |

#### Related
- **People**: [Relevant contacts from Memory]
- **Projects**: [Related projects]
- **Notes**: [Other related notes found]

#### Gaps
- [What couldn't be answered]
- [What might need external research]

#### Suggestions
- [Next steps if user wants to go deeper]
- [Related topics to explore]

## Notes

- Always cite sources (note paths)
- If nothing found in vault, say so clearly
- Suggest external research if vault doesn't have the answer
- Create research note only for substantial findings
- **Luka kontekstowa** (protokół CLAUDE.md „Luki kontekstowe"): gdy odpowiedź zależy od kontekstu, którego **nie ma w vault** (kryptonim, skrót, osoba, dokument), nie poprzestawaj na raportowaniu tego w „Gaps" — **dopytaj użytkownika** i **utrwal** odpowiedź (osoba → `Kontakty/`, reszta → `Insights.md`/temat), żeby kolejny research już to miał. Najpierw jednak wyczerp `qmd`/`Read` — pytasz dopiero, gdy vault milczy.
