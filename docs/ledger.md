# Ledger — rejestr otwartych spraw agenta

Rejestr tego, **co agentowi wisi**: odłożone maile, sprawy powiązane z zadaniami Todoist, przypomnienia o follow-upie. Dziś zasilają go maile i Todoist, docelowo także kalendarz, notatki głosowe i inne źródła — dlatego model rekordu jest źródło-agnostyczny.

Wcześniej ten stan siedział w etykietach Gmaila (`AI/Defer/<data>`, `TODO/<taskId>`): jedna etykieta na datę, jedna na zadanie, setki sztuk, a i tak bez miejsca na **powód** odłożenia i bez wiedzy, co się z zadaniem stało. Rejestr to zastępuje.

## Zasady

- **Rozmawiasz z CLI, nie z plikami.** `scripts/ledger.py` to stabilny kontrakt; format pod spodem (dziś JSONL) może się zmienić bez ruszania skilli. Nigdy nie edytuj `.jsonl` ręcznie ani nie parsuj go `grep`em.
- **Rejestr trzyma pętle, nie prozę.** Do środka trafia tylko to, co musi być deterministycznie filtrowalne: daty, status, powiązania. Opis osoby, kontekst projektu, historia sprawy → notatki w vault (`Kontakty/`, `Projects/`, `Dziennik/`), a rekord wskazuje je polem `note` i przez `refs`. Do przeszukiwania prozy jest `qmd`.
- **Zapisuje główny agent.** Subagenci w batchach zwracają propozycje rekordów i zadań w raporcie; `upsert` i tworzenie zadań robi **jeden** proces — nie tylko po to, żeby dwa batche nie deptały sobie pliku, ale przede wszystkim dlatego, że tylko ten proces widzi wszystkie sprawy naraz i potrafi rozpoznać, że dwa maile dotyczą jednej sprawy.
- **`Otwarte.md` jest generowany** — to widok do czytania z telefonu, nie źródło prawdy. Nie edytuj.

## Model rekordu

Mały, zamrożony rdzeń + swobodne `data`. Wzrost dzieje się w `data` i w nowych wartościach `kind`/`source` — dołożenie nowego źródła nie jest migracją. Pola i wartości techniczne są po angielsku; treść (tytuły, powody) po polsku.

```json
{
  "id": "eon-faktura-2026-07",
  "kind": "task",
  "context": "personal",
  "source": "gmail",
  "title": "E.ON — faktura 579,16 zł za lipiec 2026",
  "status": "open",
  "due": "2026-08-24",
  "reason": "czekam aż zapłacę; termin 23.08, przyszło ponaglenie",
  "refs": ["gmail:personal:thread:19abc", "gmail:personal:thread:19def", "todoist:task:6hJ…"],
  "note": null,
  "created": "2026-08-05",
  "updated": "2026-08-21",
  "history": ["2026-08-05 zadanie z wątku 19abc", "2026-08-18 ponaglenie — reschedule na 23.08"],
  "data": { "okres": "2026-07", "kwota": "579,16" }
}
```

| Pole | Znaczenie |
|------|-----------|
| `id` | **klucz sprawy**: `<podmiot>-<sprawa>-<okres\|numer>`. Sprawy cykliczne **muszą** nieść okres/numer dokumentu (`eon-faktura-2026-07`), żeby faktura za sierpień była nową sprawą, a ponaglenie do lipcowej — nie |
| `kind` | `task` = własna pętla agenta. `todoist_task` = lustro zadania z Todoista (pisze wyłącznie `todoist.py sync`) |
| `context` | `personal` \| `work` |
| `status` | `open` \| `waiting` (czekam na kogoś) \| `done` (tylko w archiwum) |
| `due` | data powrotu sprawy do agenta. Z zadania → jego termin; z reguły rulebooka → ta data; brak → +14 dni |
| `refs` | klej: `<źródło>:<konto>:<typ>:<id>` — `gmail:personal:thread:…`, `todoist:task:…`, `note:Dziennik/2026-08-21.md`. Jedna sprawa może mieć wiele wątków |
| `reason` | **po co to wisi** — jedno zdanie. To jest ta informacja, której etykiety nie mieściły |

## CLI

```bash
python3 scripts/ledger.py <komenda> [opcje]
```

| Komenda | Do czego |
|---|---|
| `due [--date D] [--context C]` | co dojrzało (domyślnie: dziś, `kind=task`, `status=open,waiting`) |
| `query [filtry]` | pełne filtrowanie |
| `get <id>` / `find <fraza>` | jeden rekord / szukanie po aktywnych **i archiwum** |
| `upsert --stdin` | wstaw/scal listę rekordów (po `id`: union `refs`, dopisanie `history`) |
| `close --id X --outcome completed\|obsolete\|gone --reason "…"` | zamknij → archiwum |
| `validate` | kontrola spójności (ostrzega, nie blokuje) |

**Filtry**: `--kind --context --source --status --due-before --due-after --ref --text`, plus generyczny `--where 'ścieżka OP wartość'` (powtarzalny, ANDowany; OP: `=` `!=` `<` `<=` `>` `>=` `~`, oraz `ścieżka in a,b` i `ścieżka exists`). Ścieżki są kropkowane i sięgają do `data`.

**Kontrola kontekstu**: `--select id,title,due` tnie wynik do potrzebnych pól, `--format json|ids|table|count`, `--limit N`. Zawsze zawężaj — nie wciągaj całego rejestru do kontekstu.

Daty przyjmują `today`, `today+7`, `today-3` albo `YYYY-MM-DD`.

### Przykłady

```bash
# co wraca dziś na koncie prywatnym
python3 scripts/ledger.py due --context personal --select id,title,reason,refs

# dedup: czy tę sprawę już prowadzimy (albo prowadziliśmy)?
python3 scripts/ledger.py find "E.ON" --select id,title,status,due
python3 scripts/ledger.py query --ref 19abc --select id,title

# digest dla subagenta
python3 scripts/ledger.py query --context personal --select id,title,due,refs --format json

# nowa sprawa albo dopięcie wątku do istniejącej (to samo wywołanie)
echo '[{"id":"eon-faktura-2026-07","kind":"task","context":"personal","source":"gmail",
  "title":"E.ON — faktura 579,16 zł","due":"2026-08-24","reason":"czekam aż zapłacę",
  "refs":["gmail:personal:thread:19def","todoist:task:6hJ"],
  "history":["2026-08-18 ponaglenie — reschedule na 23.08"]}]' \
  | python3 scripts/ledger.py upsert --stdin

# sprawa domknięta
python3 scripts/ledger.py close --id eon-faktura-2026-07 --outcome completed --reason "zapłacone"
```

## Todoist (`scripts/todoist.py`)

**Nie ma MCP Todoista** — to CLI jest jedyną drogą. Zdalny serwer wypadł, bo jego OAuth wygasał w trakcie pracy (w rutynie o 8:00 = cicha utrata zdolności), a jego 37 narzędzi trzeba było zagradzać nieszczelnymi deny-patternami.

| Komenda | Do czego |
|---|---|
| `sync [--init] [--days N] [--dry-run]` | lustro na dysk, na stdout **tylko diff** |
| `tasks [--today] [--overdue] [--due-before D] [--priority p1,p2] [--project] [--select] [--format]` | otwarte zadania **z lustra**, bez wywołania API |
| `completed --since --until` | ukończone w oknie (weekly-review) |
| `sections [--project]` | id + nazwy sekcji |
| `add --content … [--description] [--due] [--priority p1..p4] [--project] [--section] [--case <sprawa>]` | nowe zadanie; `--case` **od razu wiąże** je z rekordem sprawy |
| `update --id … [--content] [--description] [--priority] [--labels]` | zmiana pól **poza terminem** |
| `reschedule --id … --due <data>` | wyłącznie termin |
| `comment --id … --text …` | dodaj komentarz |
| `comments --id …` | **czytaj** komentarze zadania (notatki użytkownika) |
| `activity --id … [--limit N]` | historia zmian zadania (kto, kiedy, co) |

**Priorytety zawsze w konwencji UI** (`p1` = najpilniejszy). W API Todoista skala jest odwrócona (`4` = najpilniejszy); tłumaczenie siedzi wyłącznie w CLI, więc na zewnątrz nigdzie nie ma surowych liczb.

**`reschedule` jest osobno od `update`** — nadpisanie całego `due` przy zwykłej edycji kasuje powtarzalność zadań cyklicznych, a osobna komenda czyni to niemożliwym przez przypadek.

**`--case` linkuje atomowo** (wymaga istniejącego rekordu, więc kolejność to: `ledger upsert` → `todoist.py add --case`). Rozdzielenie tych kroków zostawia okno, w którym zadanie istnieje, a rejestr o nim nie wie — czyli zarodek duplikatu.

```bash
python3 scripts/todoist.py sync            # diff od ostatniego uruchomienia
python3 scripts/todoist.py sync --init     # pierwsze lustro (bez diffu)
python3 scripts/todoist.py tasks --today --overdue   # odczyt z lustra, bez API
```

Skrypt **czyta** Todoista tokenem z `.env` (`TODOIST_API_TOKEN`) i trzyma pełne lustro na dysku, ale na stdout wypisuje **wyłącznie zmiany** — kilka linijek zamiast kilkuset zadań:

```json
{"created":[…],
 "completed":[{"id":"6hJ…","content":"Zapłać E.ON…","tasks":["eon-faktura-2026-07"]}],
 "updated":[{"id":"…","changed":{"due":["2026-08-23","2026-08-30"]}}],
 "deleted":[…],
 "stale_links":[{"task":"…","ref":"todoist:task:…","state":"missing"}]}
```

- `tasks` przy każdej pozycji = id spraw, które obserwują to zadanie. Pusta lista = zadanie spoza rejestru (na razie nic z tym nie robimy).
- `stale_links` = sprawy wskazujące na zadanie ukończone lub nieistniejące, których diff by nie pokazał (bo zmiana nastąpiła przed powstaniem lustra). Bezpiecznik przeciw sprawom wiszącym w nieskończoność.
- Pozycje `completed` i `deleted` dostają dodatkowo **`comments`** (notatki użytkownika, do 10 ostatnich) i **`changes`** (co z zadaniem robił **człowiek** — `postponed`, `edited_by_user`, `moved`; ruchy agenta są odfiltrowane po `client`). Pola puste są pomijane, więc dzień bez notatek nie kosztuje ani linijki. To z tych notatek agent uczy się reguł — patrz `/email-review`, Faza 0. Wyłącznik: `sync --no-context`.

**Nie ma MCP Todoista** — `scripts/todoist.py` jest jedyną drogą, także dla zapisów (`add --case`, `update`, `reschedule`, `comment`). Komend `complete`/`delete`/`move` w nim nie ma, więc agent nie zamknie ani nie skasuje zadania nawet przy dziurawej konfiguracji uprawnień; ukańczanie należy do użytkownika, a rejestr tylko to zauważa.

## Odłożenie maila (dawny defer)

Wątek odkładany na później dostaje po prostu `update_thread(status:"done", priority)` — znika z `unprocessed`, **zostaje w INBOX** (archiwizują wyłącznie markery `Nieaktualne`/`Śmieci`). Data i powód powrotu idą do rejestru. Etykiety `AI/Defer/*` i `TODO/*` nie istnieją; MCP odrzuca próby ich nałożenia.
