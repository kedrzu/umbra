#!/usr/bin/env python3
"""Todoist - jedyna droga agenta do zadan (bez MCP).

Dlaczego CLI, a nie serwer MCP: potrzebujemy piaciu operacji zapisu, a hostowany
MCP Todoista dorzucal do tego 37 narzedzi, wygasajacy OAuth w krytycznej sciezce
porannej rutyny i bezpieczenstwo oparte na deny-patternach po nazwach cudzego
API (nieszczelnych). Tutaj gwarancja jest strukturalna: NIE MA podkomend
`complete`, `delete`, `uncomplete` ani `move`, wiec agent nie zamknie i nie
skasuje zadania nawet przy najbardziej dziurawej konfiguracji uprawnien.
Ukanczanie zadan nalezy do uzytkownika; agent tylko to zauwaza (`sync`).

Odczyty ida z LUSTRA na dysku (`mirrors/todoist.jsonl` w ledgerze), nie z API -
rutyna synchronizuje na starcie, wiec lustro jest swieze, a kilkaset zadan
nigdy nie wchodzi do kontekstu modelu. Do API siega tylko `sync`, zapisy
i `completed` (okno spoza lustra).

    todoist.py sync                     # diff od ostatniego uruchomienia
    todoist.py tasks --today --overdue  # z lustra, bez sieci
    todoist.py add --content "Zaplac E.ON" --priority p2 --case eon-faktura-2026-07
    todoist.py reschedule --id 6hJ --due 2026-08-30
    todoist.py comment --id 6hJ --text "ponaglenie z 18.08"
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ledger  # noqa: E402

MIRROR_SOURCE = "todoist"
MIRROR_KIND = "todoist_task"
REF_PREFIX = "todoist:task:"
COMPLETED_RETENTION_DAYS = 60
TRACKED_FIELDS = ("title", "due", "data.priority", "data.project_id", "data.section_id")

# Ograniczniki dla kontekstu dociaganego przy ukonczeniu zadania - notatka ma
# byc wskazowka, nie zalacznikiem.
MAX_COMMENTS = 10
COMMENT_MAX_CHARS = 600
# Zmiany zrobione tym klientem to ruchy agenta - dla niego nie sa nowina.
AGENT_CLIENT = "Claude Code"
# Ile zagubionych powiazan rozstrzygamy pojedynczym zapytaniem na run.
MAX_RESOLVE = 25

# Todoist przechodzi z REST v2 na zunifikowane API v1. Probujemy nowszego,
# spadamy na starsze - dzieki temu skrypt nie umiera na zmianie wersji.
API_VARIANTS = [
    {
        "name": "v1",
        "base": "https://api.todoist.com/api/v1",
        "completed": "https://api.todoist.com/api/v1/tasks/completed/by_completion_date",
    },
    {
        "name": "v2",
        "base": "https://api.todoist.com/rest/v2",
        "completed": "https://api.todoist.com/sync/v9/completed/get_all",
    },
]

# Priorytet w API jest ODWROCONY wzgledem jezyka UI i rulebookow: w API 4 = pilne,
# w UI p1 = pilne. Mapowanie zyje wylacznie tutaj - na zewnatrz (rulebooki,
# skille, lustro, wyjscie CLI) obowiazuje zawsze p1..p4.
UI_TO_API_PRIORITY = {"p1": 4, "p2": 3, "p3": 2, "p4": 1}
API_TO_UI_PRIORITY = {v: k for k, v in UI_TO_API_PRIORITY.items()}


class TodoistError(Exception):
    pass


# --------------------------------------------------------------------------
# Konfiguracja i HTTP

def load_token(repo_root: Path | None = None) -> str:
    token = os.environ.get("TODOIST_API_TOKEN", "").strip()
    if token:
        return token
    env_path = (repo_root or ledger.REPO_ROOT) / ".env"
    if env_path.is_file():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("TODOIST_API_TOKEN") and "=" in line:
                value = line.split("=", 1)[1].strip().strip('"').strip("'")
                if value:
                    return value
    raise TodoistError(
        "Brak TODOIST_API_TOKEN. Pobierz token w Todoist -> Ustawienia -> Integracje -> "
        "Developer (API token) i dopisz do .env:  TODOIST_API_TOKEN=xxxxx"
    )


def request(method: str, url: str, token: str, params: dict | None = None,
            body: dict | None = None) -> Any:
    if params:
        url = f"{url}?{urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})}"
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    if data:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:300]
        raise TodoistError(f"HTTP {exc.code} z {method} {url}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise TodoistError(f"Brak polaczenia z {url}: {exc.reason}") from exc
    return json.loads(raw) if raw.strip() else {}


def http_get(url: str, token: str, params: dict | None = None) -> Any:
    return request("GET", url, token, params=params)


def fetch_paginated(url: str, token: str, params: dict | None = None) -> list[dict]:
    items: list[dict] = []
    cursor = None
    for _ in range(50):  # bezpiecznik na wypadek zapetlenia kursora
        page = http_get(url, token, {**(params or {}), "cursor": cursor, "limit": 200})
        if isinstance(page, list):
            items.extend(page)
            return items
        if isinstance(page, dict):
            items.extend(page.get("results") or page.get("items") or [])
            cursor = page.get("next_cursor")
            if not cursor:
                return items
        else:
            return items
    return items


def api_variant(token: str) -> dict:
    """Ustal wariant API raz, na podstawie tego, ktory odpowiada."""
    last: Exception | None = None
    for variant in API_VARIANTS:
        try:
            http_get(f"{variant['base']}/projects", token, {"limit": 1})
            return variant
        except TodoistError as exc:
            last = exc
    raise TodoistError(f"Zadne API Todoista nie odpowiedzialo. Ostatni blad: {last}")


# --------------------------------------------------------------------------
# Lustro

def due_date(task: dict) -> str | None:
    due = task.get("due")
    if isinstance(due, dict):
        value = due.get("date") or due.get("datetime")
        return str(value)[:10] if value else None
    if isinstance(due, str):
        return due[:10]
    return None


def to_record(task: dict, status: str, completed_at: str | None = None) -> dict:
    task_id = str(task.get("id") or task.get("task_id") or "")
    return {
        "id": f"{REF_PREFIX}{task_id}",
        "kind": MIRROR_KIND,
        "source": MIRROR_SOURCE,
        "context": "personal",
        "title": task.get("content") or "",
        "status": status,
        "due": due_date(task),
        "data": {
            "task_id": task_id,
            "project_id": str(task.get("project_id") or ""),
            "section_id": str(task.get("section_id") or ""),
            "parent_id": str(task.get("parent_id") or ""),
            "priority": API_TO_UI_PRIORITY.get(task.get("priority"), "p4"),
            "labels": task.get("labels") or [],
            "url": task.get("url") or "",
            "description": (task.get("description") or "")[:500],
            "completed_at": completed_at,
        },
    }


def fetch_state(token: str, days: int, debug: bool) -> tuple[list[dict], str]:
    variant = api_variant(token)
    active = fetch_paginated(f"{variant['base']}/tasks", token)

    until = dt.datetime.now()
    since = until - dt.timedelta(days=days)
    completed_raw: list[dict] = []
    last_error: Exception | None = None
    for params in (
        {"since": since.strftime("%Y-%m-%dT%H:%M:%S"), "until": until.strftime("%Y-%m-%dT%H:%M:%S")},
        {"since": since.strftime("%Y-%m-%dT%H:%M"), "until": until.strftime("%Y-%m-%dT%H:%M")},
    ):
        try:
            completed_raw = fetch_paginated(variant["completed"], token, params)
            break
        except TodoistError as exc:
            last_error = exc
    if debug:
        print(json.dumps({"debug": variant["name"], "active_sample": active[:1],
                          "completed_sample": completed_raw[:1], "completed_error": str(last_error)},
                         ensure_ascii=False, indent=2), file=sys.stderr)

    records: dict[str, dict] = {}
    for task in active:
        record = to_record(task, "open")
        records[record["id"]] = record
    for item in completed_raw:
        task = item.get("item") if isinstance(item.get("item"), dict) else item
        completed_at = item.get("completed_at") or task.get("completed_at")
        record = to_record(task, "completed", completed_at)
        if record["id"] != REF_PREFIX:
            records.setdefault(record["id"], record)
    return list(records.values()), variant["name"]


# --------------------------------------------------------------------------
# Diff

def compute_diff(old: dict[str, dict], new: dict[str, dict]) -> dict[str, list[dict]]:
    diff: dict[str, list[dict]] = {"created": [], "completed": [], "updated": [], "deleted": []}

    for record_id, record in new.items():
        previous = old.get(record_id)
        entry = {"id": record["data"]["task_id"], "ref": record_id, "content": record["title"]}
        if previous is None:
            if record["status"] == "open":
                diff["created"].append({**entry, "due": record.get("due")})
            continue
        if previous.get("status") == "open" and record["status"] == "completed":
            diff["completed"].append({**entry, "completed_at": record["data"].get("completed_at")})
            continue
        if record["status"] != "open":
            continue
        changed = {}
        for path in TRACKED_FIELDS:
            before, after = ledger.get_path(previous, path), ledger.get_path(record, path)
            if before != after:
                changed[path.split(".")[-1]] = [before, after]
        if changed:
            diff["updated"].append({**entry, "changed": changed})

    for record_id, record in old.items():
        if record_id not in new and record.get("status") == "open":
            diff["deleted"].append({
                "id": record.get("data", {}).get("task_id", ""),
                "ref": record_id,
                "content": record.get("title", ""),
            })
    return diff


def fetch_comments(token: str, base: str, task_id: str) -> list[dict]:
    try:
        raw = http_get(f"{base}/comments", token, {"task_id": task_id, "limit": 50})
    except TodoistError:
        return []  # brak komentarzy nie moze wywrocic synchronizacji
    items = raw.get("results", raw) if isinstance(raw, dict) else raw
    out = [{"posted_at": c.get("posted_at"), "content": (c.get("content") or "")[:COMMENT_MAX_CHARS]}
           for c in (items or []) if (c.get("content") or "").strip()]
    return out[-MAX_COMMENTS:]


def fetch_changes(token: str, base: str, task_id: str) -> dict:
    """Streszczenie tego, co z zadaniem robil CZLOWIEK.

    Zmiany zrobione przez agenta odfiltrowujemy po `client` - agent nie musi
    sie dowiadywac o wlasnych ruchach. Zostaje sygnal o tym, jak zadanie bylo
    prowadzone: przekladane (zle oszacowany termin), przepisane (zle
    sformulowane), przeniesione (zla kategoria)."""
    try:
        raw = http_get(f"{base}/activities", token,
                       {"object_type": "item", "object_id": task_id, "limit": 50})
    except TodoistError:
        return {}
    events = raw.get("results", raw) if isinstance(raw, dict) else raw

    summary: dict[str, Any] = {}
    postponed = 0
    for event in events or []:
        extra = event.get("extra_data") or {}
        if AGENT_CLIENT in str(extra.get("client") or ""):
            continue  # to byl agent, nie uzytkownik
        if event.get("event_type") != "updated":
            continue
        if extra.get("last_due_date") or extra.get("due_date"):
            postponed += 1
        if extra.get("last_content"):
            summary["edited_by_user"] = True
        if extra.get("last_section_id") or extra.get("last_project_id"):
            summary["moved"] = True
    if postponed:
        summary["postponed"] = postponed
    return summary


def add_context(diff: dict[str, list[dict]], token: str, base: str) -> None:
    """Dociaga komentarze i historie do zadan ukończonych/usunietych.

    To jedyny moment, w ktorym agent i tak na nie patrzy - a przy zadaniu
    czesto zostaje instrukcja wazniejsza niz sam fakt ukonczenia ("nie
    placimy juz za Disney+, ignoruj te maile"). Pola puste pomijamy, zeby
    dzien bez notatek nie kosztowal ani linijki kontekstu."""
    for bucket in ("completed", "deleted"):
        for item in diff.get(bucket, []):
            task_id = item.get("id")
            if not task_id:
                continue
            comments = fetch_comments(token, base, task_id)
            if comments:
                item["comments"] = comments
            changes = fetch_changes(token, base, task_id)
            if changes:
                item["changes"] = changes


def enrich(diff: dict[str, list[dict]], store: ledger.Store) -> dict[str, list[dict]]:
    """Dokleja do kazdej pozycji id spraw, ktore ja obserwuja - bez tego
    agent musialby przeszukiwac rejestr osobno dla kazdego zadania."""
    owners: dict[str, list[str]] = {}
    for record in ledger.Store.read_jsonl(store.tasks_path):
        for ref in record.get("refs") or []:
            if ref.startswith(REF_PREFIX):
                owners.setdefault(ref, []).append(str(record.get("id")))
    for items in diff.values():
        for item in items:
            item["tasks"] = owners.get(item.get("ref", ""), [])
    return diff


def resolve_missing(token: str, base: str, task_id: str) -> dict:
    """Rozstrzyga los zadania, ktorego nie ma w lustrze.

    'Nie ma w lustrze' nie znaczy 'usuniete': lustro trzyma ukonczone tylko z
    ostatnich ~30 dni, wiec zadanie zamkniete kwartal temu wyglada tak samo jak
    skasowane. Roznica jest istotna, bo ukonczone domyka sprawe, a skasowane
    idzie do triazu - bez tego rozroznienia maile trafialyby do triazu bez
    powodu."""
    try:
        task = http_get(f"{base}/tasks/{task_id}", token)
    except TodoistError:
        return {"state": "deleted"}  # 404 = zadania nie ma
    if task.get("is_deleted"):
        return {"state": "deleted"}
    if task.get("checked"):
        return {"state": "completed", "completed_at": task.get("completed_at"),
                "content": task.get("content")}
    # Otwarte, a poza lustrem - nie powinno sie zdarzyc; zglos zamiast zgadywac.
    return {"state": "open_unmirrored", "content": task.get("content")}


def stale_links(store: ledger.Store, mirror: dict[str, dict],
                token: str | None = None, base: str | None = None) -> list[dict]:
    """Sprawy wskazujace na zadanie, ktorego juz nie ma albo jest ukonczone.

    Diff pokazuje tylko ZMIANY, wiec sprawa powiazana z zadaniem ukonczonym
    zanim powstalo lustro (np. tuz po migracji) nie wyprodukowalaby zadnego
    zdarzenia i wisialaby otwarta w nieskonczonosc. To jest ten bezpiecznik.
    """
    out = []
    resolved = 0
    for record in ledger.Store.read_jsonl(store.tasks_path):
        if record.get("status") not in ("open", "waiting"):
            continue
        for ref in record.get("refs") or []:
            if not ref.startswith(REF_PREFIX):
                continue
            mirrored = mirror.get(ref)
            if mirrored is not None and mirrored.get("status") == "open":
                continue
            entry = {"task": record.get("id"), "title": record.get("title"), "ref": ref}
            if mirrored is not None:
                entry["state"] = mirrored.get("status")
            elif token and base and resolved < MAX_RESOLVE:
                resolved += 1
                detail = resolve_missing(token, base, ref[len(REF_PREFIX):])
                entry.update(detail)
                if detail["state"] in ("completed", "deleted"):
                    comments = fetch_comments(token, base, ref[len(REF_PREFIX):])
                    if comments:
                        entry["comments"] = comments
            else:
                entry["state"] = "missing"
            out.append(entry)
    return out


def prune(records: list[dict]) -> list[dict]:
    """Ukonczone trzymamy chwile (zeby przejscie open->completed dalo sie
    wykryc raz), potem znikaja - lustro ma nie puchnac w nieskonczonosc."""
    cutoff = (dt.date.today() - dt.timedelta(days=COMPLETED_RETENTION_DAYS)).isoformat()
    out = []
    for record in records:
        if record.get("status") == "completed":
            completed_at = str(record.get("data", {}).get("completed_at") or "")[:10]
            if completed_at and completed_at < cutoff:
                continue
        out.append(record)
    return out


# --------------------------------------------------------------------------
# Komendy

def cmd_sync(store: ledger.Store, args: argparse.Namespace) -> int:
    token = load_token()
    records, variant = fetch_state(token, args.days, args.debug)
    mirror_path = store.mirror_path(MIRROR_SOURCE)
    old = {r["id"]: r for r in ledger.Store.read_jsonl(mirror_path)}
    new = {r["id"]: r for r in records}

    if args.init or not old:
        if not args.dry_run:
            with store.lock():
                ledger.Store.write_jsonl(mirror_path, prune(records))
        print(json.dumps({
            "init": True, "api": variant, "mirrored": len(records),
            "open": sum(1 for r in records if r["status"] == "open"),
            "stale_links": stale_links(store, new, token, api_variant(token)["base"]),
        }, ensure_ascii=False, indent=2))
        return 0

    diff = enrich(compute_diff(old, new), store)
    total = sum(len(v) for v in diff.values())  # przed doklejeniem stale_links
    if not args.no_context:
        add_context(diff, token, api_variant(token)["base"])
    diff["stale_links"] = stale_links(store, new, token, api_variant(token)["base"])

    if not args.dry_run:
        # Lustro to swiezy stan, nie suma historyczna: zadania zgloszone jako
        # usuniete musza z niego zniknac, inaczej wracalyby w diffie co dzien.
        with store.lock():
            ledger.Store.write_jsonl(mirror_path, prune(list(new.values())))

    print(json.dumps({"api": variant, "changes": total, **diff}, ensure_ascii=False, indent=2))
    return 0


def cmd_tasks(store: ledger.Store, args: argparse.Namespace) -> int:
    """Odczyt z lustra - zero wywolan API, zero kosztu kontekstu."""
    records = [r for r in ledger.Store.read_jsonl(store.mirror_path(MIRROR_SOURCE))
               if r.get("status") == "open"]
    today = ledger.today()

    if args.today or args.overdue or args.due_before:
        limit = ledger.resolve_date(args.due_before) if args.due_before else today
        picked = []
        for record in records:
            due = record.get("due")
            if not due:
                continue
            if args.overdue and due < today:
                picked.append(record)
            elif args.today and due == today:
                picked.append(record)
            elif args.due_before and due <= limit:
                picked.append(record)
        records = picked
    if args.priority:
        wanted = {p.strip() for p in args.priority.split(",") if p.strip()}
        records = [r for r in records if ledger.get_path(r, "data.priority") in wanted]
    if args.project:
        records = [r for r in records if ledger.get_path(r, "data.project_id") == args.project]

    records = sorted(records, key=lambda r: (r.get("due") or ledger.FAR_FUTURE,
                                             ledger.get_path(r, "data.priority") or "p4"))
    if args.limit:
        records = records[: args.limit]
    ledger.emit(records, args.format, args.select)
    return 0


def cmd_completed(store: ledger.Store, args: argparse.Namespace) -> int:
    token = load_token()
    variant = api_variant(token)
    since = ledger.resolve_date(args.since) or ledger.today()
    until = ledger.resolve_date(args.until) or ledger.today()
    items = fetch_paginated(variant["completed"], token, {
        "since": f"{since}T00:00:00", "until": f"{until}T23:59:59",
    })
    out = []
    for item in items:
        task = item.get("item") if isinstance(item.get("item"), dict) else item
        out.append({
            "id": str(task.get("id") or task.get("task_id") or ""),
            "content": task.get("content") or "",
            "completed_at": item.get("completed_at") or task.get("completed_at"),
            "project_id": str(task.get("project_id") or ""),
        })
    print(json.dumps({"since": since, "until": until, "count": len(out), "tasks": out},
                     ensure_ascii=False, indent=2))
    return 0


def cmd_comments(store: ledger.Store, args: argparse.Namespace) -> int:
    token = load_token()
    base = api_variant(token)["base"]
    print(json.dumps(fetch_comments(token, base, args.id), ensure_ascii=False, indent=2))
    return 0


def cmd_activity(store: ledger.Store, args: argparse.Namespace) -> int:
    token = load_token()
    base = api_variant(token)["base"]
    raw = http_get(f"{base}/activities", token,
                   {"object_type": "item", "object_id": args.id, "limit": args.limit})
    events = raw.get("results", raw) if isinstance(raw, dict) else raw
    out = []
    for event in events or []:
        extra = event.get("extra_data") or {}
        out.append({
            "event_date": event.get("event_date"),
            "event_type": event.get("event_type"),
            "client": extra.get("client"),
            "extra": {k: v for k, v in extra.items()
                      if k.startswith("last_") or k in ("content", "due_date")},
        })
    print(json.dumps({"summary": fetch_changes(token, base, args.id), "events": out},
                     ensure_ascii=False, indent=2))
    return 0


def cmd_sections(store: ledger.Store, args: argparse.Namespace) -> int:
    token = load_token()
    variant = api_variant(token)
    items = fetch_paginated(f"{variant['base']}/sections", token,
                            {"project_id": args.project} if args.project else None)
    print(json.dumps([{"id": s.get("id"), "name": s.get("name"),
                       "project_id": s.get("project_id")} for s in items],
                     ensure_ascii=False, indent=2))
    return 0


def link_case(store: ledger.Store, case_id: str, task_id: str, note: str) -> None:
    """Dopiecie zadania do sprawy w tym samym wywolaniu, co jego utworzenie.

    Rozdzielenie tych dwoch krokow zostawia okno, w ktorym zadanie istnieje,
    a rejestr o nim nie wie - czyli dokladnie zarodek duplikatu, ktory ten
    system ma likwidowac."""
    payload = [{
        "id": case_id, "kind": "task",
        "refs": [f"{REF_PREFIX}{task_id}"],
        "history": [f"{ledger.today()} {note}"],
    }]
    existing = {str(r.get("id")) for r in ledger.Store.read_jsonl(store.tasks_path)}
    if case_id not in existing:
        raise TodoistError(
            f"Sprawa '{case_id}' nie istnieje w rejestrze - najpierw utworz rekord "
            f"(ledger.py upsert), potem powiaz zadanie."
        )
    # cmd_upsert raportuje na stdout; tutaj stdout nalezy do wyniku `add`,
    # wiec jego log idzie na stderr.
    with contextlib.redirect_stdout(sys.stderr):
        ledger.cmd_upsert(store, argparse.Namespace(stdin=False, json=json.dumps(payload)))


def cmd_add(store: ledger.Store, args: argparse.Namespace) -> int:
    token = load_token()
    variant = api_variant(token)
    body: dict[str, Any] = {"content": args.content}
    if args.description:
        body["description"] = args.description
    if args.due:
        body["due_date"] = ledger.resolve_date(args.due) or args.due
    if args.priority:
        body["priority"] = UI_TO_API_PRIORITY[args.priority]
    if args.project:
        body["project_id"] = args.project
    if args.section:
        body["section_id"] = args.section
    if args.labels:
        body["labels"] = [l.strip() for l in args.labels.split(",") if l.strip()]

    task = request("POST", f"{variant['base']}/tasks", token, body=body)
    task_id = str(task.get("id", ""))
    result = {"id": task_id, "content": task.get("content"),
              "url": task.get("url") or f"https://app.todoist.com/app/task/{task_id}"}
    if args.case:
        link_case(store, args.case, task_id, f"utworzono zadanie {task_id}")
        result["case"] = args.case
    print(json.dumps(result, ensure_ascii=False))
    return 0


def cmd_update(store: ledger.Store, args: argparse.Namespace) -> int:
    token = load_token()
    variant = api_variant(token)
    body: dict[str, Any] = {}
    if args.content:
        body["content"] = args.content
    if args.description:
        body["description"] = args.description
    if args.priority:
        body["priority"] = UI_TO_API_PRIORITY[args.priority]
    if args.labels:
        body["labels"] = [l.strip() for l in args.labels.split(",") if l.strip()]
    if not body:
        raise TodoistError("Nic do zmiany - podaj --content/--description/--priority/--labels. "
                           "Termin zmienia sie osobno: `reschedule`.")
    task = request("POST", f"{variant['base']}/tasks/{args.id}", token, body=body)
    print(json.dumps({"id": str(task.get("id", args.id)), "updated": sorted(body)},
                     ensure_ascii=False))
    return 0


def cmd_reschedule(store: ledger.Store, args: argparse.Namespace) -> int:
    """Termin ma wlasna komende, bo nadpisanie calego `due` w zwyklym update
    kasuje powtarzalnosc zadan cyklicznych. Osobna komenda = nie da sie tego
    zrobic przez przypadek."""
    token = load_token()
    variant = api_variant(token)
    due = ledger.resolve_date(args.due) or args.due
    task = request("POST", f"{variant['base']}/tasks/{args.id}", token,
                   body={"due_date": due})
    print(json.dumps({"id": str(task.get("id", args.id)), "due": due}, ensure_ascii=False))
    return 0


def cmd_comment(store: ledger.Store, args: argparse.Namespace) -> int:
    token = load_token()
    variant = api_variant(token)
    comment = request("POST", f"{variant['base']}/comments", token,
                      body={"task_id": args.id, "content": args.text})
    print(json.dumps({"id": str(comment.get("id", "")), "task_id": args.id}, ensure_ascii=False))
    return 0


# --------------------------------------------------------------------------
# CLI

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Todoist bez MCP (odczyt z lustra, zapis przez API)")
    parser.add_argument("--store", default=os.environ.get("LEDGER_DIR", str(ledger.DEFAULT_STORE)))
    sub = parser.add_subparsers(dest="command", required=True)

    p_sync = sub.add_parser("sync", help="lustro -> diff (nowe/ukonczone/zmienione/usuniete)")
    p_sync.add_argument("--init", action="store_true", help="pierwsze lustro, bez diffu")
    p_sync.add_argument("--days", type=int, default=30, help="okno ukonczonych (domyslnie 30)")
    p_sync.add_argument("--dry-run", action="store_true")
    p_sync.add_argument("--no-context", action="store_true",
                        help="nie dociagaj komentarzy/historii do ukonczonych zadan")
    p_sync.add_argument("--debug", action="store_true")
    p_sync.set_defaults(func=cmd_sync)

    p_comments = sub.add_parser("comments", help="komentarze zadania (notatki uzytkownika)")
    p_comments.add_argument("--id", required=True)
    p_comments.set_defaults(func=cmd_comments)

    p_activity = sub.add_parser("activity", help="historia zmian zadania")
    p_activity.add_argument("--id", required=True)
    p_activity.add_argument("--limit", type=int, default=20)
    p_activity.set_defaults(func=cmd_activity)

    p_tasks = sub.add_parser("tasks", help="otwarte zadania z lustra (bez wywolania API)")
    p_tasks.add_argument("--today", action="store_true")
    p_tasks.add_argument("--overdue", action="store_true")
    p_tasks.add_argument("--due-before", dest="due_before")
    p_tasks.add_argument("--priority", help="p1,p2 …")
    p_tasks.add_argument("--project")
    p_tasks.add_argument("--select")
    p_tasks.add_argument("--format", choices=["json", "ids", "table", "count"], default="json")
    p_tasks.add_argument("--limit", type=int)
    p_tasks.set_defaults(func=cmd_tasks)

    p_done = sub.add_parser("completed", help="ukonczone w oknie (weekly-review)")
    p_done.add_argument("--since", default="today-7")
    p_done.add_argument("--until", default="today")
    p_done.set_defaults(func=cmd_completed)

    p_sections = sub.add_parser("sections", help="sekcje projektu (id + nazwa)")
    p_sections.add_argument("--project")
    p_sections.set_defaults(func=cmd_sections)

    p_add = sub.add_parser("add", help="nowe zadanie")
    p_add.add_argument("--content", required=True)
    p_add.add_argument("--description")
    p_add.add_argument("--due")
    p_add.add_argument("--priority", choices=list(UI_TO_API_PRIORITY))
    p_add.add_argument("--project")
    p_add.add_argument("--section")
    p_add.add_argument("--labels")
    p_add.add_argument("--case", help="id sprawy w rejestrze - powiazanie w tym samym wywolaniu")
    p_add.set_defaults(func=cmd_add)

    p_update = sub.add_parser("update", help="zmiana pol zadania (BEZ terminu)")
    p_update.add_argument("--id", required=True)
    p_update.add_argument("--content")
    p_update.add_argument("--description")
    p_update.add_argument("--priority", choices=list(UI_TO_API_PRIORITY))
    p_update.add_argument("--labels")
    p_update.set_defaults(func=cmd_update)

    p_resched = sub.add_parser("reschedule", help="zmiana terminu zadania")
    p_resched.add_argument("--id", required=True)
    p_resched.add_argument("--due", required=True)
    p_resched.set_defaults(func=cmd_reschedule)

    p_comment = sub.add_parser("comment", help="komentarz do zadania")
    p_comment.add_argument("--id", required=True)
    p_comment.add_argument("--text", required=True)
    p_comment.set_defaults(func=cmd_comment)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    store = ledger.Store(Path(args.store).expanduser())
    try:
        return args.func(store, args)
    except (TodoistError, ledger.LedgerError) as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
