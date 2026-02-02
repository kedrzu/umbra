---
name: email-analysis
description: Analyze email patterns across accounts and help design labeling/workflow strategy. Use this to understand email types, frequencies, and propose organization systems. Run separately for personal vs work accounts.
---

# Email Analysis

Przeanalizuj wzorce emaili i pomóż zaprojektować strategię workflow.

## MCP Tools Used

| Operation | Tool |
|-----------|------|
| Search emails | `search_threads` |
| Read thread content | `get_thread` |
| Read memory | `read_note` |
| Save workflow | `create_ai_note` |

## Gmail Accounts

| Account | Email |
|---------|-------|
| Personal | kedrzu@gmail.com |
| Work | kedrzu@sigma.clinic |

## Cel

Strategia labelowania i obsługi emaili nie jest jeszcze zdefiniowana. Ten skill pomoże:
1. Zrozumieć jakie typy emaili przychodzą na każde konto
2. Zidentyfikować wzorce i kategorie
3. Zaproponować system labelowania
4. Zaprojektować workflow dostosowany do każdego konta

## Proces

### Krok 1: Zbierz dane

Dla wybranego konta (personal lub work):

1. **Pobierz próbkę emaili** z ostatnich 30-90 dni
   - Użyj różnych query: `is:inbox`, `is:sent`, `is:important`
   - Zbierz minimum 100-200 wątków dla statystycznie znaczącej próbki

2. **Przeanalizuj nadawców**
   - Top 20 najczęstszych nadawców
   - Kategoryzacja: osoby vs firmy vs automatyczne
   - Częstotliwość kontaktu

3. **Przeanalizuj treść**
   - Typy wiadomości (newsletter, transakcyjne, osobiste, projekty)
   - Długość wątków
   - Załączniki

### Krok 2: Zidentyfikuj wzorce

1. **Kategorie naturalne**
   - Jakie grupy emaili się wyłaniają?
   - Co wymaga natychmiastowej reakcji vs co może poczekać?
   - Co jest informacyjne vs wymaga akcji?

2. **Wzorce czasowe**
   - Kiedy przychodzi najwięcej emaili?
   - Ile emaili dziennie/tygodniowo?
   - Sezonowość?

3. **Priorytety**
   - Które emaile użytkownik otwiera od razu?
   - Które są ignorowane?
   - Co trafia do spamu vs co jest wartościowe?

### Krok 3: Zaproponuj strategię

Na podstawie analizy zaproponuj:

1. **System labelów**
   ```
   Przykład dla konta osobistego:
   - @Pilne
   - @Do-odpowiedzi
   - @Czekam-na-odpowiedź
   - Finanse/
   - Zakupy/
   - Rodzina/
   - Subskrypcje/
   ```

2. **Reguły automatyczne**
   - Które emaile powinny być auto-labelowane?
   - Co można od razu archiwizować?
   - Co powinno trafiać do priorytetu?

3. **Workflow codzienny**
   - Jak często przeglądać inbox?
   - Kolejność przetwarzania
   - Zasady odpowiadania

### Krok 4: Iteruj

1. Przedstaw propozycję użytkownikowi
2. Zbierz feedback
3. Dostosuj strategię
4. Użyj `create_ai_note` aby zapisać finalną strategię w `AI/Memory/EmailWorkflow-[account].md`

**Ważne**: Workflow zapisany w `AI/Memory/EmailWorkflow-[account].md` będzie automatycznie używany przez `/inbox-review` do labelowania i kategoryzacji emaili. Po zakończeniu analizy, uruchom `/inbox-review` aby zobaczyć strategię w akcji.

## Format wyjściowy

### Analiza konta: [Personal/Work]

#### Statystyki (ostatnie [X] dni)
| Metryka | Wartość |
|---------|---------|
| Łączna liczba emaili | X |
| Średnio dziennie | X |
| Nieprzeczytane | X |
| Wątki z odpowiedzią | X% |

#### Top nadawcy
| Nadawca | Liczba | Typ | Priorytet |
|---------|--------|-----|-----------|
| ... | ... | ... | ... |

#### Zidentyfikowane kategorie
1. **[Kategoria 1]** (~X% emaili)
   - Charakterystyka: ...
   - Przykłady nadawców: ...
   - Sugerowana akcja: ...

2. **[Kategoria 2]** ...

#### Proponowany system labelów
```
[Hierarchia labelów]
```

#### Proponowany workflow
1. [Krok 1]
2. [Krok 2]
...

#### Pytania do użytkownika
- [Pytanie o preferencje]
- [Pytanie o priorytety]

---

## Ważne

- **Analizuj konta osobno** - workflow personal i work będzie zupełnie inny
- **Bądź interaktywny** - pytaj o preferencje, nie narzucaj rozwiązań
- **Zapisuj wnioski** - każda analiza powinna być zapisana w AI/Memory/
- **Iteruj** - to proces, nie jednorazowa akcja
- **Komunikuj po polsku**
