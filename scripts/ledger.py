#!/usr/bin/env python3
"""Ledger - rejestr otwartych spraw agenta.

Magazyn rekordow w JSONL (vault Obsidian), z filtrowaniem po polach rdzenia
i po dowolnych sciezkach w `data`. To jest STABILNY interfejs agenta:
skille rozmawiaja wylacznie z tym CLI, nigdy z plikami wprost - dzieki temu
silnik (JSONL -> SQLite) da sie kiedys wymienic bez ruszania rulebookow.

Uklad plikow (domyslnie ./obsidian/Asystent/Memory/Ledger):
    tasks.jsonl        rekordy agenta (kind: task)
    archive.jsonl      zamkniete (append-only)
    mirrors/<src>.jsonl lustra obiektow zewnetrznych (kind: todoist_task, ...)
    Otwarte.md         generowany widok

Przyklady:
    ledger.py query --kind task --context personal --due-before today
    ledger.py query --where 'data.okres=2026-07' --select id,title,due
    ledger.py due --context personal
    echo '[{...}]' | ledger.py upsert --stdin
    ledger.py close --id eon-faktura-2026-07 --outcome completed --reason "zaplacone"
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Iterable

# --------------------------------------------------------------------------
# Uklad magazynu

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_STORE = REPO_ROOT / "obsidian" / "Asystent" / "Memory" / "Ledger"

TASKS_FILE = "tasks.jsonl"
ARCHIVE_FILE = "archive.jsonl"
MIRRORS_DIR = "mirrors"
VIEW_FILE = "Otwarte.md"
LOCK_FILE = ".lock"

CORE_FIELDS = [
    "id", "kind", "context", "source", "title", "status", "due",
    "reason", "refs", "note", "created", "updated", "history", "data",
]
AGENT_KIND = "task"
OUTCOMES = ("completed", "obsolete", "gone")
FAR_FUTURE = "9999-12-31"


class LedgerError(Exception):
    pass


# --------------------------------------------------------------------------
# Daty

def today() -> str:
    return dt.date.today().isoformat()


def now() -> str:
    return dt.datetime.now().isoformat(timespec="seconds")


def resolve_date(value: str | None) -> str | None:
    """Zamienia 'today', 'today+7', 'today-3', 'YYYY-MM-DD' na date ISO.

    Skille licza terminy w glowie; przyjmowanie 'today+7' oszczedza im
    arytmetyki na datach, ktora jest klasycznym zrodlem cichych bledow.
    """
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None
    m = re.fullmatch(r"(today|dzis)\s*([+-]\s*\d+)?", value, re.I)
    if m:
        base = dt.date.today()
        if m.group(2):
            base += dt.timedelta(days=int(m.group(2).replace(" ", "")))
        return base.isoformat()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        try:
            dt.date.fromisoformat(value)
        except ValueError as exc:
            raise LedgerError(f"Niepoprawna data: {value}") from exc
        return value
    raise LedgerError(f"Niepoprawna data: {value!r} (oczekiwano YYYY-MM-DD albo today[+/-N])")


# --------------------------------------------------------------------------
# Warstwa plikow

class Store:
    def __init__(self, root: Path):
        self.root = root

    # -- sciezki ---------------------------------------------------------
    @property
    def tasks_path(self) -> Path:
        return self.root / TASKS_FILE

    @property
    def archive_path(self) -> Path:
        return self.root / ARCHIVE_FILE

    @property
    def mirrors_dir(self) -> Path:
        return self.root / MIRRORS_DIR

    def mirror_path(self, source: str) -> Path:
        safe = re.sub(r"[^a-z0-9_-]", "-", (source or "unknown").lower())
        return self.mirrors_dir / f"{safe}.jsonl"

    def path_for(self, record: dict) -> Path:
        """Mirror kazdego zrodla ma wlasny plik - rozne skrypty pisza je
        niezaleznie, wiec wspolny plik oznaczalby konflikt zapisu."""
        if record.get("kind") == AGENT_KIND:
            return self.tasks_path
        return self.mirror_path(record.get("source", ""))

    def mirror_files(self) -> list[Path]:
        if not self.mirrors_dir.is_dir():
            return []
        return sorted(self.mirrors_dir.glob("*.jsonl"))

    # -- io --------------------------------------------------------------
    @contextlib.contextmanager
    def lock(self):
        self.root.mkdir(parents=True, exist_ok=True)
        lock_path = self.root / LOCK_FILE
        with open(lock_path, "w") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(handle, fcntl.LOCK_UN)

    @staticmethod
    def read_jsonl(path: Path) -> list[dict]:
        if not path.is_file():
            return []
        out = []
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise LedgerError(f"{path.name}:{lineno} - uszkodzony JSON: {exc}") from exc
        return out

    @staticmethod
    def write_jsonl(path: Path, records: Iterable[dict]) -> None:
        """Zapis atomowy - vault idzie przez iCloud, wiec polowicznie
        zapisany plik jest realnym ryzykiem, nie teoria."""
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        with open(tmp, "w", encoding="utf-8") as handle:
            for record in records:
                handle.write(json.dumps(record, ensure_ascii=False, sort_keys=False) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)

    @staticmethod
    def append_jsonl(path: Path, records: Iterable[dict]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8") as handle:
            for record in records:
                handle.write(json.dumps(record, ensure_ascii=False) + "\n")
            handle.flush()
            os.fsync(handle.fileno())

    # -- odczyt logiczny --------------------------------------------------
    def load_active(self) -> list[dict]:
        records = self.read_jsonl(self.tasks_path)
        for path in self.mirror_files():
            records.extend(self.read_jsonl(path))
        return records

    def load_archive(self) -> list[dict]:
        return self.read_jsonl(self.archive_path)


# --------------------------------------------------------------------------
# Dostep do pol i filtry

def get_path(record: dict, path: str) -> Any:
    current: Any = record
    for part in path.split("."):
        if isinstance(current, dict):
            current = current.get(part)
        else:
            return None
        if current is None:
            return None
    return current


def _norm(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def _compare(actual: Any, expected: str) -> int:
    with contextlib.suppress(TypeError, ValueError):
        return (float(actual) > float(expected)) - (float(actual) < float(expected))
    a, b = _norm(actual), expected
    return (a > b) - (a < b)


def match_condition(record: dict, cond: tuple[str, str, str]) -> bool:
    path, op, expected = cond
    actual = get_path(record, path)

    if op == "exists":
        return actual is not None
    if op == "in":
        wanted = {v.strip() for v in expected.split(",") if v.strip()}
        values = actual if isinstance(actual, list) else [actual]
        return any(_norm(v) in wanted for v in values)
    if op == "~":
        values = actual if isinstance(actual, list) else [actual]
        needle = expected.lower()
        return any(needle in _norm(v).lower() for v in values)
    if op in ("=", "!="):
        values = actual if isinstance(actual, list) else [actual]
        hit = any(_norm(v) == expected for v in values)
        return hit if op == "=" else not hit
    if actual is None:
        return False
    result = _compare(actual, expected)
    return {"<": result < 0, "<=": result <= 0, ">": result > 0, ">=": result >= 0}[op]


WHERE_RE = re.compile(r"^\s*([\w.\-]+)\s*(!=|>=|<=|=|<|>|~)\s*(.*)$")


def parse_where(expr: str) -> tuple[str, str, str]:
    stripped = expr.strip()
    m = re.fullmatch(r"([\w.\-]+)\s+exists", stripped, re.I)
    if m:
        return (m.group(1), "exists", "")
    m = re.fullmatch(r"([\w.\-]+)\s+in\s+(.+)", stripped, re.I)
    if m:
        return (m.group(1), "in", m.group(2).strip())
    m = WHERE_RE.match(stripped)
    if not m:
        raise LedgerError(
            f"Nie rozumiem warunku {expr!r}. Skladnia: 'sciezka OP wartosc', "
            "OP = = != < <= > >= ~ | 'sciezka in a,b' | 'sciezka exists'"
        )
    path, op, value = m.group(1), m.group(2), m.group(3).strip()
    if op in ("<", "<=", ">", ">=") and path in ("due", "created", "updated", "closed"):
        value = resolve_date(value) or value
    return (path, op, value)


def text_matches(record: dict, needle: str) -> bool:
    blob = json.dumps(record, ensure_ascii=False).lower()
    return needle.lower() in blob


def filter_records(records: list[dict], args: argparse.Namespace) -> list[dict]:
    conds = [parse_where(w) for w in (getattr(args, "where", None) or [])]

    def keep(record: dict) -> bool:
        for field in ("kind", "context", "source", "status"):
            wanted = getattr(args, field, None)
            if wanted:
                allowed = {v.strip() for v in wanted.split(",") if v.strip()}
                if _norm(record.get(field)) not in allowed:
                    return False
        due_before = resolve_date(getattr(args, "due_before", None))
        due_after = resolve_date(getattr(args, "due_after", None))
        if due_before or due_after:
            due = record.get("due")
            if not due:
                return False
            if due_before and due > due_before:
                return False
            if due_after and due < due_after:
                return False
        ref = getattr(args, "ref", None)
        if ref:
            refs = record.get("refs") or []
            if not any(ref == r or ref in r for r in refs):
                return False
        text = getattr(args, "text", None)
        if text and not text_matches(record, text):
            return False
        return all(match_condition(record, cond) for cond in conds)

    return [r for r in records if keep(r)]


def sort_records(records: list[dict]) -> list[dict]:
    return sorted(records, key=lambda r: (r.get("due") or FAR_FUTURE, str(r.get("id", ""))))


# --------------------------------------------------------------------------
# Wyjscie

def project(records: list[dict], select: str | None) -> list[dict]:
    if not select:
        return records
    fields = [f.strip() for f in select.split(",") if f.strip()]
    return [{f: get_path(r, f) for f in fields} for r in records]


def emit(records: list[dict], fmt: str, select: str | None = None) -> None:
    if fmt == "count":
        print(len(records))
        return
    if fmt == "ids":
        for record in records:
            print(record.get("id", ""))
        return
    rows = project(records, select)
    if fmt == "table":
        print(render_table(rows))
        return
    print(json.dumps(rows, ensure_ascii=False, indent=2))


def render_table(rows: list[dict]) -> str:
    if not rows:
        return "(brak)"
    headers: list[str] = []
    for row in rows:
        for key in row:
            if key not in headers:
                headers.append(key)
    def cell(value: Any) -> str:
        if isinstance(value, list):
            return ", ".join(str(v) for v in value)
        return "" if value is None else str(value)
    widths = {h: max(len(h), *(len(cell(r.get(h))) for r in rows)) for h in headers}
    lines = [" | ".join(h.ljust(widths[h]) for h in headers),
             "-+-".join("-" * widths[h] for h in headers)]
    for row in rows:
        lines.append(" | ".join(cell(row.get(h)).ljust(widths[h]) for h in headers))
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Mutacje

def normalize(record: dict, existing: dict | None = None) -> dict:
    if not isinstance(record, dict):
        raise LedgerError(f"Rekord musi byc obiektem JSON, dostalem: {type(record).__name__}")
    record_id = record.get("id")
    kind = record.get("kind") or (existing or {}).get("kind")
    if not record_id:
        raise LedgerError("Rekord bez 'id'")
    if not kind:
        raise LedgerError(f"Rekord {record_id}: brak 'kind'")

    merged = dict(existing) if existing else {}
    incoming = dict(record)

    refs = list(merged.get("refs") or [])
    for ref in incoming.pop("refs", []) or []:
        if ref not in refs:
            refs.append(ref)

    history = list(merged.get("history") or [])
    for entry in incoming.pop("history", []) or []:
        if entry not in history:
            history.append(entry)

    data = dict(merged.get("data") or {})
    data.update(incoming.pop("data", {}) or {})

    merged.update(incoming)
    merged["refs"] = refs
    merged["history"] = history
    merged["data"] = data
    merged.setdefault("created", today())
    merged["updated"] = today()
    merged.setdefault("status", "open" if kind == AGENT_KIND else "open")
    merged.setdefault("due", None)
    merged.setdefault("note", None)

    if kind == AGENT_KIND:
        for field in ("title", "context", "source"):
            if not merged.get(field):
                raise LedgerError(f"Rekord {record_id}: brak wymaganego pola '{field}'")
    if merged.get("due"):
        merged["due"] = resolve_date(merged["due"])

    ordered = {f: merged[f] for f in CORE_FIELDS if f in merged}
    ordered.update({k: v for k, v in merged.items() if k not in ordered})
    return ordered


def cmd_upsert(store: Store, args: argparse.Namespace) -> int:
    raw = sys.stdin.read() if args.stdin else args.json
    if not raw or not raw.strip():
        raise LedgerError("Brak danych wejsciowych (--stdin albo --json)")
    payload = json.loads(raw)
    incoming = payload if isinstance(payload, list) else [payload]

    created, updated = [], []
    with store.lock():
        buckets: dict[Path, list[dict]] = {}
        index: dict[str, tuple[Path, int]] = {}
        for path in [store.tasks_path, *store.mirror_files()]:
            buckets[path] = store.read_jsonl(path)
            for pos, record in enumerate(buckets[path]):
                index[str(record.get("id"))] = (path, pos)

        for record in incoming:
            record_id = str(record.get("id", ""))
            if record_id in index:
                path, pos = index[record_id]
                merged = normalize(record, buckets[path][pos])
                target = store.path_for(merged)
                if target == path:
                    buckets[path][pos] = merged
                else:  # zmiana kind/source przenosi rekord miedzy plikami
                    buckets[path].pop(pos)
                    buckets.setdefault(target, store.read_jsonl(target) if target not in buckets else buckets[target])
                    buckets[target].append(merged)
                    index = _reindex(buckets)
                updated.append(record_id)
            else:
                merged = normalize(record)
                target = store.path_for(merged)
                if target not in buckets:
                    buckets[target] = store.read_jsonl(target)
                buckets[target].append(merged)
                index[record_id] = (target, len(buckets[target]) - 1)
                created.append(record_id)

        for path, records in buckets.items():
            store.write_jsonl(path, records)
        write_view(store)

    print(json.dumps({"created": created, "updated": updated}, ensure_ascii=False))
    return 0


def _reindex(buckets: dict[Path, list[dict]]) -> dict[str, tuple[Path, int]]:
    index: dict[str, tuple[Path, int]] = {}
    for path, records in buckets.items():
        for pos, record in enumerate(records):
            index[str(record.get("id"))] = (path, pos)
    return index


def cmd_close(store: Store, args: argparse.Namespace) -> int:
    if args.outcome not in OUTCOMES:
        raise LedgerError(f"--outcome musi byc jednym z: {', '.join(OUTCOMES)}")
    wanted = set(args.id)
    closed, missing = [], []

    with store.lock():
        buckets = {path: store.read_jsonl(path) for path in [store.tasks_path, *store.mirror_files()]}
        moved: list[dict] = []
        for path, records in buckets.items():
            keep = []
            for record in records:
                if str(record.get("id")) in wanted:
                    record["status"] = "done"
                    record["outcome"] = args.outcome
                    record["closed"] = today()
                    record["updated"] = today()
                    if args.reason:
                        # Przy zamknietej sprawie interesuje nas, JAK sie skonczyla,
                        # a nie po co kiedys wisiala - wiec `reason` przejmuje powod
                        # zamkniecia, a poprzedni zostaje w historii.
                        previous = record.get("reason")
                        note = f"{today()} zamkniete ({args.outcome}): {args.reason}"
                        if previous and previous != args.reason:
                            note += f" [wcześniej: {previous}]"
                        record["history"] = list(record.get("history") or []) + [note]
                        record["reason"] = args.reason
                    moved.append(record)
                    closed.append(str(record.get("id")))
                else:
                    keep.append(record)
            buckets[path] = keep

        missing = sorted(wanted - set(closed))
        if moved:
            for path, records in buckets.items():
                store.write_jsonl(path, records)
            store.append_jsonl(store.archive_path, moved)
            write_view(store)

    print(json.dumps({"closed": closed, "not_found": missing}, ensure_ascii=False))
    return 0 if not missing else 1


# --------------------------------------------------------------------------
# Odczyt

def cmd_query(store: Store, args: argparse.Namespace) -> int:
    records = store.load_active()
    if getattr(args, "include_archived", False):
        records.extend(store.load_archive())
    records = sort_records(filter_records(records, args))
    if args.limit:
        records = records[: args.limit]
    emit(records, args.format, args.select)
    return 0


def cmd_due(store: Store, args: argparse.Namespace) -> int:
    args.due_before = args.date or "today"
    args.due_after = None
    args.status = args.status or "open,waiting"
    args.kind = args.kind or AGENT_KIND
    args.include_archived = False
    return cmd_query(store, args)


def cmd_get(store: Store, args: argparse.Namespace) -> int:
    for record in store.load_active() + store.load_archive():
        if str(record.get("id")) == args.id:
            print(json.dumps(record, ensure_ascii=False, indent=2))
            return 0
    print(json.dumps({"error": "not_found", "id": args.id}, ensure_ascii=False))
    return 1


def cmd_find(store: Store, args: argparse.Namespace) -> int:
    """Szuka po aktywnych I archiwum - odpowiada na pytanie
    'czy tej sprawy juz kiedys nie obslugiwalismy?', ktore jest sercem deduplikacji."""
    hits = []
    for record in store.load_active():
        if text_matches(record, args.query):
            hits.append({**record, "archived": False})
    for record in store.load_archive():
        if text_matches(record, args.query):
            hits.append({**record, "archived": True})
    hits = sort_records(hits)
    if args.limit:
        hits = hits[: args.limit]
    emit(hits, args.format, args.select)
    return 0


# --------------------------------------------------------------------------
# Widok i walidacja

def bucket_for(due: str | None, ref: str) -> str:
    if not due:
        return "Bez daty"
    if due < ref:
        return "Zalegle"
    if due == ref:
        return "Dzis"
    week = (dt.date.fromisoformat(ref) + dt.timedelta(days=7)).isoformat()
    return "Ten tydzien" if due <= week else "Pozniej"


def write_view(store: Store) -> None:
    records = [r for r in store.load_active() if r.get("kind") == AGENT_KIND]
    records = sort_records(records)
    ref = today()
    groups: dict[str, list[dict]] = {}
    for record in records:
        groups.setdefault(bucket_for(record.get("due"), ref), []).append(record)

    lines = [
        "# Otwarte sprawy",
        "",
        "> [!warning] Plik generowany przez `scripts/ledger.py` - nie edytuj recznie.",
        f"> Wygenerowano: {now()} · rekordow: {len(records)}",
        "",
    ]
    for bucket in ("Zalegle", "Dzis", "Ten tydzien", "Pozniej", "Bez daty"):
        items = groups.get(bucket)
        if not items:
            continue
        lines += [f"## {bucket} ({len(items)})", "",
                  "| Termin | Kontekst | Sprawa | Powod | Powiazania |",
                  "|--------|----------|--------|-------|------------|"]
        for record in items:
            refs = ", ".join(f"`{r}`" for r in (record.get("refs") or [])) or "-"
            lines.append(
                f"| {record.get('due') or '-'} | {record.get('context') or '-'} | "
                f"{record.get('title') or record.get('id')} | {record.get('reason') or '-'} | {refs} |"
            )
        lines.append("")
    if not records:
        lines += ["Nic nie wisi.", ""]

    path = store.root / VIEW_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".md.tmp")
    tmp.write_text("\n".join(lines), encoding="utf-8")
    os.replace(tmp, path)


def cmd_render(store: Store, args: argparse.Namespace) -> int:
    with store.lock():
        write_view(store)
    print(json.dumps({"rendered": str(store.root / VIEW_FILE)}, ensure_ascii=False))
    return 0


def cmd_validate(store: Store, args: argparse.Namespace) -> int:
    """Ostrzega, nie blokuje - rejestr ma byc pomocny, nie formalistyczny."""
    warnings: list[str] = []
    active = store.load_active()

    seen: dict[str, int] = {}
    for record in active:
        seen[str(record.get("id"))] = seen.get(str(record.get("id")), 0) + 1
    warnings += [f"duplikat id: {rid} (x{count})" for rid, count in seen.items() if count > 1]

    mirror_ids = {str(r.get("id")) for r in active if r.get("kind") != AGENT_KIND}
    ref_owners: dict[str, list[str]] = {}
    for record in active:
        rid = str(record.get("id"))
        for field in ("id", "kind"):
            if not record.get(field):
                warnings.append(f"{rid}: brak pola rdzenia '{field}'")
        if record.get("kind") == AGENT_KIND:
            for field in ("title", "context", "source", "status"):
                if not record.get(field):
                    warnings.append(f"{rid}: brak pola rdzenia '{field}'")
            due = record.get("due")
            if due and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(due)):
                warnings.append(f"{rid}: 'due' nie jest data ISO: {due}")
            for ref in record.get("refs") or []:
                if ref.startswith("todoist:") and ref not in mirror_ids:
                    warnings.append(f"{rid}: ref {ref} nie ma lustra (uruchom todoist-sync.py)")
                ref_owners.setdefault(ref, []).append(rid)

    # Ten sam watek albo to samo zadanie w kilku sprawach to niemal zawsze
    # duplikat - jedna sprawa rozbita na kilka rekordow. To jest dokladnie ten
    # blad, ktory rejestr ma eliminowac, wiec warto go widziec.
    for ref, owners in ref_owners.items():
        if len(owners) > 1:
            co = "watek" if ref.startswith("gmail:") else "zadanie"
            warnings.append(
                f"{co} {ref} wisi w kilku sprawach: {', '.join(owners)} - podejrzenie duplikatu"
            )

    print(json.dumps({"records": len(active), "warnings": warnings}, ensure_ascii=False, indent=2))
    return 0


# --------------------------------------------------------------------------
# CLI

def add_filter_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--kind")
    parser.add_argument("--context")
    parser.add_argument("--source")
    parser.add_argument("--status")
    parser.add_argument("--due-before", dest="due_before")
    parser.add_argument("--due-after", dest="due_after")
    parser.add_argument("--ref")
    parser.add_argument("--text")
    parser.add_argument("--where", action="append",
                        help="'sciezka OP wartosc' (OP: = != < <= > >= ~), 'sciezka in a,b', 'sciezka exists'")
    parser.add_argument("--select")
    parser.add_argument("--format", choices=["json", "ids", "table", "count"], default="json")
    parser.add_argument("--limit", type=int)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Rejestr otwartych spraw agenta")
    parser.add_argument("--store", default=os.environ.get("LEDGER_DIR", str(DEFAULT_STORE)))
    sub = parser.add_subparsers(dest="command", required=True)

    p_query = sub.add_parser("query", help="filtrowanie rekordow")
    add_filter_args(p_query)
    p_query.add_argument("--include-archived", action="store_true", dest="include_archived")
    p_query.set_defaults(func=cmd_query)

    p_due = sub.add_parser("due", help="co dojrzalo (skrot na query)")
    add_filter_args(p_due)
    p_due.add_argument("--date", help="domyslnie dzis")
    p_due.set_defaults(func=cmd_due)

    p_get = sub.add_parser("get", help="jeden rekord po id")
    p_get.add_argument("id")
    p_get.set_defaults(func=cmd_get)

    p_find = sub.add_parser("find", help="szukanie po aktywnych i archiwum")
    p_find.add_argument("query")
    p_find.add_argument("--select")
    p_find.add_argument("--format", choices=["json", "ids", "table", "count"], default="json")
    p_find.add_argument("--limit", type=int, default=20)
    p_find.set_defaults(func=cmd_find)

    p_upsert = sub.add_parser("upsert", help="wstaw/scal rekordy (JSON: obiekt albo lista)")
    p_upsert.add_argument("--stdin", action="store_true")
    p_upsert.add_argument("--json")
    p_upsert.set_defaults(func=cmd_upsert)

    p_close = sub.add_parser("close", help="zamknij sprawe (przenosi do archiwum)")
    p_close.add_argument("--id", action="append", required=True)
    p_close.add_argument("--outcome", required=True, choices=list(OUTCOMES))
    p_close.add_argument("--reason")
    p_close.set_defaults(func=cmd_close)

    p_render = sub.add_parser("render", help="regeneruj widok Otwarte.md")
    p_render.set_defaults(func=cmd_render)

    p_validate = sub.add_parser("validate", help="kontrola spojnosci (ostrzega, nie blokuje)")
    p_validate.set_defaults(func=cmd_validate)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    store = Store(Path(args.store).expanduser())
    try:
        return args.func(store, args)
    except LedgerError as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2
    except json.JSONDecodeError as exc:
        print(json.dumps({"error": f"niepoprawny JSON na wejsciu: {exc}"}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
