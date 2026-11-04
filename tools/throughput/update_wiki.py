#!/usr/bin/env python3
"""Turn a ThroughputRunner CSV into new tables on the BLE-Throughput wiki page.

One table per hardware (Shimmer3, Shimmer3R) per release, inserted above "# Notes". Old tables are
never touched. Re-running for the same release and hardware replaces that table, so there are no
duplicates.

Dry run by default: prints the diff and changes nothing. --commit commits in the local wiki clone.
It never pushes. Push the wiki yourself after reading the diff.

    python update_wiki.py --csv results.csv --release ShimmerSwiftAPI_v1.1.0 --phone "iPhone 12" \
        --radio Shimmer3="RN4678 v1.23" --radio Shimmer3R="IF820 v01.04.16.16" --wiki ./SwiftAPI.wiki
"""
import argparse
import csv
import re
import statistics
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


def marker(release: str, hw: str) -> str:
    return f"<!-- throughput:{release}:{hw} -->"


def fw_cell(hw: str, fw: str) -> str:
    """CSV holds major.minor.internal, e.g. 1.1.9. The wiki writes v1.01.009."""
    major, minor, internal = (int(x) for x in fw.split("."))
    return f"L&S {hw} v{major}.{minor:02d}.{internal:03d}"


def num(x: float) -> str:
    return f"{x:g}"


def build_rows(rows, release, phone, radios, distance, min_runs):
    """Group ok runs by hardware. Return ({hw: [row cells]}, [problems])."""
    problems = []
    skipped = [r for r in rows if r["status"] != "ok"]
    for r in skipped:
        problems.append(f"skipped {r['hw'] or '?'} {r['config']} crc={r['crc']} run={r['run']}: {r['status']}")

    groups = defaultdict(list)
    for r in rows:
        if r["status"] == "ok":
            groups[(r["hw"], r["config"], int(r["crc"]), float(r["rate_hz"]), int(r["seconds"]))].append(r)

    tables = defaultdict(list)
    for (hw, config, crc, rate, secs), g in sorted(groups.items(), key=lambda kv: (HW_ORDER.index(kv[0][0]), kv[0][2])):
        if len(g) < min_runs:
            problems.append(f"{hw} {config} crc={crc}: {len(g)} ok run(s), need {min_runs}")
            continue
        if len({x["fw"] for x in g}) != 1 or len({x["packet_bytes"] for x in g}) != 1:
            problems.append(f"{hw} {config} crc={crc}: runs disagree on firmware or packet size")
            continue
        if hw not in radios:
            problems.append(f"no --radio given for {hw}")
            continue
        prr = statistics.median(float(x["prr_api"]) for x in g)
        first = g[0]
        tables[hw].append([
            phone, hw, fw_cell(hw, first["fw"]), radios[hw], config,
            f"{crc} byte" + ("" if crc == 1 else "s"), f"{first['packet_bytes']} bytes",
            f"{num(rate)} Hz", f"{secs} s", f"{round(prr)}%", first["ios"], distance,
        ])
    return tables, problems


def render(hw, release, number, cells):
    head = f"# Test Results {number} For Different Sensor Configurations ({hw}, {release})"
    lines = [marker(release, hw), head,
             "| " + " | ".join(COLUMNS) + " |",
             "| " + " | ".join("---" for _ in COLUMNS) + " |"]
    lines += ["| " + " | ".join(c) + " |" for c in cells]
    return "\n".join(lines) + "\n"


def apply(text, release, tables):
    """Replace this release's tables, or insert new ones above '# Notes'."""
    numbers = [int(n) for n in re.findall(r"^# Test Results (\d+)", text, re.M)]
    next_n = max(numbers, default=0) + 1
    for hw in HW_ORDER:
        if hw not in tables:
            continue
        m = marker(release, hw)
        existing = re.search(re.escape(m) + r"\n# Test Results (\d+).*?(?=\n\n|\n# |\Z)", text, re.S)
        if existing:
            n = int(existing.group(1))
            text = text[:existing.start()] + render(hw, release, n, tables[hw]).rstrip("\n") + text[existing.end():]
        else:
            block = render(hw, release, next_n, tables[hw]) + "\n"
            next_n += 1
            notes = re.search(r"^# Notes", text, re.M)
            if notes:
                text = text[:notes.start()] + block + text[notes.start():]
            else:
                text = text.rstrip("\n") + "\n\n" + block
    return text


def git(wiki, *args, check=True):
    return subprocess.run(["git", "-C", str(wiki), *args], capture_output=True, text=True, check=check)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--csv", required=True, type=Path)
    ap.add_argument("--release", required=True, help="e.g. ShimmerSwiftAPI_v1.1.0")
    ap.add_argument("--phone", required=True, help='Equipment cell, e.g. "iPhone 12"')
    ap.add_argument("--radio", action="append", default=[], metavar="HW=VERSION",
                    help='e.g. Shimmer3="RN4678 v1.23" (repeat per hardware)')
    ap.add_argument("--distance", default="2.5 m")
    ap.add_argument("--min-runs", type=int, default=3, help="ok runs needed per config (default 3)")
    ap.add_argument("--wiki", type=Path, help="existing wiki clone (default: clone to a temp dir)")
    ap.add_argument("--commit", action="store_true", help="commit in the wiki clone. Never pushes.")
    a = ap.parse_args()

    radios = dict(r.split("=", 1) for r in a.radio)
    with a.csv.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        sys.exit("CSV has no rows")

    tables, problems = build_rows(rows, a.release, a.phone, radios, a.distance, a.min_runs)
    for p in problems:
        print("WARNING:", p, file=sys.stderr)
    if not tables:
        sys.exit("nothing to write: no hardware had a complete set of ok runs")

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
        print("No change: this release is already on the page with these values.")
        return
    page.write_text(new, encoding="utf-8", newline="\n")
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
