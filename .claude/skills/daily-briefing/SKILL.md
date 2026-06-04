---
name: daily-briefing
description: Poranny briefing. Zbiera kalendarz, zadania, emaile, przegląda przypomnienia i prezentuje co masz dziś na tapecie. Tworzy Dashboard w Obsidian.
---

# Daily Briefing

Codzienny briefing - wszystko czego potrzebujesz na start dnia.

## Vault Obsidian

**WAŻNE**: Wszystkie pliki pamięci i kontaktów są w vault Obsidian (`./obsidian/`), NIE w lokalnym folderze projektu!

Foldery w vault:
- `./obsidian/Kontakty/` - profile osób (frontmatter YAML dla Obsidian Bases)
- `./obsidian/Asystent/Memory/` - pamięć systemowa (Projects.md, EmailReminders.md, etc.)
- `./obsidian/Inbox/` - dashboardy (np. `./obsidian/Inbox/Dashboard-YYYY-MM-DD.md`)

## MCP Tools Used

| Operation | Tool |
|-----------|------|
| Read memory | `Read` |
| Search contacts/notes | `qmd` (MCP) - NIE Glob! |
| List files in vault | `Bash(ls ./obsidian/...)` - NIE Glob! |
| Calendar events | `list-events` |
| Tasks | Todoist tools |
| Email scan | `search_threads` |
| Create dashboard | `Write` |
| Update memory | `Edit` |

**WAŻNE**: `./obsidian/` jest symlinkiem - Glob może nie działać!

## Process

1. **Pobierz aktualną datę i czas**

2. **Przeczytaj AI Memory**
   - `./obsidian/Asystent/Memory/Projects.md` - aktywne projekty
   - `./obsidian/Asystent/Memory/EmailReminders.md` - przypomnienia do przeglądu
   - `./obsidian/Asystent/Memory/Insights.md` - wzorce i preferencje

   **NIE ładuj listy kontaktów** - jeśli potrzebujesz info o uczestniku spotkania, użyj `qmd` do wyszukania po imieniu

3. **Zbierz wydarzenia z kalendarza** na dziś
   - Użyj `list-events` dla wszystkich kont (Personal, Work, Shared)
   - Grupuj: Praca / Osobiste / Wspólne
   - Wykryj konflikty i ciasne przejścia między spotkaniami

4. **Pobierz zadania** z Todoist
   - Due today + overdue
   - Priorytet P1, P2
   - Sortuj wg priorytetu

5. **Skanuj emaile** (szybki przegląd)
   - Liczba nieprzeczytanych per konto
   - Pilne/ważne do uwagi

6. **Przegląd przypomnień emailowych**
   - Znajdź przypomnienia z `EmailReminders.md` gdzie data <= dziś
   - Dla zaległych (data < dziś):
     - Sprawdź czy wątek ma nową aktywność (użyj `get_thread`)
     - Oznacz jako "do weryfikacji"
   - Dla dzisiejszych:
     - Uwzględnij w sekcji "Na dziś"

7. **Wygeneruj sugestie fokusowe** (2-3 obszary)
   - Na podstawie kalendarza, zadań, deadlines
   - BEZ planowania godzina-po-godzinie

8. **Utwórz notatkę Dashboard**
   - Ścieżka: `Inbox/Dashboard-YYYY-MM-DD.md`
   - Użyj `create_user_note`

9. **Przedstaw briefing użytkownikowi**

10. **Aktualizuj Digital Twin Memory**
    - Nowe osoby z kalendarza → utwórz `./obsidian/Kontakty/Imie-Nazwisko.md` (użyj `qmd` żeby sprawdzić czy już istnieje)
    - Uczestnicy spotkań → użyj `qmd` do znalezienia kontaktu, aktualizuj `ostatni_kontakt`
    - Po spotkaniach → dodaj wpis do `## Historia kontaktów` uczestników
    - Kontekst projektowy → `./obsidian/Asystent/Memory/Projects.md`
    - Wzorce → `./obsidian/Asystent/Memory/Insights.md`

    **WAŻNE**: NIE ładuj całej listy kontaktów - wyszukuj przez `qmd`!

## Template notatki Dashboard

```markdown
# Dashboard - [Full Date]

## Harmonogram

### Praca
| Godzina | Wydarzenie | Miejsce |
|---------|------------|---------|
| ... | ... | ... |

### Osobiste
| Godzina | Wydarzenie | Miejsce |
|---------|------------|---------|
| ... | ... | ... |

### Wspólne
| Godzina | Wydarzenie | Miejsce |
|---------|------------|---------|
| ... | ... | ... |

**Uwagi**: [konflikty, ciasne przejścia między spotkaniami]

## Zadania na dziś

### Pilne (P1)
- [ ] [Zadanie] - [kontekst]

### Ważne (P2)
- [ ] [Zadanie] - [kontekst]

### Zaległe
- [ ] [Zadanie] - opóźnienie [X dni]

## Emaile wymagające uwagi

### Praca ([X] nieprzeczytanych)
| Od | Temat | Sugerowana akcja |
|----|-------|------------------|
| ... | ... | ... |

### Osobiste ([X] nieprzeczytanych)
| Od | Temat | Sugerowana akcja |
|----|-------|------------------|
| ... | ... | ... |

## Przypomnienia

### Na dziś
- [ ] [Reminder] - [Link](url)

### Do weryfikacji (z poprzednich dni)
- [ ] [Reminder zaległy] - ustawione [data] - [Link](url)

## Na czym się skupić

1. **[Obszar 1]**: [uzasadnienie]
2. **[Obszar 2]**: [uzasadnienie]

---
*Wygenerowano: [timestamp]*
```

## Output (briefing dla użytkownika)

```markdown
### Dzień dobry! Co masz dziś na tapecie:

**Kalendarz**: [X] spotkań
**Zadania**: [X] na dziś, [Y] zaległych
**Emaile**: [X] nieprzeczytanych

---

#### Kluczowe punkty dnia
[Top 3-5 najważniejszych rzeczy z kontekstem]

#### Zadania priorytetowe
1. [Zadanie 1]
2. [Zadanie 2]
3. [Zadanie 3]

#### Przypomnienia emailowe

[Jeśli są dzisiejsze przypomnienia:]
**Na dziś:**
- [Temat] - [kontekst] - [Link](url)

[Jeśli są zaległe przypomnienia:]
**Do weryfikacji z poprzednich dni:**
1. **[Temat]** (z [data]) - [krótki kontekst]
   → Sprawdziłem wątek: [status - czy jest nowa aktywność]

Które możemy oznaczyć jako załatwione? (np. "1 i 3" / "wszystkie" / "żadne")

#### Sugerowane obszary fokusowe
1. **[Obszar 1]** - [uzasadnienie]
2. **[Obszar 2]** - [uzasadnienie]

---
*Dashboard zapisany: `Inbox/Dashboard-[date].md`*
```

## Obsługa przypomnień

### Oznaczanie jako rozwiązane

Gdy użytkownik wskaże które przypomnienia są załatwione:
1. Przeczytaj `Asystent/Memory/EmailReminders.md`
2. Przenieś wskazane przypomnienia do sekcji "Rozwiązane"
3. Dodaj datę rozwiązania i przekreślenie
4. Zapisz zaktualizowany plik

### Format rozwiązanego przypomnienia

```markdown
## Rozwiązane

### Luty 2025
- [x] ~~**[Praca]** Re: Umowa z XYZ Corp~~ - Rozwiązane 2025-02-03
```

## Important Rules

- NIE planuj godzina-po-godzinie - tylko obszary fokusowe
- Przypomnienia weryfikuj zbiorczo, nie pojedynczo
- Zawsze twórz notatkę Dashboard w Obsidian
- Aktualizuj Digital Twin Memory przy każdym uruchomieniu
