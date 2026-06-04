---
name: email-triage
description: Interaktywne przejście przez stertę AI/Triage (maile, co do których automat był niepewny) RAZEM z użytkownikiem - wspólnie decydujecie jak je obsłużyć, agent wykonuje akcje na tych mailach ORAZ dopisuje nowe reguły do rulebooka EmailWorkflow, żeby następnym razem /email-review ogarnął je sam. Użyj, gdy użytkownik chce "rozkminić / wyczyścić stertę triażu", "poprawić reguły maili", "przejść przez niepewne maile razem", albo pyta "czemu to oznaczyłeś do triażu". To narzędzie do poprawiania automatyzacji - NIE do codziennego nadrabiania skrzynki (to /email-review).
---

# Email Triage

Interaktywne czyszczenie sterty `AI/Triage` — maili, których `/email-review` nie umiał obsłużyć jednoznacznie. Przechodzicie je **razem**: agent proponuje, użytkownik decyduje, a każda decyzja zamienia się w (1) **akcję na mailach** i (2) **nową/zaktualizowaną regułę** w rulebooku. Efekt: następne `/email-review` obsługuje ten wzorzec sam, a sterta triażu maleje.

## Zasada działania

**Rulebook = źródło reguł**, ten skill je **rozszerza**:
- `./obsidian/Asystent/Memory/EmailWorkflow-Personal.md` (kedrzu@gmail.com)
- `./obsidian/Asystent/Memory/EmailWorkflow-Work.md` (kedrzu@sigma.clinic)

Mechanikę nakładania labelek/draftów stosuj jak w `/email-review` (ta sama konwencja `AI/Done`/`AI/Triage`).

## ⚠️ Podwójne opt-in — NIC nie zapisuj bez wyraźnej zgody

To jest najważniejsza zasada tego skilla. Żadna zmiana reguły ani akcja na mailach nie dzieje się "z marszu":

1. **Opt-in #1 — decyzja.** Użytkownik mówi, co zrobić z grupą (wybór w `AskUserQuestion` lub własnymi słowami).
2. **Echo + propozycja.** Powtórz **konkretnie, co zrozumiałeś**: dokładny wiersz reguły do dodania/edycji ORAZ dokładne akcje na mailach (które labele na które wątki, ew. draft, archiwizacja, `AI/Done`/zdjęcie `AI/Triage`). **Zakończ turę i czekaj — nic nie zapisuj.**
3. **Opt-in #2 — wyraźna akceptacja.** Zapisz regułę i wykonaj akcje **tylko** gdy użytkownik wyraźnie zaakceptuje ("OK / akceptuję / rób tak"). **Każda inna odpowiedź to feedback, nie zgoda** — nanieś poprawki, przedstaw propozycję ponownie (krok 2) i znów czekaj. Pętla aż do wyraźnego "tak".

Gwarancja: "powiedziałeś X → robię dokładnie X (potwierdzone), nigdy po cichu Y". Feedback ≠ koniec.

## Narzędzia

| Operacja | Narzędzie |
|----------|-----------|
| Pobranie sterty triażu | `mcp__gmail__search_threads` (`filter:"triage"`) |
| Treść wątku | `mcp__gmail__get_thread` |
| Labele / draft | `mcp__gmail__update_thread`, `mcp__gmail__create_draft` |
| Pytania do użytkownika | `AskUserQuestion` |
| Czytanie/zapis rulebooka | `Read`, `Edit` |
| Szukanie kontaktów | `qmd` (MCP) |
| Digest batcha | `Agent` (`model: "sonnet"`) |

Konta: Personal = kedrzu@gmail.com, Work = kedrzu@sigma.clinic.

## Wejście: sterta AI/Triage

```
mcp__gmail__search_threads(account: <konto>, query: "in:inbox", filter: "triage")
```

Tylko sterta `AI/Triage` — ten skill **nie** przetwarza świeżych nieprzetworzonych maili (od tego jest `/email-review`).

**Maile wysłane:** nie trafiają już do `AI/Triage` (obsługuje je lekka ścieżka w `/email-review`). Jeśli któryś wątek historycznie tu jest, a jego najnowsza wiadomość jest od użytkownika (`kedrzu@gmail.com` / `kedrzu@sigma.clinic`) → potraktuj lekką ścieżką: zdejmij `AI/Triage`, dodaj `AI/Done`, ew. dopisz reminder/wiedzę. **Nie** twórz dla niego reguły.

## Proces

### 1. Wczytaj kontekst
- Rulebook obu kont (`Read`).
- (Best-effort) `Asystent/Memory/InboxReviewState.md` — tabela Priority/Triage Emails zawiera **powód triażu** zapisany przez `/email-review`; użyj go, żeby nie zgadywać od zera.

### 2. Digest sterty (subagenci Sonnet, read-only)
Podziel stertę na batche (~5-8 wątków) i zleć **subagentom na Sonnecie** *tylko odczyt i streszczenie*. Subagent dla każdego wątku zwraca: `{nadawca, krótkie streszczenie, proponowana akcja wg rulebooka, czemu niepewne, klucz grupy (domena/nadawca+wzorzec tematu), czy użytkownik już ręcznie obsłużył}`. **Subagent niczego nie modyfikuje.**

### 3. Wątki już obsłużone ręcznie
Jeśli digest pokazuje, że użytkownik już zadziałał od czasu triażu (nowa wiadomość wysłana przez niego / wątek opuścił INBOX / dodany nie-AI label):
- Posprzątaj status: zdejmij `AI/Triage`, dodaj `AI/Done`.
- Z tego, co użytkownik zrobił, **zaproponuj regułę** — ale przez **podwójne opt-in** (to nadal sugestia, nie auto-zapis).

### 4. Pętla triażu (zbieraj i pytaj grupami)
- Zbierz digesty i **pogrupuj po kluczu, na którym oprze się reguła** (domena nadawcy / nadawca + wzorzec tematu).
- Dla każdej grupy zadaj **jedno** `AskUserQuestion` o decyzję (opt-in #1): proponowana akcja jako opcja domyślna (ze słownika akcji rulebooka) + "jak szeroko?" (ten nadawca / cała domena / ten typ). Decydując raz dla grupy, ogarniasz wiele maili naraz.
- Po decyzji → **echo + propozycja** (opt-in #2, sekcja wyżej) i czekaj na wyraźną zgodę.

### 5. Commit (dopiero po opt-in #2)
- **Reguła**: dopisz lub **zedytuj w miejscu** pasujący wiersz `| Typ | Akcja |` w `EmailWorkflow-{konto}.md`. Najpierw poszukaj istniejącego wiersza o tym samym wzorcu Typ — jeśli jest, edytuj go (nie duplikuj). Zaktualizuj datę "Ostatnia aktualizacja" na górze pliku. (Bez osobnego dziennika zmian.)
- **Maile**: nałóż uzgodnioną akcję na **każdy** wątek w grupie — labele/draft/archiwizacja wg reguły — potem **zawsze** `AI/Done` + **zdejmij `AI/Triage`** (`addLabels:["AI/Done"]`, `removeLabels:["AI/Triage"]`). Sterta `AI/Triage` ma realnie maleć po sesji, nie tylko rosnąć rulebook. Masowe nałożenie na grupę możesz zlecić subagentowi Sonnet. Tylko wątki świadomie odłożone (bez decyzji) zostają w `AI/Triage`.

### 6. Pamięć
Po sesji skomituj aktualizacje digital twin jak w `/email-review` (kontakty: `ostatni_kontakt` + historia; Projects/Work/Personal/Timeline/Insights gdy maile coś ujawniły).

## Format reguły (rulebook)

Reguły to sekcje `### Kategoria` z tabelą `| Typ | Akcja |`. Akcję buduj ze słownika rulebooka, np.:

```markdown
### <Kategoria>
| Typ | Akcja |
|-----|-------|
| <wzorzec nadawcy/tematu> | <Label> + [archiwizuj] + [IMPORTANT] + AI/Done |
```

Trzymaj się istniejących nazw labelek i konwencji akcji z danego rulebooka.

## Format wyjścia

### Podsumowanie triażu
- **Przetworzone:** N wątków w M grupach
- **Nowe/zmienione reguły:** lista (Typ → Akcja, konto)
- **Akcje na mailach:** labele/drafty/archiwizacje, ile `AI/Triage` → `AI/Done` (zdjęty triage)
- **Pozostało w triażu:** ile wątków zostało w `AI/Triage` (tylko świadomie odłożone)

## Bezpieczeństwo

- **Podwójne opt-in** na każdą zmianę reguły i akcję — patrz sekcja wyżej. Feedback ≠ zgoda.
- **Nigdy nie wysyłaj** maili — tylko drafty.
- **Nigdy nie usuwaj** maili/zadań/wydarzeń/notatek.
- Maile zostają w `AI/Triage` dopóki użytkownik nie zaakceptuje akcji. **Po akceptacji zawsze zdejmij `AI/Triage` i nałóż `AI/Done`** — obsłużony wątek nie może zostać w stercie triażu.
- Komunikuj po polsku.
