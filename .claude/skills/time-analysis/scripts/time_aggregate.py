#!/usr/bin/env python3
"""Deterministyczna agregacja i walidacja logu czasu (Etap 2 skilla time-analysis).

Model robi CAŁĄ interpretację (rekonstrukcję osi czasu i kategoryzację) i emituje
JSON zgodny z kontraktem opisanym w SKILL.md. Ten skrypt robi WYŁĄCZNIE matematykę
i walidację — zero wiedzy domenowej, zero polskiego NLP, zero priorów. Dzięki temu
arytmetyka (sumy minut, procenty, wykrywanie nakładek/dziur) jest deterministyczna,
a nie liczona "w pamięci" przez LLM.

Użycie:
    python3 time_aggregate.py --in <model.json> --out <results.json> [--pretty]

Wejście:  JSON wyemitowany przez model po Etapie 1+2 (patrz SKILL.md, sekcja "Kontrakt").
Wyjście:  results.json (liczby) + krótkie podsumowanie na stdout.
Exit !=0: tylko przy zepsutym/niezgodnym wejściu — wtedy model poprawia log i powtarza.

Tylko biblioteka standardowa (json, argparse, sys).
"""

import argparse
import json
import sys

# Bloki pór dnia: (etykieta, start_godz, end_godz). Noc owija się przez północ.
TIME_BLOCKS = [
    ("Rano", 5, 9),
    ("Przedpołudnie", 9, 12),
    ("Popołudnie", 12, 17),
    ("Wieczór", 17, 22),
    ("Noc", 22, 29),  # 22:00–05:00 (29 = 24 + 5), liczone modulo 1440
]

COUNTING_TYPES = {"activity", "sleep"}  # typy wnoszące minuty do kategorii


class InputError(Exception):
    """Wejście nie spełnia kontraktu — skrypt kończy się kodem != 0."""


def parse_hhmm(value, field):
    """'HH:MM' -> minuty od północy (int). Rzuca InputError przy złym formacie."""
    if not isinstance(value, str) or ":" not in value:
        raise InputError(f"Pole {field} musi być 'HH:MM', dostałem: {value!r}")
    h, _, m = value.partition(":")
    try:
        h, m = int(h), int(m)
    except ValueError:
        raise InputError(f"Pole {field} nie jest liczbą: {value!r}")
    if not (0 <= h <= 23 and 0 <= m <= 59):
        raise InputError(f"Pole {field} poza zakresem zegara: {value!r}")
    return h * 60 + m


def row_span(row, day_date):
    """Zwraca (start_min, end_min, computed_minutes) dla wiersza logu.

    Tylko wiersz type=='sleep' może przekraczać północ (end < start -> +1440).
    Dla innych typów end < start to błąd wejścia.
    """
    start = parse_hhmm(row.get("start"), f"{day_date}/{row.get('id','?')}/start")
    end = parse_hhmm(row.get("end"), f"{day_date}/{row.get('id','?')}/end")
    if end < start:
        if row.get("type") == "sleep":
            end += 1440
        else:
            raise InputError(
                f"{day_date}/{row.get('id','?')}: end < start ({row.get('start')} > "
                f"{row.get('end')}), a type != 'sleep'"
            )
    return start, end, end - start


def split_across_blocks(start, end):
    """Rozdziela [start, end) (minuty od północy, end może być >1440) na bloki pór dnia.

    Zwraca {etykieta_bloku: minuty}.
    """
    out = {}
    for minute in range(start, end):
        hod = (minute % 1440) // 60  # godzina doby
        for label, b0, b1 in TIME_BLOCKS:
            lo, hi = b0 % 24, b1  # hi może być >24 dla Nocy
            in_block = (lo <= hod < hi) or (hi > 24 and (hod < (hi - 24)))
            if in_block:
                out[label] = out.get(label, 0) + 1
                break
    return out


def round1(x):
    return round(x, 1)


def aggregate(data):
    if not isinstance(data, dict):
        raise InputError("Wejście musi być obiektem JSON.")
    categories = data.get("categories")
    days = data.get("days")
    if not isinstance(categories, list) or not categories:
        raise InputError("Brak niepustej listy 'categories'.")
    if not isinstance(days, list):
        raise InputError("Brak listy 'days'.")

    cat_label = {}
    zero_time = set()
    for c in categories:
        cid = c.get("id")
        if not cid:
            raise InputError(f"Kategoria bez 'id': {c!r}")
        cat_label[cid] = c.get("label", cid)
        if c.get("zero_time"):
            zero_time.add(cid)

    totals_by_cat = {cid: 0 for cid in cat_label}
    by_timeofday = {label: {} for label, *_ in TIME_BLOCKS}
    by_day = []
    duration_mismatches = []
    overlaps = []
    holes = []
    self_report_drift = []
    unknown_categories = set()

    total_tracked = 0
    total_untracked = 0

    for day in days:
        date = day.get("date", "?")
        log = day.get("log", [])
        if not isinstance(log, list):
            raise InputError(f"{date}: 'log' musi być listą.")

        day_by_cat = {}
        day_tracked = 0
        day_untracked = 0
        day_reflections = 0
        spans = []  # (start, end, type, id) dla wykrywania nakładek/dziur

        for row in log:
            rtype = row.get("type", "activity")
            cid = row.get("category")
            start, end, computed = row_span(row, date)
            declared = row.get("duration_min")

            if isinstance(declared, (int, float)) and abs(declared - computed) > 1:
                duration_mismatches.append({
                    "date": date, "id": row.get("id"),
                    "declared": declared, "computed": computed,
                    "start": row.get("start"), "end": row.get("end"),
                })
            minutes = computed

            if rtype == "reflection":
                day_reflections += 1
                continue  # zero_time z definicji, nie wnosi minut ani spanu
            if rtype == "untracked":
                day_untracked += minutes
                spans.append((start, end, rtype, row.get("id")))
                continue

            # type in COUNTING_TYPES (activity / sleep)
            if rtype not in COUNTING_TYPES:
                raise InputError(
                    f"{date}/{row.get('id','?')}: nieznany type {rtype!r} "
                    "(dozwolone: activity, sleep, reflection, untracked)"
                )
            if cid is None or cid not in cat_label:
                unknown_categories.add(str(cid))
                cid = cid if cid is not None else "?"
            if cid in zero_time:
                # kategoria zero_time nie powinna nieść minut — zgłoś jako mismatch
                if minutes > 0:
                    duration_mismatches.append({
                        "date": date, "id": row.get("id"),
                        "note": f"kategoria zero_time '{cid}' niesie {minutes} min",
                    })
                continue

            day_by_cat[cid] = day_by_cat.get(cid, 0) + minutes
            day_tracked += minutes
            spans.append((start, end, rtype, row.get("id")))

            if cid in totals_by_cat:
                totals_by_cat[cid] += minutes
            for label, mins in split_across_blocks(start, end).items():
                by_timeofday[label][cid] = by_timeofday[label].get(cid, 0) + mins

        # nakładki i dziury w obrębie dnia (po posortowaniu po starcie)
        spans.sort()
        for i in range(1, len(spans)):
            prev_end = spans[i - 1][1]
            cur_start = spans[i][0]
            if cur_start < prev_end:
                overlaps.append({
                    "date": date,
                    "a": spans[i - 1][3], "b": spans[i][3],
                    "overlap_min": prev_end - cur_start,
                })
            elif cur_start > prev_end:
                gap = cur_start - prev_end
                holes.append({
                    "date": date,
                    "after": spans[i - 1][3], "before": spans[i][3],
                    "from": f"{prev_end // 60:02d}:{prev_end % 60:02d}",
                    "to": f"{cur_start // 60:02d}:{cur_start % 60:02d}",
                    "minutes": gap,
                })
                day_untracked += gap

        # cross-check self-report vs rekonstrukcja
        for sr in day.get("self_reported", []) or []:
            cat = sr.get("category")
            reported = sr.get("minutes")
            if not isinstance(reported, (int, float)):
                continue
            reconstructed = day_by_cat.get(cat, 0)
            self_report_drift.append({
                "date": date, "category": cat,
                "reported": reported, "reconstructed": reconstructed,
                "delta": reconstructed - reported,
            })

        total_tracked += day_tracked
        total_untracked += day_untracked
        by_day.append({
            "date": date,
            "weekday": day.get("weekday"),
            "tracked": day_tracked,
            "untracked": day_untracked,
            "reflections": day_reflections,
            "by_category": day_by_cat,
        })

    accounted = total_tracked + total_untracked
    coverage_pct = round1(100 * total_tracked / accounted) if accounted else 0.0

    totals_list = []
    for cid, mins in sorted(totals_by_cat.items(), key=lambda kv: -kv[1]):
        if mins == 0 and cid in zero_time:
            continue
        totals_list.append({
            "id": cid,
            "label": cat_label.get(cid, cid),
            "minutes": mins,
            "hours": round1(mins / 60),
            "pct_tracked": round1(100 * mins / total_tracked) if total_tracked else 0.0,
        })

    # macierz dzień × kategoria (kolejność kategorii wg totali malejąco)
    ordered_cats = [t["id"] for t in totals_list]
    matrix_header = ["data"] + [cat_label.get(c, c) for c in ordered_cats]
    matrix_rows = []
    for d in by_day:
        matrix_rows.append([d["date"]] + [d["by_category"].get(c, 0) for c in ordered_cats])

    results = {
        "schema_version": 1,
        "range": data.get("range"),
        "generated_at": data.get("generated_at"),
        "n_days": len(days),
        "totals_by_category": totals_list,
        "by_day": by_day,
        "by_timeofday": by_timeofday,
        "day_matrix": {"header": matrix_header, "rows": matrix_rows},
        "checks": {
            "total_tracked_min": total_tracked,
            "total_untracked_min": total_untracked,
            "coverage_pct": coverage_pct,
            "duration_mismatches": duration_mismatches,
            "overlaps": overlaps,
            "holes": holes,
            "self_report_drift": self_report_drift,
            "unknown_categories": sorted(unknown_categories),
        },
        "warnings": list(data.get("warnings", []) or []),
    }
    return results


def summary_text(r):
    c = r["checks"]
    lines = []
    rng = r.get("range") or {}
    lines.append(f"Zakres: {rng.get('start','?')} → {rng.get('end','?')}  ({r['n_days']} dni)")
    lines.append(
        f"Tracked: {c['total_tracked_min']} min ({round1(c['total_tracked_min']/60)} h) | "
        f"Untracked: {c['total_untracked_min']} min | Pokrycie: {c['coverage_pct']}%"
    )
    lines.append("Top kategorie:")
    for t in r["totals_by_category"][:8]:
        lines.append(f"  - {t['label']}: {t['hours']} h ({t['pct_tracked']}%)")
    flags = []
    if c["duration_mismatches"]:
        flags.append(f"{len(c['duration_mismatches'])} rozjazdów duration_min")
    if c["overlaps"]:
        flags.append(f"{len(c['overlaps'])} nakładek")
    if c["holes"]:
        flags.append(f"{len(c['holes'])} dziur (untracked)")
    if c["unknown_categories"]:
        flags.append(f"nieznane kategorie: {', '.join(c['unknown_categories'])}")
    lines.append("Flagi: " + ("; ".join(flags) if flags else "brak"))
    if c["self_report_drift"]:
        lines.append("Self-report vs rekonstrukcja:")
        for d in c["self_report_drift"]:
            lines.append(
                f"  - {d['date']} {d['category']}: deklarowane {d['reported']} / "
                f"odtworzone {d['reconstructed']} (Δ{d['delta']:+d})"
            )
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Agregacja i walidacja logu czasu.")
    ap.add_argument("--in", dest="inp", required=True, help="ścieżka do model.json")
    ap.add_argument("--out", dest="out", required=True, help="ścieżka do results.json")
    ap.add_argument("--pretty", action="store_true", help="wcięcia w results.json")
    args = ap.parse_args(argv)

    try:
        with open(args.inp, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"BŁĄD: niepoprawny JSON w {args.inp}: {e}", file=sys.stderr)
        return 2
    except OSError as e:
        print(f"BŁĄD: nie mogę otworzyć {args.inp}: {e}", file=sys.stderr)
        return 2

    try:
        results = aggregate(data)
    except InputError as e:
        print(f"BŁĄD WEJŚCIA: {e}", file=sys.stderr)
        return 3

    try:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2 if args.pretty else None)
    except OSError as e:
        print(f"BŁĄD: nie mogę zapisać {args.out}: {e}", file=sys.stderr)
        return 2

    print(summary_text(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
