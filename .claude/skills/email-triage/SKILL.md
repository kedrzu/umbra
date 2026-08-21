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

Mechanikę nakładania labelek/draftów stosuj jak w `/email-review`. Status `AI/Done`/`AI/Triage` ustawiasz **wyłącznie** parametrem `status: "done"|"triage"` w `update_thread` (rozłączne; MCP zdejmuje przeciwny status) — nigdy ręcznie przez addLabels/removeLabels (MCP odrzuci). Odłożenia, powiązania z zadaniami i przypomnienia trzyma **rejestr** (`scripts/ledger.py`, kontrakt w `docs/ledger.md`), nie labelki.

## ⚠️ Podwójne opt-in — TYLKO na zmianę reguły rulebooka

Opt-in dotyczy **wyłącznie zapisu/edycji reguły** w rulebooku (i akcji nierozerwalnie związanej z tą nową, dopiero uczoną regułą). **Akcje na mailach objętych istniejącymi regułami są autonomiczne** — nakładaj labele, twórz i aktualizuj zadania, odkładaj, archiwizuj i sprawdzaj stan zadań (programowo przez `todoist.py sync`) **bez pytania**. Triaż służy **uczeniu nowych reguł** dla maili, które nie wpadają w żaden sensowny workflow — **nie** odpytywaniu użytkownika o każdy mail „czy załatwione".

Gdy mail **nie pasuje** do żadnej reguły i chcesz nauczyć nową:

1. **Opt-in #1 — decyzja.** Użytkownik mówi, jak obsłużyć grupę (wybór w `AskUserQuestion` lub własnymi słowami).
2. **Echo + propozycja reguły.** Powtórz **konkretnie**: dokładny wiersz reguły do dodania/edycji oraz jak zostanie zastosowana do grupy. **Zakończ turę i czekaj — reguły nie zapisuj.**
3. **Opt-in #2 — wyraźna akceptacja.** Zapisz regułę (i wykonaj akcje na grupie) **tylko** gdy użytkownik wyraźnie zaakceptuje ("OK / akceptuję / rób tak"). **Każda inna odpowiedź to feedback, nie zgoda** — nanieś poprawki, przedstaw ponownie (krok 2) i znów czekaj.

Gwarancja: zmiana **reguły** = "powiedziałeś X → zapisuję dokładnie X (potwierdzone)". Feedback ≠ koniec. Sama akcja na mailu wg istniejącej reguły zgody nie wymaga.

## Narzędzia

| Operacja | Narzędzie |
|----------|-----------|
| Pobranie sterty triażu | `mcp__gmail__search_threads` (`filter:"triage"`) |
| Dojrzałe sprawy (opcjonalnie) | `Bash(python3 scripts/ledger.py due …)` |
| Treść wątku (labelki jako nazwy) | `mcp__gmail__get_thread` |
| Wyszukiwanie referencyjne (cała poczta) | `mcp__gmail__search_threads` **bez** `filter` (inbox + archiwum + `AI/Done`) |
| Status (AI/Done\|AI/Triage) / labele / draft | `mcp__gmail__update_thread` (status: "done"\|"triage" dla statusu; addLabels/removeLabels dla kategorii), `mcp__gmail__create_draft` |
| Odłożenie z datą | `update_thread(status:"done", priority)` + rekord w rejestrze (`ledger upsert`) |
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
Podziel stertę na batche (~5-8 wątków) i zleć **subagentom na Sonnecie** *tylko odczyt i streszczenie*. Subagent dla każdego wątku zwraca: `{nadawca, krótkie streszczenie, proponowana akcja wg rulebooka, **czy pasuje do istniejącej reguły**, czemu niepewne, klucz grupy (domena/nadawca+wzorzec tematu), czy użytkownik już ręcznie obsłużył}`. **Subagent niczego nie modyfikuje.**

### 3. Obsłuż autonomicznie to, co da się obsłużyć (bez pytania)
Zanim zaczniesz pytać użytkownika, ogarnij sam wszystko, co **nie wymaga** uczenia nowej reguły:
- **Wątek pasuje do istniejącej reguły** (digest tak wskazuje) → zastosuj ją od razu: labele/task/defer/archiwizacja + `update_thread(status:"done", priority)`. Bez opt-in.
- **Użytkownik już zadziałał ręcznie** (nowa wiadomość wysłana przez niego / wątek opuścił INBOX / dodany nie-AI label) → posprzątaj status: `update_thread(status:"done", priority: …)` (MCP zdejmie `AI/Triage`). Jeśli z tego, co zrobił, **wyłania się nowa reguła** → zaproponuj ją przez podwójne opt-in (krok 4); sam zapis statusu jest autonomiczny.
- **Wątek należy do sprawy z rejestru** (`ledger query --ref <threadId>`) → stan zadania ustalaj **programowo**, nie pytaniem: `python3 scripts/todoist.py sync` → zadanie w `completed`/`stale_links` (pozycje `completed` niosą też `comments` i `changes` — przerób je jak w `/email-review`, sekcja „Żniwo wiedzy z ukończonych zadań”: instrukcja na przyszłość → reguła rulebooka z cytatem źródłowym, fakt → pamięć, niejasny zakres → do decyzji z użytkownikiem) → `update_thread(status:"done", addLabels:["Nieaktualne"], priority)` + `ledger close --outcome completed`; zadanie otwarte → nowe `due` w rekordzie; zadanie usunięte → zostaw w triażu z notką.

Do kroku 4 trafiają **tylko** wątki, które nie pasują do żadnej reguły — bo to dla nich uczymy nową regułę.

### 4. Pętla nauki reguł (zbieraj i pytaj grupami — tylko wątki bez reguły)
- Zbierz pozostałe digesty i **pogrupuj po kluczu, na którym oprze się reguła** (domena nadawcy / nadawca + wzorzec tematu).
- Dla każdej grupy zadaj **jedno** `AskUserQuestion` o decyzję (opt-in #1): proponowana akcja jako opcja domyślna (ze słownika akcji rulebooka) + "jak szeroko?" (ten nadawca / cała domena / ten typ). Decydując raz dla grupy, ogarniasz wiele maili naraz. Wśród opcji (gdy pasuje do grupy) uwzględnij: **„Odłóż do <data> (Defer)"** — mail dziś OK, zdezaktualizuje się później (event/deadline/oferta) — **„Oznacz Nieaktualne (archiwizuj, zostaw do referencji)"**, **„Śmieci (archiwizuj, bezpieczny do usunięcia)"** oraz **„Nieaktualne + Śmieci"** (nieaktualny i bezwartościowy). Patrz sekcja „Defer i Nieaktualne".
- Po decyzji → **echo + propozycja** (opt-in #2, sekcja wyżej) i czekaj na wyraźną zgodę.

### 5. Commit (dopiero po opt-in #2)
- **Reguła**: dopisz lub **zedytuj w miejscu** pasujący wiersz `| Typ | Akcja |` w `EmailWorkflow-{konto}.md`. Najpierw poszukaj istniejącego wiersza o tym samym wzorcu Typ — jeśli jest, edytuj go (nie duplikuj). Zaktualizuj datę "Ostatnia aktualizacja" na górze pliku. (Bez osobnego dziennika zmian.)
- **Maile**: nałóż uzgodnioną akcję na **każdy** wątek w grupie — labele kategorii/draft/archiwizacja wg reguły — potem **zawsze** oznacz jako done przez `update_thread(status:"done", priority: …)` (MCP nakłada `AI/Done` i **sam zdejmuje `AI/Triage`**; nie podawaj tych labelek ręcznie — odrzuci). **Zawsze nadaj priorytet** — `priority: P0..P3` (poziomy → sekcja „Priorytety" rulebooka). MCP **wymaga** priorytetu przy każdym `AI/Done`. **Archiwizacja**: wątek opuszcza INBOX **wyłącznie** gdy dostaje marker `Śmieci` i/lub `Nieaktualne` w `addLabels` — MCP sam zdejmuje INBOX. Markery nakładaj na kategorię (np. `Zakupy`+`Śmieci`); sama kategoria nie archiwizuje (MCP odrzuci `removeLabels:["INBOX"]` bez markera). Dla decyzji **Odłóż** użyj `update_thread(status:"done", priority)` **plus** rekordu w rejestrze (`ledger upsert` z `due` i `reason` — wątek zostaje w INBOX i wraca, gdy data minie); dla **Nieaktualne** użyj `update_thread(status:"done", addLabels:["Nieaktualne", …kategoria; +"Śmieci" jeśli reguła], priority)` (Nieaktualne + `AI/Done` + `P/<n>` + archiwum + zdjęcie `AI/Triage`) — **oba wymagają priorytetu** (śmieci/Nieaktualne zwykle P3). Sterta `AI/Triage` ma realnie maleć po sesji, nie tylko rosnąć rulebook. Masowe nałożenie na grupę możesz zlecić subagentowi Sonnet. Tylko wątki świadomie odłożone (bez decyzji) zostają w `AI/Triage`.

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
- `Odłóż:<efektywna data>` — odłóż do daty efektywnej (event/deadline/oferta); brak konkretnej daty → +14 dni. Wykonanie: `update_thread(status:"done", priority)` + rekord w rejestrze z `due` i `reason`.
- `Nieaktualne [+ Śmieci] + archiwizuj` — mail nieaktualny (zostaw do referencji) lub nieaktualny i bezpieczny do usunięcia (+`Śmieci`). Wykonanie: `update_thread(status:"done", addLabels:[…], priority)` — MCP archiwizuje.
- `Śmieci + archiwizuj` — bezpieczny do usunięcia, bez wartości na przyszłość (marker, nie usuwamy). Wykonanie: `update_thread(status:"done", addLabels:["Śmieci", …kategoria], priority)`.

## Odkładanie i Nieaktualne

- **Odłożenie** = `update_thread(status:"done", priority)` (wątek znika z `unprocessed`, zostaje w INBOX) **plus** rekord w rejestrze z `due` i `reason`. Wraca do oceny dopiero gdy data minie (przez `ledger due`). Daje to regułę typu „ten newsletter eventowy → odłóż do daty eventu". `reason` ma mówić **po co** wraca — to on trafia potem do subagenta zamiast zgadywania z treści.
- **Nieaktualne** = stan terminalny (`update_thread` z `addLabels:["Nieaktualne", …]`): mail stracił aktualność — archiwizujemy (MCP zdejmuje INBOX); zostawiamy do referencji, a jeśli też bezwartościowy → dodaj `Śmieci`. Jeśli wątek miał rekord → `ledger close --outcome obsolete`.
- **Dojrzałe sprawy**: opcjonalnie możesz wciągnąć `ledger due` (sprawy, których data minęła) i przejść je tak jak stertę triażu — decyzja per grupa: nowa data / Nieaktualne / obsłuż / zostaw. Te same opcje w `AskUserQuestion`.

## Akcje i Faktury → Rachunki (autonomicznie wg reguł)

Te same mechanizmy co w `/email-review` i **tak samo autonomiczne** — gdy wątek pasuje do reguły, wykonaj od razu, bez pytania (to nie jest zmiana reguły). Opt-in pojawia się **tylko** gdy przy okazji uczysz **nowej** reguły dla tej grupy. Mechanika akcji **zależy od konta**: Personal → task Todoist; Work → tylko marker `Wymaga …` (bez tasków):

- **Brama adresatów** (rulebook „Adresaci — czy akcja jest moja?", rygor głównie na Work): przed akcją oceń pozycję w `to`/`cc`, imienne zaadresowanie i czy akcja jest w mojej domenie czy kolegi. Jasno cudza → bez akcji (sklasyfikuj + `status:"done"`); niejasna → zostaw/oznacz `AI/Triage`; jasno moja → obsłuż wg konta niżej.
- **Akcje — zależnie od konta** (rulebook, sekcja „Akcje"): wątek, który wg reguły dostaje `Wymaga działania`/`Wymaga odpowiedzi` **i którego akcja jest moja**:
  - **Personal** (rulebook „Akcje → Todoist") → **autonomicznie**, ale **najpierw dedup**: `ledger query --ref <threadId>` i `ledger find "<podmiot/numer/kwota>"`. Znana sprawa z otwartym zadaniem → **żadnego nowego zadania**, tylko `todoist.py reschedule`/`update`/`comment` + dopięcie wątku do rekordu. Nowa sprawa → `ledger upsert` (rekord), potem `todoist.py add --content … --priority p1..p4 --project 6Crg7HhPc5pxM22C --case <klucz>` (sekcja wg kategorii). Stan zadań ustalaj przez `todoist.py sync`, nie pytaniem użytkownika.
  - **Work** (rulebook „Akcje → markery Wymaga (BEZ tasków)") → **BEZ taska**: `update_thread(status:"done", addLabels:[<kategoria>,"Wymaga działania"|"Wymaga odpowiedzi","IMPORTANT"], priority)`. Marker do ręcznej obsługi; wraca do pipeline'u przy nowej wiadomości, wtedy `Wymaga …` się zdejmuje gdy sprawa domknięta.
- **Faktury → Rachunki** (rulebook „Faktury → folder Rachunki"): o kategorii i trwałości decydują **pozycje z załącznika, nie nadawca/temat/treść maila**. Faktura/paragon z załącznikiem → **otwórz PDF (`save_attachment`→`Read`) i ustal produkt PRZED kategorią** (subagent/digest klasyfikujący fakturę otwiera PDF sam, nie zgaduje ze snippeta) — zwłaszcza gdy nadawca/temat „przesądzają" kategorię; brak załącznika → treść, dalej niejasne → zostaw w triażu. Zakup → `Zakupy` (nie `Finanse`/`Księgowość`, nawet z NIP/VAT/kosztem firmowym; sam „usługowy" wygląd nadawcy nie wystarcza); trwałe dobro >100 zł → **autonomicznie** zapisz PDF + notatkę do `./obsidian/Rachunki/`. Bez pytania.

## Format wyjścia

### Podsumowanie triażu
- **Przetworzone:** N wątków w M grupach
- **Nowe/zmienione reguły:** lista (Typ → Akcja, konto)
- **Akcje na mailach:** labele/drafty/archiwizacje, priorytety (P0/P1/P2/P3), ile `AI/Triage` → `AI/Done` (zdjęty triage), ile Defer / Nieaktualne
- **Pozostało w triażu:** ile wątków zostało w `AI/Triage` (tylko świadomie odłożone)

## Bezpieczeństwo

- **Luka kontekstowa** (protokół CLAUDE.md „Luki kontekstowe"): nadawca / organizacja / wewnętrzny termin / dokument, który **zmienia klasyfikację lub akcję**, a jest nieczytelny nawet po obejrzeniu maila i PDF oraz research w vault (qmd/Read digital twina) → **dopytaj użytkownika w trakcie sesji** (i tak jesteście w dialogu) i **utrwal** (osoba → `Kontakty/`, kontekst zawodowy → `Work.md`, reszta → `Insights.md`). To **inna rzecz niż podwójne opt-in na regułę**: tu **rozumiesz świat**, żeby dobrze sklasyfikować; tam **zmieniasz rulebook**. Rozumienie kontekstu nie wymaga opt-in — zmiana reguły wymaga.
- **Podwójne opt-in TYLKO na zmianę reguły** rulebooka (patrz sekcja wyżej). Akcje na mailach/taskach wg istniejących reguł są autonomiczne — nie pytaj o każdy mail. Feedback ≠ zgoda (dla reguł).
- **Nigdy nie wysyłaj** maili — tylko drafty.
- **Nigdy nie usuwaj** maili/zadań/wydarzeń/notatek; **nie** modyfikuj ani **nie** ukańczaj istniejących tasków (to robi użytkownik).
- Po obsłużeniu wątku **zawsze `update_thread(status:"done", …)`** (MCP zdejmie `AI/Triage`) — obsłużony wątek nie może zostać w stercie triażu. W `AI/Triage` zostają **tylko** wątki, dla których czekasz na zgodę na nową regułę, lub świadomie odłożone.
- Komunikuj po polsku.
