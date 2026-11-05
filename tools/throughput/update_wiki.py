#!/usr/bin/env python3
"""Turn a ThroughputRunner CSV into new tables on the BLE-Throughput wiki page.

One table per API release, numbered after the last "# Test Results N" on the page and inserted above
"# Notes". Each row notes the API release in an "API Release" column after Equipment. A later run for the same release adds its rows to that
release's table (grouped by hardware, Shimmer3 first); rows already in it are not repeated, and no
row is ever removed. Other tables are never touched.

Dry run by default: prints the diff and changes nothing. --commit commits in the local wiki clone.
It never pushes. Push the wiki yourself after reading the diff.

    python update_wiki.py --csv results.csv --release ShimmerSwiftAPI_v1.1.0 --wiki ./SwiftAPI.wiki

The CSV is the app's export: the wiki's own columns, one row per setting, copied as they are. A row
whose Packet Reception Rate is not a percentage (incomplete, connect failed) or whose Streaming
Duration is not 60 s (a quick check) is skipped with a warning.
"""
import argparse
import csv
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

WIKI_URL = "https://github.com/ShimmerResearch/SwiftAPI.wiki.git"
PAGE = "BLE-Throughput.md"
HW_ORDER = ["Shimmer3", "Shimmer3R"]
COLUMNS = ["Equipment", "Shimmer Device", "FW Version", "Radio Type", "Sensors Enabled", "CRC Bytes",
           "Number of Bytes", "Sampling Rate", "Streaming Duration", "Packet Reception Rate",
           "OS Version", "Distance between devices (approximate)"]
# The wiki table is the app's CSV columns plus the API release, which the app cannot know: it comes
# from --release.
WIKI_COLUMNS = COLUMNS[:1] + ["API Release"] + COLUMNS[1:]
DEVICE = WIKI_COLUMNS.index("Shimmer Device")


def marker(release: str) -> str:
    return f"<!-- throughput:{release} -->"


def build_rows(rows, release):
    """Group publishable rows by hardware. Return ({hw: [row cells]}, [problems])."""
    tables, problems = defaultdict(list), []
    for r in rows:
        cells = [release if c == "API Release" else r[c] for c in WIKI_COLUMNS]
        hw, prr, secs = r["Shimmer Device"], r["Packet Reception Rate"], r["Streaming Duration"]
        what = f"{hw} {r['Sensors Enabled']} {r['CRC Bytes']}"
        if hw not in HW_ORDER:
            problems.append(f"skipped {what}: unknown device {hw!r} ({prr})")
        elif not re.fullmatch(r"\d+%", prr):
            problems.append(f"skipped {what}: {prr}")
        elif secs != "60 s":
            problems.append(f"skipped {what}: {secs} is a quick check, not a wiki result")
        elif "," in r["Equipment"]:   # a raw model identifier such as iPhone18,3
            problems.append(f"skipped {what}: phone {r['Equipment']!r} is a raw model identifier; "
                            "add it to the app's phone table")
        else:
            tables[hw].append(cells)
    return tables, problems


def render(release, number, cells):
    hws = ", ".join(h for h in HW_ORDER if any(c[DEVICE] == h for c in cells))
    head = f"# Test Results {number} For Different Sensor Configurations ({hws})"
    lines = [marker(release), head,
             "| " + " | ".join(WIKI_COLUMNS) + " |",
             "| " + " | ".join("---" for _ in WIKI_COLUMNS) + " |"]
    lines += ["| " + " | ".join(c) + " |" for c in cells]
    return "\n".join(lines) + "\n"


def apply(text, release, tables):
    """Add this run's rows to the release's table, or start that table as the next number."""
    new = [c for hw in HW_ORDER for c in tables.get(hw, [])]
    existing = re.search(re.escape(marker(release)) + r"\n# Test Results (\d+).*?(?=\n\n|\n# |\Z)", text, re.S)
    if not existing:
        numbers = [int(n) for n in re.findall(r"^# Test Results (\d+)", text, re.M)]
        block = render(release, max(numbers, default=0) + 1, new) + "\n"
        notes = re.search(r"^# Notes", text, re.M)
        if notes:
            return text[:notes.start()] + block + text[notes.start():]
        return text.rstrip("\n") + "\n\n" + block
    rows = [[c.strip() for c in line.strip().strip("|").split("|")] for line in existing.group(0).splitlines()[4:]]
    rows += [c for c in new if c not in rows]
    order = {hw: i for i, hw in enumerate(HW_ORDER)}
    rows.sort(key=lambda c: order.get(c[DEVICE], len(HW_ORDER)))   # stable: runs stay in the order published
    block = render(release, int(existing.group(1)), rows).rstrip("\n")
    return text[:existing.start()] + block + text[existing.end():]


def git(wiki, *args, check=True):
    return subprocess.run(["git", "-C", str(wiki), *args], capture_output=True, text=True, check=check)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--csv", required=True, type=Path)
    ap.add_argument("--release", required=True, help="e.g. ShimmerSwiftAPI_v1.1.0")
    ap.add_argument("--wiki", type=Path, help="existing wiki clone (default: clone to a temp dir)")
    ap.add_argument("--commit", action="store_true", help="commit in the wiki clone. Never pushes.")
    a = ap.parse_args()

    with a.csv.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != COLUMNS:
            sys.exit(f"{a.csv} is not the app's wiki-column CSV (columns: {reader.fieldnames})")
        rows = list(reader)
    if not rows:
        sys.exit("CSV has no rows")

    tables, problems = build_rows(rows, a.release)
    for p in problems:
        print("WARNING:", p, file=sys.stderr)
    if not tables:
        sys.exit("nothing to write: no row is a complete 60 s result")

    wiki = a.wiki
    if wiki is None:
        wiki = Path(tempfile.mkdtemp(prefix="swiftapi-wiki-")) / "wiki"
        subprocess.run(["git", "clone", "--quiet", WIKI_URL, str(wiki)], check=True)
    page = wiki / PAGE
    if git(wiki, "status", "--porcelain").stdout.strip():
        sys.exit(f"{wiki} has uncommitted changes; clean it first")

    old = page.read_text(encoding="utf-8")
    new = apply(old, a.release, tables)
    if new == old:
        print("No change: these rows are already in this release's table.")
        return
    with page.open("w", encoding="utf-8", newline="\n") as f:  # write_text(newline=) needs 3.10
        f.write(new)
    print(git(wiki, "diff", "--", PAGE).stdout)

    if not a.commit:
        git(wiki, "checkout", "--", PAGE)
        print("Dry run: nothing changed. Add --commit to commit locally.")
        return
    git(wiki, "add", PAGE)
    hws = ", ".join(h for h in HW_ORDER if h in tables)
    git(wiki, "commit", "-m", f"BLE throughput results for {a.release} ({hws})")
    print(f"Committed in {wiki}. Not pushed. Review, then: git -C \"{wiki}\" push")


if __name__ == "__main__":
    main()
