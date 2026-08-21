#!/usr/bin/env python3
"""Migracja jednorazowa: labelki Gmaila -> rekordy w ledgerze.

Stan "co jest odlozone i do kiedy" oraz "ktory watek ma jakie zadanie" siedzial
w labelkach `AI/Defer/<data>` i `TODO/<taskId>`. Ten skrypt czyta je z Gmaila
(przez MCP po HTTP) i zamienia na rekordy ledgera. Jest idempotentny: mozna go
puscic kilka razy, `ledger upsert` scala po id.

    migrate-ledger.py --dry-run     # pokaz co powstanie
    migrate-ledger.py               # zapisz rekordy do ledgera
    migrate-ledger.py --emit        # wypisz rekordy na stdout (bez zapisu)

Skrypt NIE kasuje labelek - to osobny, swiadomy krok:
    gmail-mcp.sh cleanup_labels '{"account":"...","prefix":"AI/Defer/","onlyEmpty":false}'
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import unicodedata
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ledger  # noqa: E402

MCP_URL = "http://localhost:4002/mcp"
ACCOUNTS = {"kedrzu@gmail.com": "personal", "kedrzu@sigma.clinic": "work"}
DEFER_RE = re.compile(r"^AI/Defer/(\d{4}-\d{2}-\d{2})$")
TODO_RE = re.compile(r"^TODO/(.+)$")


def mcp_call(tool: str, arguments: dict) -> str:
    payload = {
        "jsonrpc": "2.0", "id": 2, "method": "tools/call",
        "params": {"name": tool, "arguments": arguments},
    }
    request = urllib.request.Request(
        MCP_URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Accept": "application/json, text/event-stream"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read().decode()
    for line in body.splitlines():
        line = line.strip()
        if line.startswith("data:"):
            line = line[5:].strip()
        if not line.startswith("{"):
            continue
        data = json.loads(line)
        if data.get("id") != 2:
            continue
        if "error" in data:
            raise RuntimeError(json.dumps(data["error"], ensure_ascii=False))
        return "\n".join(c.get("text", "") for c in data.get("result", {}).get("content", []))
    raise RuntimeError(f"Brak odpowiedzi z MCP: {body[:300]}")


def slugify(text: str, limit: int = 48) -> str:
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = re.sub(r"[^a-zA-Z0-9]+", "-", text).strip("-").lower()
    return (text[:limit].rstrip("-")) or "watek"


def collect(account: str, context: str) -> dict[str, dict]:
    """Zwraca {threadId: {...}} ze stanem wyczytanym z labelek."""
    labels = json.loads(mcp_call("list_labels", {"account": account}))
    names = [l["name"] for l in (labels.get("labels") or labels)]

    threads: dict[str, dict] = {}
    for name in names:
        defer = DEFER_RE.match(name)
        todo = TODO_RE.match(name)
        if not (defer or todo):
            continue
        found = json.loads(mcp_call("search_threads", {
            "account": account, "query": f'label:"{name}"', "maxResults": 100,
        }))
        for thread in found.get("threads", []):
            entry = threads.setdefault(thread["id"], {
                "thread_id": thread["id"],
                "subject": thread.get("subject") or "(bez tematu)",
                "from": thread.get("from") or "",
                "date": thread.get("date") or "",
                "context": context,
                "due": None,
                "task_id": None,
            })
            if defer:
                # Watek moze miec kilka labelek defer (stare + nowa) - liczy sie
                # najpozniejsza, bo to ona byla efektywna.
                if not entry["due"] or defer.group(1) > entry["due"]:
                    entry["due"] = defer.group(1)
            if todo:
                entry["task_id"] = todo.group(1)
    return threads


def group_by_case(threads: dict[str, dict]) -> list[list[dict]]:
    """Watki dzielace jedno zadanie Todoist to JEDNA sprawa.

    Stary schemat wieszal labelke `TODO/<id>` na kazdym watku z osobna, wiec
    faktura + dwa ponaglenia wygladaly jak trzy niezalezne rzeczy. Wlasnie ta
    fragmentacja rodzila duplikaty - migracja jest pierwsza okazja, zeby ja
    scalic, zamiast przenosic balagan jeden do jednego."""
    by_task: dict[str, list[dict]] = {}
    singles: list[list[dict]] = []
    for entry in threads.values():
        if entry["task_id"]:
            by_task.setdefault(entry["task_id"], []).append(entry)
        else:
            singles.append([entry])
    return list(by_task.values()) + singles


def to_records(threads: dict[str, dict], used: set[str]) -> list[dict]:
    """`used` jest wspolne dla wszystkich kont - ten sam temat potrafi przyjsc
    i na personal, i na work ('Zaproszenie na...'), a to sa rozne sprawy."""
    records = []
    for group in group_by_case(threads):
        # Najswiezszy watek nadaje sprawie tytul i date powrotu.
        group.sort(key=lambda e: e.get("date") or "")
        lead = group[-1]

        base = slugify(lead["subject"])
        record_id = base
        suffix = 2
        while record_id in used:
            record_id = f"{base}-{suffix}"
            suffix += 1
        used.add(record_id)

        refs = [f"gmail:{lead['context']}:thread:{e['thread_id']}" for e in group]
        if lead["task_id"]:
            refs.append(f"todoist:task:{lead['task_id']}")

        due = max((e["due"] for e in group if e["due"]), default=None)
        why = "zadanie w Todoist" if lead["task_id"] else "odlozone do daty"
        history = [f"{ledger.today()} zmigrowane z labelek AI/Defer/TODO"]
        if len(group) > 1:
            history.append(
                f"{ledger.today()} scalono {len(group)} watkow dzielacych jedno zadanie"
            )

        records.append({
            "id": record_id,
            "kind": "task",
            "context": lead["context"],
            "source": "gmail",
            "title": lead["subject"],
            "status": "open",
            "due": due or ledger.today(),
            "reason": f"migracja z labelek Gmaila ({why})",
            "refs": refs,
            "history": history,
            "data": {
                "migrated": True,
                "from": lead["from"],
                "todoist_task_id": lead["task_id"],
                "threads": len(group),
            },
        })
    return records


REMINDERS_PATH = Path("obsidian/Asystent/Memory/EmailReminders.md")
THREAD_LINK_RE = re.compile(r"#inbox/([0-9a-f]+)")
ITEM_RE = re.compile(r"^- \[ \] (.+)$")
DATE_HEADING_RE = re.compile(r"^#{2,3} (\d{4}-\d{2}-\d{2})")


def collect_reminders(existing_refs: dict[str, str]) -> list[dict]:
    """Przenosi otwarte przypomnienia z EmailReminders.md na rekordy.

    Plik jest logiem kolejnych rutyn, wiec ta sama sprawa powtarza sie w nim
    wielokrotnie - dedup po watku i po znormalizowanym tytule jest tu
    obowiazkowy, inaczej przenieslibysmy 47 wpisow zamiast realnych spraw."""
    if not REMINDERS_PATH.is_file():
        return []
    text = REMINDERS_PATH.read_text(encoding="utf-8")
    start = text.index("## Oczekujące")
    stop = min((text.index(m) for m in ("## Zweryfikowane", "## Rozwiązane") if m in text),
               default=len(text))
    section = text[start:stop]

    items: dict[str, dict] = {}
    heading_date = None
    current: dict | None = None
    for line in section.splitlines():
        heading = DATE_HEADING_RE.match(line)
        if heading:
            heading_date = heading.group(1)
            current = None
            continue
        item = ITEM_RE.match(line)
        if item:
            raw = item.group(1)
            context = "work" if "[Work]" in raw else "personal"
            # Najpierw zdejmij marker konta (**[Personal]**), dopiero potem emoji
            # i resztę ozdobników - odwrotna kolejność rozjeżdża gwiazdki.
            title = re.sub(r"\*\*\[[^\]]+\]\*\*", "", raw)
            title = re.sub(r"^[\W_]+", "", title).strip(" *")
            key = slugify(title, 60)
            current = items.setdefault(key, {
                "title": title, "context": context, "due": heading_date,
                "threads": [], "reason": "",
            })
            # log rutyn idzie od najnowszych - pierwszy wpis wygrywa date
            continue
        if current is None:
            continue
        for thread_id in THREAD_LINK_RE.findall(line):
            if thread_id not in current["threads"]:
                current["threads"].append(thread_id)
        note = re.search(r"(?:Kontekst|Stan|Powód)\s*:\s*(.+)", line)
        if note and not current["reason"]:
            current["reason"] = note.group(1).strip()[:200]

    records, merged = [], 0
    for key, item in items.items():
        refs = [f"gmail:{item['context']}:thread:{t}" for t in item["threads"]]
        owner = next((existing_refs[r] for r in refs if r in existing_refs), None)
        if owner:
            # Watek juz ma sprawe (zmigrowana z labelek) - dopnij do niej, nie duplikuj.
            merged += 1
            records.append({
                "id": owner, "kind": "task",
                "history": [f"{ledger.today()} scalono przypomnienie z EmailReminders.md"],
                "data": {"follow_up": item["reason"] or item["title"]},
            })
            continue
        records.append({
            "id": key, "kind": "task", "context": item["context"], "source": "gmail",
            "title": item["title"], "status": "open",
            "due": item["due"] or ledger.today(),
            "reason": item["reason"] or "przypomnienie przeniesione z EmailReminders.md",
            "refs": refs,
            "history": [f"{ledger.today()} zmigrowane z EmailReminders.md"],
            "data": {"migrated": True, "type": "follow-up"},
        })
    print(f"EmailReminders.md: {len(items)} spraw ({merged} dopiętych do istniejących)",
          file=sys.stderr)
    return records


def main() -> int:
    parser = argparse.ArgumentParser(description="Migracja labelek Gmaila do ledgera")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--emit", action="store_true", help="wypisz rekordy JSON na stdout")
    parser.add_argument("--reminders", action="store_true",
                        help="migruj wyłącznie EmailReminders.md (labelki pomiń)")
    args = parser.parse_args()

    all_records: list[dict] = []
    used: set[str] = set()

    if args.reminders:
        store = ledger.Store(ledger.DEFAULT_STORE)
        existing = {ref: str(r.get("id"))
                    for r in ledger.Store.read_jsonl(store.tasks_path)
                    for ref in (r.get("refs") or [])}
        all_records = collect_reminders(existing)
        return _finish(all_records, args)

    for account, context in ACCOUNTS.items():
        threads = collect(account, context)
        records = to_records(threads, used)
        print(f"{account}: {len(threads)} watkow z labelkami -> {len(records)} rekordow",
              file=sys.stderr)
        all_records.extend(records)

    return _finish(all_records, args)


def _finish(records: list[dict], args: argparse.Namespace) -> int:
    if args.emit or args.dry_run:
        print(json.dumps(records, ensure_ascii=False, indent=2))
        if args.dry_run:
            return 0
    if args.emit:
        return 0
    result = subprocess.run(
        [sys.executable, str(Path(__file__).parent / "ledger.py"), "upsert", "--stdin"],
        input=json.dumps(records, ensure_ascii=False),
        text=True, capture_output=True,
    )
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
