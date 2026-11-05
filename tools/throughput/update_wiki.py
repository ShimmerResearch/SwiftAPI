#!/usr/bin/env python3
"""Turn a ThroughputRunner CSV into new tables on the BLE-Throughput wiki page.

One table per API release, numbered after the last "# Test Results N" on the page and inserted above
"# Notes". Each row notes the API release in an "API Release" column after Equipment. A later run for the same release adds its rows to that
release's table (grouped by hardware, Shimmer3 first). A re-run of the same setting on the same
phone and firmware replaces that row in place; anything else is added. Other tables are never
touched.

Dry run by default: prints the change and touches nothing. To publish in one step:

    python3 update_wiki.py ~/Downloads/throughput_20261105_120207.csv --push

--push clones the live wiki fresh, shows the change, asks before pushing, then commits and pushes.
--release defaults to the latest ShimmerSwiftAPI_v* tag on GitHub. --commit commits in a clone
(--wiki) without pushing.

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
WIKI_PAGE_URL = "https://github.com/ShimmerResearch/SwiftAPI/wiki/BLE-Throughput"
REPO_URL = "https://github.com/ShimmerResearch/SwiftAPI.git"
PAGE = "BLE-Throughput.md"
HW_ORDER = ["Shimmer3", "Shimmer3R"]
COLUMNS = ["Equipment", "Shimmer Device", "FW Version", "Radio Type", "Sensors Enabled", "CRC Bytes",
           "Number of Bytes", "Sampling Rate", "Streaming Duration", "Packet Reception Rate",
           "OS Version", "Distance between devices (approximate)"]
# The wiki table is the app's CSV columns plus the API release, which the app cannot know: it comes
# from --release.
WIKI_COLUMNS = COLUMNS[:1] + ["API Release"] + COLUMNS[1:]
DEVICE = WIKI_COLUMNS.index("Shimmer Device")
# Cells that identify a setting within a release's table: a newer result for these replaces the row.
SETTING = [WIKI_COLUMNS.index(c) for c in ["Equipment", "Shimmer Device", "FW Version", "Sensors Enabled",
                                           "CRC Bytes", "Sampling Rate", "Streaming Duration"]]


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
    # A re-run of the same setting on the same phone and firmware replaces that row in place, so a
    # setting never shows two results. Anything else (another phone, firmware or setting) is added.
    for c in new:
        same = next((i for i, r in enumerate(rows) if [r[k] for k in SETTING] == [c[k] for k in SETTING]), None)
        if same is None:
            rows.append(c)
        else:
            rows[same] = c
    order = {hw: i for i, hw in enumerate(HW_ORDER)}
    rows.sort(key=lambda c: order.get(c[DEVICE], len(HW_ORDER)))   # stable: runs stay in the order published
    block = render(release, int(existing.group(1)), rows).rstrip("\n")
    return text[:existing.start()] + block + text[existing.end():]


def git(wiki, *args, check=True):
    return subprocess.run(["git", "-C", str(wiki), *args], capture_output=True, text=True, check=check)


def latest_release():
    """The highest ShimmerSwiftAPI_vX.Y.Z tag on GitHub, or None."""
    out = subprocess.run(["git", "ls-remote", "--tags", REPO_URL, "ShimmerSwiftAPI_v*"],
                         capture_output=True, text=True, check=True).stdout
    tags = set(re.findall(r"refs/tags/(ShimmerSwiftAPI_v(\d+)\.(\d+)\.(\d+))$", out, re.M))
    return max(tags, key=lambda t: tuple(int(x) for x in t[1:]))[0] if tags else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv", nargs="?", type=Path, help="the app's CSV")
    ap.add_argument("--csv", dest="csv_opt", type=Path, help=argparse.SUPPRESS)   # older spelling
    ap.add_argument("--release", help="e.g. ShimmerSwiftAPI_v1.1.0 (default: the latest release tag on GitHub)")
    ap.add_argument("--wiki", type=Path, help="existing wiki clone (default: a fresh clone in a temp dir)")
    ap.add_argument("--commit", action="store_true", help="commit in the wiki clone, without pushing")
    ap.add_argument("--push", action="store_true",
                    help="publish: fresh clone of the live wiki, show the change, ask, commit and push")
    ap.add_argument("--yes", action="store_true",
                    help="with --push: publish without asking (for a shell with no keyboard input)")
    a = ap.parse_args()
    a.csv = a.csv or a.csv_opt
    if not a.csv:
        ap.error("give the CSV path")
    if a.push and a.wiki:
        ap.error("--push always works on a fresh clone of the live wiki; leave out --wiki")

    with a.csv.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != COLUMNS:
            sys.exit(f"{a.csv} is not the app's wiki-column CSV (columns: {reader.fieldnames})")
        rows = list(reader)
    if not rows:
        sys.exit("CSV has no rows")

    if not a.release:
        a.release = latest_release()
        if not a.release:
            sys.exit("no ShimmerSwiftAPI_v* release tag found on GitHub; pass --release")
        print(f"API release: {a.release} (latest release tag on GitHub; --release to change)")

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

    if not (a.commit or a.push):
        git(wiki, "checkout", "--", PAGE)
        print("Dry run: nothing changed. Add --push to publish, or --commit to commit locally.")
        return
    if a.push and not a.yes:
        try:
            answer = input("Publish this to the GitHub wiki? [y/N] ")
        except EOFError:   # no keyboard: e.g. run through a tool rather than a terminal
            answer = ""
            print("\nNo answer could be read (no terminal). Run it in Terminal, or add --yes after "
                  "checking the change above.")
        if answer.strip().lower() != "y":
            git(wiki, "checkout", "--", PAGE)
            print("Cancelled: nothing published.")
            return
    git(wiki, "add", PAGE)
    hws = ", ".join(h for h in HW_ORDER if h in tables)
    git(wiki, "commit", "-m", f"BLE throughput results for {a.release} ({hws})")
    if not a.push:
        print(f"Committed in {wiki}. Not pushed. Review, then: git -C \"{wiki}\" push")
        return
    pushed = git(wiki, "push", "--quiet", check=False)
    if pushed.returncode != 0:
        sys.exit(f"Push failed, nothing published:\n{pushed.stderr}The commit is in {wiki}.")
    print(f"Published: {WIKI_PAGE_URL}")


if __name__ == "__main__":
    main()
