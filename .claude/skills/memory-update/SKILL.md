---
name: memory-update
description: Explicitly update the AI's memory with new information. Use when user shares important context they want remembered, or when assistant learns something that should be preserved. Stores in Asystent/Memory/ folder.
---

# Memory Update

Update AI memory with: $ARGUMENTS

This skill explicitly updates the **Digital Twin** - the comprehensive model of the user's life.

## Vault Obsidian

**WAŻNE**: Wszystkie pliki pamięci i kontaktów są w vault Obsidian (`./obsidian/`), NIE w lokalnym folderze projektu!

Foldery w vault:
- `./obsidian/Kontakty/` - profile osób (frontmatter YAML dla Obsidian Bases)
- `./obsidian/Asystent/Memory/` - pamięć systemowa (Projects.md, Work.md, Personal.md, etc.)
- `./obsidian/Projects/` - szczegółowe pliki projektów

## MCP Tools Used

| Operation | Tool |
|-----------|------|
| Read existing memory | `Read` |
| Create/update AI memory | `Edit`, `Write` |
| Search for related notes | `qmd` (MCP) |
| List files in vault | `Bash(ls ./obsidian/...)` - NIE Glob! |

**WAŻNE**: `./obsidian/` jest symlinkiem - Glob może nie działać!

## Memory Structure

```
Asystent/Memory/
├── Projects.md         # Index of all projects (brief list with links)
├── Projects/           # Individual project files (detailed profiles)
│   ├── _TEMPLATE.md    # Template for new project files
│   └── Project-Alpha.md
├── Work.md             # Professional context
├── Personal.md         # Personal life context
├── Preferences.md      # Behavioral patterns
├── Insights.md         # Observations and patterns
└── Timeline.md         # Life events and milestones

Kontakty/               # Osobny folder w vault (Obsidian Bases)
├── Kontakty.base       # Widok tabeli wszystkich kontaktów
├── _TEMPLATE-Osoba.md  # Szablon dla nowych osób
└── Imie-Nazwisko.md    # Profile osób (dane w frontmatter YAML)
```

## Process

1. **Analyze the Information**
   - What category does this fit?
     - Person info → `Kontakty/Imie-Nazwisko.md` (frontmatter YAML + sekcje)
     - Project context → `Projects.md` (index) + `Projects/Nazwa-Projektu.md` (details)
     - Work context → `Work.md`
     - Personal context → `Personal.md`
     - User preference → `Preferences.md`
     - Pattern/observation → `Insights.md`
     - Important date → `Timeline.md`
     - Email workflow strategy → `EmailWorkflow-Personal.md` or `EmailWorkflow-Work.md`
   - Is this new or an update to existing?
   - Does this connect to other information? (cross-reference!)
   - **Luka kontekstowa** (protokół CLAUDE.md „Luki kontekstowe"): jeśli zapisywana informacja odwołuje się do czegoś niejasnego (osoba, kryptonim, skrót, dokument), którego nie rozumiesz — **najpierw research** (`qmd`/`Read` digital twina), a gdy vault milczy i to blokuje sensowny zapis — **dopytaj użytkownika**. Lokalizację docelową i tak wybierasz wg routingu wyżej (osoba → `Kontakty/`, projekt → `Projects/`, reszta → `Work.md`/`Personal.md`/`Insights.md`).

2. **For People (Kontakty)**

   **Szukanie istniejącego kontaktu:**
   - Użyj `qmd` do wyszukania po imieniu, nazwisku lub emailu
   - NIE używaj Glob do listowania wszystkich kontaktów!

   **If new person:**
   - Create file in `./obsidian/Kontakty/` using `_TEMPLATE-Osoba.md`
   - Wypełnij frontmatter YAML (imię, nazwisko, email, kategoria, opis, etc.)
   - Use kebab-case for filenames: `Jan-Kowalski.md`
   - Brak indeksu - Obsidian Bases automatycznie wyświetla kontakty

   **If updating existing person:**
   - Znajdź plik używając `qmd` (wyszukaj po imieniu/emailu)
   - Aktualizuj frontmatter YAML (np. `ostatni_kontakt`, `email`)
   - Dodaj wpis do `## Historia kontaktów` jeśli był kontakt

   **Kategorie kontaktów**: `praca` | `rodzina` | `znajomy` | `biznes` | `rzemieślnik` | `medyczny`

3. **For Projects**

   **If new project:**
   - Create individual file in `Projects/` using template
   - Add entry to `Projects.md` index
   - Use kebab-case for filenames: `Project-Alpha.md`

   **If updating existing:**
   - Find and update the individual file
   - Update index if status changed

4. **For Other Memory Files**
   - Read current file
   - Find the right section
   - Add or update entry

5. **Cross-Reference**
   - Link people to projects they're involved in
   - Link projects to people on the team
   - Use Obsidian wiki-links: `[[Kontakty/Jan-Kowalski|Jan Kowalski]]`

6. **Confirm to User**
   - What was stored
   - Where it was stored
   - How it will be used

## File Templates

### Person File (`Kontakty/Jan-Kowalski.md`) z frontmatter YAML

```yaml
---
typ: osoba
utworzono: 2025-02-04
zaktualizowano: 2025-02-04
imie: Jan
nazwisko: Kowalski
email: jan@example.com
telefon: "+48 600 123 456"
kategoria: praca           # praca | rodzina | znajomy | biznes | rzemieślnik | medyczny
opis: "Tech Lead, zespół backend"  # Oneliner widoczny w tabeli Bases
status: aktywny            # aktywny | nieaktywny | archiwalny
priorytet: normalny        # wysoki | normalny | niski
firma: Google
stanowisko: Senior Engineer
branza: IT
linkedin_url: "https://linkedin.com/in/jan-kowalski"
linkedin_id: jan-kowalski
ostatni_kontakt: 2025-02-01
nastepny_kontakt: 2025-02-15
preferowany_kanal: email   # email | telefon | slack | spotkanie
projekty:
  - "[[Projects/Project-Alpha]]"
powiazania:
  - "[[Kontakty/Anna-Nowak]]"
---

# Jan Kowalski

## Podsumowanie
Kolega z pracy od 2022, prowadzi projekt X. Ekspert od Kubernetes.

## LinkedIn
> Cache danych z profilu LinkedIn. Aktualizować przy okazji.
> Ostatnia aktualizacja: -

**Tytuł**:
**About**:
**Doświadczenie**:

## Komunikacja
- **Preferowany kanał**: Email, Slack
- **Styl**: Krótkie maile, odpowiada szybko rano
- **Najlepszy czas**: Rano

## Projekty wspólne
- [[Projects/Project-Alpha|Project Alpha]] - Tech Lead

## Powiązania
- [[Kontakty/Anna-Nowak|Anna Nowak]] - jego manager

## Szczegóły osobiste
- Ma córkę (Zuzia, ~5 lat)
- Interesuje się bieganiem

## Historia kontaktów

### 2025-02-01 | Email | Deadline projektu
- **Źródło**: Email (jan@example.com)

Rozmowa o deadline projektu Alpha.

---

### 2024-06-15 | Spotkanie | Awans
- **Źródło**: Spotkanie

Awansował na tech leada.

---

## Dziennik relacji
- Świetna współpraca, komunikatywny
```

**Ważne**: Przy każdym kontakcie:
1. Aktualizuj `ostatni_kontakt` w frontmatter!
2. Dodaj wpis do `## Historia kontaktów` z datą i źródłem

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
- [[Kontakty/Jan-Kowalski|Jan Kowalski]] - Tech Lead
- [[Kontakty/Anna-Nowak|Anna Nowak]] - PM
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

**Category**: [Kontakty/Projects/Work/Personal/Preferences/Insights/Timeline]
**Files updated**:
- `Kontakty/[Imie-Nazwisko].md` lub `Asystent/Memory/[path]`

**Action**: [Created new / Updated existing]

**What was saved**:
> [Summary of the information stored]

**Cross-references added**:
- [Links to related entries if applicable]

**How this helps**:
[Brief explanation of how this memory will be used]

## Important Rules

- **People (Kontakty)**: Bez indeksu - bezpośrednio `Kontakty/Imie-Nazwisko.md` z frontmatter YAML
- **Projects**: Index (`Projects.md`) + individual files (`Projects/Nazwa.md`)
- **Naming**: Use kebab-case for filenames (e.g., `Jan-Kowalski.md`)
- **Cross-reference**: Link between people and projects: `[[Kontakty/...]]`, `[[Projects/...]]`
- **Templates**: Use `_TEMPLATE-Osoba.md` for new contacts
- **ostatni_kontakt**: Zawsze aktualizuj to pole przy każdym kontakcie!
- Always read the file first before updating
- Preserve existing content
- Use consistent formatting
- Include dates
- Be specific - vague memories aren't useful
- Don't store sensitive info like passwords
- **NIGDY** nie ustawiaj `status: archiwalny` - tylko użytkownik może archiwizować kontakty
