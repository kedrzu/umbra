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

6. **Przegląd przypomnień emailowych** (rozstrzygasz sam, nie pytasz)
   - Znajdź przypomnienia z `EmailReminders.md` gdzie data <= dziś
   - Dla zaległych (data < dziś):
     - Sprawdź wątek (`get_thread`) - czy poszła odpowiedź, czy sprawa się domknęła
     - **Jednoznaczny dowód załatwienia** (moja odpowiedź w wątku / druga strona potwierdziła / powiązany task ukończony) → **sam** przenieś do "Rozwiązane" w `EmailReminders.md`
     - **Niejednoznaczne** → zostaw jako oczekujące, wypisz w "Do decyzji" z jednozdaniowym stanem wątku
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

### Rozwiązane dziś (automatycznie)
- [x] [Reminder] - powód: [np. odpowiedź wysłana 2026-07-26]

## Na czym się skupić

1. **[Obszar 1]**: [uzasadnienie]
2. **[Obszar 2]**: [uzasadnienie]

## Do decyzji

> Rzeczy, których nie wolno mi było rozstrzygnąć autonomicznie. Nic tu nie czeka na odpowiedź w czacie - to lista do Twojego przejrzenia.

- [ ] [Propozycja wydarzenia w kalendarzu: termin + kontekst - do ręcznego utworzenia]
- [ ] [Niejednoznaczne przypomnienie: stan wątku + co bym zrobił]
- [ ] [Sterta AI/Triage: X wątków → `/email-triage`]
- [ ] [Luka kontekstowa: pojęcie/dokument, gdzie na nie trafiłem, czemu jest istotne]

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

[Jeśli sam oznaczyłem coś jako rozwiązane:]
**Zamknięte automatycznie:** [Temat] - [powód, np. odpowiedź poszła 26.07]

[Jeśli zostały niejednoznaczne zaległe:]
**Do weryfikacji z poprzednich dni:**
1. **[Temat]** (z [data]) - [krótki kontekst]
   → Sprawdziłem wątek: [status - czy jest nowa aktywność] → zostawiam otwarte, jest w „Do decyzji"

#### Sugerowane obszary fokusowe
1. **[Obszar 1]** - [uzasadnienie]
2. **[Obszar 2]** - [uzasadnienie]

#### Do decyzji
- [Otwarte kwestie - bez pytań, do przejrzenia]

---
*Dashboard zapisany: `Inbox/Dashboard-[date].md`*
```

## Obsługa przypomnień

### Oznaczanie jako rozwiązane (autonomicznie, bez pytania)

Briefing **nie pyta** „które oznaczyć jako załatwione" - nikt nie musi odpowiadać, bo rutyna bywa uruchamiana z harmonogramu. Decydujesz sam, na podstawie sprawdzonego wątku:

**Zamykasz przypomnienie**, gdy dowód jest jednoznaczny:
- w wątku jest moja odpowiedź wysłana po dacie przypomnienia,
- druga strona potwierdziła załatwienie sprawy,
- powiązany task Todoist jest ukończony (`fetch-object`),
- wątek ma już `Nieaktualne`.

Wtedy:
1. Przeczytaj `Asystent/Memory/EmailReminders.md`
2. Przenieś przypomnienie do sekcji "Rozwiązane"
3. Dodaj datę rozwiązania, przekreślenie i **powód** ("odpowiedź wysłana 2026-07-26")
4. Zapisz zaktualizowany plik

**Zostawiasz otwarte** (i wypisujesz w "Do decyzji"), gdy dowodu brak albo jest niejednoznaczny. Nigdy nie zamykaj przypomnienia „bo minęło dużo czasu".

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
- **Nie zadawaj pytań i nie czekaj na odpowiedź** - briefing bywa uruchamiany z harmonogramu (`/do-your-job`, 8:00 pon-pt), gdzie nikogo nie ma po drugiej stronie. Wszystko otwarte → sekcja **„Do decyzji"** w Dashboardzie.
- **Luka kontekstowa** (protokół CLAUDE.md „Luki kontekstowe"): nieznany uczestnik spotkania / projekt / skrót w kalendarzu, zadaniach lub mailu → najpierw `qmd`/`Read` digital twina. Jeśli dalej niejasne — **nie blokuj briefingu**: zapisz do pamięci to, co już wiadomo, a samą lukę wypisz w „Do decyzji" (nazwij pojęcie/dokument, gdzie na nie trafiłeś i czemu jest istotne), żeby dało się ją domknąć przy najbliższej interaktywnej sesji.
