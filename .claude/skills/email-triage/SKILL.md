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

Mechanikę nakładania labelek/draftów stosuj jak w `/email-review`. Status `AI/Done`/`AI/Triage` ustawiasz **wyłącznie** parametrem `status: "done"|"triage"` w `update_thread` (rozłączne; MCP zdejmuje przeciwny status i `AI/Defer/*`) — nigdy ręcznie przez addLabels/removeLabels (MCP odrzuci).

## ⚠️ Podwójne opt-in — NIC nie zapisuj bez wyraźnej zgody

To jest najważniejsza zasada tego skilla. Żadna zmiana reguły ani akcja na mailach nie dzieje się "z marszu":

1. **Opt-in #1 — decyzja.** Użytkownik mówi, co zrobić z grupą (wybór w `AskUserQuestion` lub własnymi słowami).
2. **Echo + propozycja.** Powtórz **konkretnie, co zrozumiałeś**: dokładny wiersz reguły do dodania/edycji ORAZ dokładne akcje na mailach (które labele na które wątki, ew. draft, archiwizacja, `status:"done"` — MCP sam zdejmie `AI/Triage`). **Zakończ turę i czekaj — nic nie zapisuj.**
3. **Opt-in #2 — wyraźna akceptacja.** Zapisz regułę i wykonaj akcje **tylko** gdy użytkownik wyraźnie zaakceptuje ("OK / akceptuję / rób tak"). **Każda inna odpowiedź to feedback, nie zgoda** — nanieś poprawki, przedstaw propozycję ponownie (krok 2) i znów czekaj. Pętla aż do wyraźnego "tak".

Gwarancja: "powiedziałeś X → robię dokładnie X (potwierdzone), nigdy po cichu Y". Feedback ≠ koniec.

## Narzędzia

| Operacja | Narzędzie |
|----------|-----------|
| Pobranie sterty triażu | `mcp__gmail__search_threads` (`filter:"triage"`) |
| Dojrzałe defery (opcjonalnie) | `mcp__gmail__search_threads` (`filter:"defer-due"`) |
| Treść wątku | `mcp__gmail__get_thread` |
| Status (AI/Done\|AI/Triage) / labele / draft | `mcp__gmail__update_thread` (status: "done"\|"triage" dla statusu; addLabels/removeLabels dla kategorii), `mcp__gmail__create_draft` |
| Odłożenie z datą | `mcp__gmail__defer_thread` (until=`RRRR-MM-DD`) |
| Archiwizacja (Śmieci/Nieaktualne) | `mcp__gmail__update_thread` z `addLabels:["Nieaktualne"\|"Śmieci", …]` — MCP zdejmuje INBOX |
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

**Maile wysłane:** nie trafiają już do `AI/Triage` (obsługuje je lekka ścieżka w `/email-review`). Jeśli któryś wątek historycznie tu jest, a jego najnowsza wiadomość jest od użytkownika (`kedrzu@gmail.com` / `kedrzu@sigma.clinic`) → potraktuj lekką ścieżką: `update_thread(status:"done", priority: …)` (MCP zdejmie `AI/Triage`), ew. dopisz reminder/wiedzę. **Nie** twórz dla niego reguły.

## Proces

### 1. Wczytaj kontekst
- Rulebook obu kont (`Read`).
- (Best-effort) `Asystent/Memory/InboxReviewState.md` — tabela Priority/Triage Emails zawiera **powód triażu** zapisany przez `/email-review`; użyj go, żeby nie zgadywać od zera.

### 2. Digest sterty (subagenci Sonnet, read-only)
Podziel stertę na batche (~5-8 wątków) i zleć **subagentom na Sonnecie** *tylko odczyt i streszczenie*. Subagent dla każdego wątku zwraca: `{nadawca, krótkie streszczenie, proponowana akcja wg rulebooka, czemu niepewne, klucz grupy (domena/nadawca+wzorzec tematu), czy użytkownik już ręcznie obsłużył}`. **Subagent niczego nie modyfikuje.**

### 3. Wątki już obsłużone ręcznie
Jeśli digest pokazuje, że użytkownik już zadziałał od czasu triażu (nowa wiadomość wysłana przez niego / wątek opuścił INBOX / dodany nie-AI label):
- Posprzątaj status: `update_thread(status:"done", priority: …)` — MCP zdejmie `AI/Triage`.
- Z tego, co użytkownik zrobił, **zaproponuj regułę** — ale przez **podwójne opt-in** (to nadal sugestia, nie auto-zapis).

### 4. Pętla triażu (zbieraj i pytaj grupami)
- Zbierz digesty i **pogrupuj po kluczu, na którym oprze się reguła** (domena nadawcy / nadawca + wzorzec tematu).
- Dla każdej grupy zadaj **jedno** `AskUserQuestion` o decyzję (opt-in #1): proponowana akcja jako opcja domyślna (ze słownika akcji rulebooka) + "jak szeroko?" (ten nadawca / cała domena / ten typ). Decydując raz dla grupy, ogarniasz wiele maili naraz. Wśród opcji (gdy pasuje do grupy) uwzględnij: **„Odłóż do <data> (Defer)"** — mail dziś OK, zdezaktualizuje się później (event/deadline/oferta) — **„Oznacz Nieaktualne (archiwizuj, zostaw do referencji)"**, **„Śmieci (archiwizuj, bezpieczny do usunięcia)"** oraz **„Nieaktualne + Śmieci"** (nieaktualny i bezwartościowy). Patrz sekcja „Defer i Nieaktualne".
- Po decyzji → **echo + propozycja** (opt-in #2, sekcja wyżej) i czekaj na wyraźną zgodę.

### 5. Commit (dopiero po opt-in #2)
- **Reguła**: dopisz lub **zedytuj w miejscu** pasujący wiersz `| Typ | Akcja |` w `EmailWorkflow-{konto}.md`. Najpierw poszukaj istniejącego wiersza o tym samym wzorcu Typ — jeśli jest, edytuj go (nie duplikuj). Zaktualizuj datę "Ostatnia aktualizacja" na górze pliku. (Bez osobnego dziennika zmian.)
- **Maile**: nałóż uzgodnioną akcję na **każdy** wątek w grupie — labele kategorii/draft/archiwizacja wg reguły — potem **zawsze** oznacz jako done przez `update_thread(status:"done", priority: …)` (MCP nakłada `AI/Done` i **sam zdejmuje `AI/Triage`** oraz `AI/Defer/*`; nie podawaj tych labelek ręcznie — odrzuci). **Zawsze nadaj priorytet** — `priority: P0..P3` (poziomy → sekcja „Priorytety" rulebooka). MCP **wymaga** priorytetu przy każdym `AI/Done`. **Archiwizacja**: wątek opuszcza INBOX **wyłącznie** gdy dostaje marker `Śmieci` i/lub `Nieaktualne` w `addLabels` — MCP sam zdejmuje INBOX. Markery nakładaj na kategorię (np. `Zakupy`+`Śmieci`); sama kategoria nie archiwizuje (MCP odrzuci `removeLabels:["INBOX"]` bez markera). Dla decyzji **Defer** użyj `defer_thread(threadId, until, priority)` (nakłada `AI/Defer/<data>` + `AI/Done` + `P/<n>`, zdejmuje `AI/Triage`); dla **Nieaktualne** użyj `update_thread(status:"done", addLabels:["Nieaktualne", …kategoria; +"Śmieci" jeśli reguła], priority)` (Nieaktualne + `AI/Done` + `P/<n>` + archiwum + zdjęcie `AI/Triage`) — **oba wymagają priorytetu** (śmieci/Nieaktualne zwykle P3). Sterta `AI/Triage` ma realnie maleć po sesji, nie tylko rosnąć rulebook. Masowe nałożenie na grupę możesz zlecić subagentowi Sonnet. Tylko wątki świadomie odłożone (bez decyzji) zostają w `AI/Triage`.

### 6. Pamięć
Po sesji skomituj aktualizacje digital twin jak w `/email-review` (kontakty: `ostatni_kontakt` + historia; Projects/Work/Personal/Timeline/Insights gdy maile coś ujawniły).

## Format reguły (rulebook)

Reguły to sekcje `### Kategoria` z tabelą `| Typ | Akcja |`. Akcję buduj ze słownika rulebooka, np.:

```markdown
### <Kategoria>
| Typ | Akcja |
|-----|-------|
| <wzorzec nadawcy/tematu> | <Label> + [archiwizuj] + [P/0..P/3] + [IMPORTANT] + AI/Done |
```

Trzymaj się istniejących nazw labelek i konwencji akcji z danego rulebooka. Reguła klasyfikująca wątek przychodzący powinna wskazywać priorytet (`P/0..P/3`); reguła archiwizująca (`archiwizuj`) musi wskazywać etykietę-kubełek użytkownika (nie sam `CATEGORY_*`).

**Słownik akcji dla maili z datą ważności** (do reguł i akcji):
- `Defer:<efektywna data>` — odłóż do daty efektywnej (event/deadline/oferta); brak konkretnej daty → +14 dni. Wykonanie: `defer_thread`.
- `Nieaktualne [+ Śmieci] + archiwizuj` — mail nieaktualny (zostaw do referencji) lub nieaktualny i bezpieczny do usunięcia (+`Śmieci`). Wykonanie: `update_thread(status:"done", addLabels:[…], priority)` — MCP archiwizuje.
- `Śmieci + archiwizuj` — bezpieczny do usunięcia, bez wartości na przyszłość (marker, nie usuwamy). Wykonanie: `update_thread(status:"done", addLabels:["Śmieci", …kategoria], priority)`.

## Defer i Nieaktualne

- **Defer** = odłożenie wątku z **efektywną datą** (`defer_thread`): MCP nakłada `AI/Defer/<data>` + `AI/Done`, wątek wraca do oceny dopiero gdy data minie (przez `filter:"defer-due"`). Daje to regułę typu „ten newsletter eventowy → odłóż do daty eventu".
- **Nieaktualne** = stan terminalny (`update_thread` z `addLabels:["Nieaktualne", …]`): mail stracił aktualność — archiwizujemy (MCP zdejmuje INBOX); zostawiamy do referencji, a jeśli też bezwartościowy → dodaj `Śmieci`.
- **Dojrzałe defery**: opcjonalnie możesz wciągnąć `filter:"defer-due"` (wątki, których data minęła) i przejść je tak jak stertę triażu — decyzja per grupa: re-defer na nową datę / Nieaktualne / obsłuż / zostaw. Te same opcje w `AskUserQuestion`.

## Akcje → Todoist i Faktury → Rachunki (przez opt-in)

Te same mechanizmy co w `/email-review`, ale **przez podwójne opt-in** — nic bez wyraźnej zgody:

- **Akcje → Todoist** (rulebook „Akcje → Todoist"): dla wątku, który ma dostać `Wymaga działania`/`Wymaga odpowiedzi`, w echo+propozycji pokaż też, że utworzysz **task Todoist** (treść, projekt/sekcja wg konta, priorytet p1..p4, ew. `deadlineDate`) + labelkę `TODO/<id>` + defer. Wykonaj dopiero po „OK". Dojrzałe defery z `TODO/<id>` re-oceniaj wg re-checku (`fetch-object`/`find-completed-tasks` → COMPLETED → `update_thread(status:"done", addLabels:["Nieaktualne"], priority)`; OPEN → re-defer; GONE → zostaw w triażu) — też proponuj, nie rób z marszu.
- **Faktury → Rachunki** (rulebook „Faktury → folder Rachunki"): gdy faktura trwałego dobra >100 zł, zaproponuj zapis PDF + notatki do `./obsidian/Rachunki/`; zapisuj dopiero po akceptacji.

## Format wyjścia

### Podsumowanie triażu
- **Przetworzone:** N wątków w M grupach
- **Nowe/zmienione reguły:** lista (Typ → Akcja, konto)
- **Akcje na mailach:** labele/drafty/archiwizacje, priorytety (P0/P1/P2/P3), ile `AI/Triage` → `AI/Done` (zdjęty triage), ile Defer / Nieaktualne
- **Pozostało w triażu:** ile wątków zostało w `AI/Triage` (tylko świadomie odłożone)

## Bezpieczeństwo

- **Podwójne opt-in** na każdą zmianę reguły i akcję — patrz sekcja wyżej. Feedback ≠ zgoda.
- **Nigdy nie wysyłaj** maili — tylko drafty.
- **Nigdy nie usuwaj** maili/zadań/wydarzeń/notatek.
- Maile zostają w `AI/Triage` dopóki użytkownik nie zaakceptuje akcji. **Po akceptacji zawsze `update_thread(status:"done", …)`** (MCP zdejmie `AI/Triage`) — obsłużony wątek nie może zostać w stercie triażu.
- Komunikuj po polsku.
