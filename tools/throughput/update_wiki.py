#!/usr/bin/env python3
"""Turn a ThroughputRunner CSV into new tables on the BLE-Throughput wiki page.

One table per test run, numbered after the last "# Test Results N" on the page and inserted above
"# Notes", with every hardware's rows in it (Shimmer3 first) and the API release in its heading.
Old tables are never touched, so a release tested again gets a new table and the earlier one stays.
Publishing a run whose table is already on the page for that release changes nothing.

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


def marker(release: str) -> str:
    return f"<!-- throughput:{release} -->"


def build_rows(rows):
    """Group publishable rows by hardware. Return ({hw: [row cells]}, [problems])."""
    tables, problems = defaultdict(list), []
    for r in rows:
        cells = [r[c] for c in COLUMNS]
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
    hws = ", ".join(h for h in HW_ORDER if any(c[1] == h for c in cells))
    head = f"# Test Results {number} For Different Sensor Configurations ({hws}, {release})"
    lines = [marker(release), head,
             "| " + " | ".join(COLUMNS) + " |",
             "| " + " | ".join("---" for _ in COLUMNS) + " |"]
    lines += ["| " + " | ".join(c) + " |" for c in cells]
    return "\n".join(lines) + "\n"


def apply(text, release, tables):
    """Add this run as the next table above '# Notes', unless the same table is already there."""
    cells = [c for hw in HW_ORDER for c in tables.get(hw, [])]
    for block in re.finditer(re.escape(marker(release)) + r"\n# Test Results \d+.*?(?=\n\n|\n# |\Z)", text, re.S):
        rows = [[c.strip() for c in line.strip().strip("|").split("|")] for line in block.group(0).splitlines()[4:]]
        if rows == cells:
            return text   # this run is already published
    numbers = [int(n) for n in re.findall(r"^# Test Results (\d+)", text, re.M)]
    block = render(release, max(numbers, default=0) + 1, cells) + "\n"
    notes = re.search(r"^# Notes", text, re.M)
    if notes:
        return text[:notes.start()] + block + text[notes.start():]
    return text.rstrip("\n") + "\n\n" + block


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

    tables, problems = build_rows(rows)
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
        print("No change: this run is already on the page for this release.")
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
