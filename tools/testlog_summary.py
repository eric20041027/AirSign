"""Progress summary of AirSign test-lab records, for whoever keeps the session log.

Reads only labels, counts, durations and sample counts from attempt-*.json, never prints motion data.

    python3 tools/testlog_summary.py                          # this Mac's logs, all sessions
    python3 tools/testlog_summary.py --session S1-tonight     # one session
    python3 tools/testlog_summary.py /path/to/test-logs       # another folder (e.g. unzipped from a teammate)
"""
import argparse
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path

DEFAULT_DIR = Path.home() / "Library/Application Support/AirSign/test-logs"

# Targets per tester from docs/test-protocol.md (protocol v2).
TARGETS = {
    ("S1-tonight", "A1-owner"): 20,
    ("S2-midnight", "A1-owner"): 20,
    ("S3-morning", "A1-owner"): 20,
    ("S1-tonight", "A2-zero-effort"): 10,
    ("S1-tonight", "A3-watched-once"): 10,
    ("S1-tonight", "A4-skilled"): 15,
    ("S3-morning", "A4-skilled"): 10,
    ("S1-tonight", "A5-other-bud"): 10,
    ("S1-tonight", "A5-other-pair"): 10,
}


def load(directory: Path) -> list[dict]:
    records = []
    for path in sorted(directory.glob("attempt-*.json")):
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as error:
            print(f"skipped {path.name}: {error}")
            continue
        records.append({
            "file": path.name,
            "mode": data.get("mode", ""),
            "session": data.get("session", ""),
            "owner": data.get("owner", ""),
            "tester": data.get("tester", ""),
            "scenario": data.get("scenario", ""),
            "enrollment": data.get("enrollment", ""),
            "loc": data.get("loc", ""),
            "accepted": data.get("accepted"),
            "rejection": data.get("rejection"),
            "dur": float(data.get("dur") or 0),
            "n": len(data.get("rows") or []),
        })
    return records


def sample_rate(records: list[dict]) -> str:
    rates = [(r["n"] - 1) / r["dur"] for r in records if r["dur"] > 0.5 and r["n"] > 10]
    return f"{statistics.median(rates):.1f} Hz (median of {len(rates)} records)" if rates else "unknown"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", nargs="?", type=Path, default=DEFAULT_DIR)
    parser.add_argument("--session")
    args = parser.parse_args()

    records = load(args.directory)
    if args.session:
        records = [r for r in records if r["session"] == args.session]
    print(f"# Test-lab progress: {args.directory}")
    print(f"\nRecords: {len(records)}. Measured sample rate: {sample_rate(records)}")

    enrollments = Counter((r["owner"], r["enrollment"], r["loc"]) for r in records if r["mode"] == "enroll")
    print("\n## Enrollments (each should have 3 records)")
    for (owner, fingerprint, loc), count in sorted(enrollments.items()):
        warning = "" if count == 3 else "  <- expected 3"
        print(f"- owner {owner}, enrollment {fingerprint}, {loc} bud: {count} records{warning}")

    rows = defaultdict(lambda: [0, 0])
    for r in records:
        if r["mode"] != "verify":
            continue
        key = (r["session"], r["owner"], r["tester"], r["scenario"])
        rows[key][0] += 1
        rows[key][1] += 1 if r["accepted"] else 0
    print("\n## Verify attempts")
    print("| Session | Owner | Tester | Scenario | Logged | Accepted | Target | Left |")
    print("|---|---|---|---|---|---|---|---|")
    for (session, owner, tester, scenario), (logged, accepted) in sorted(rows.items()):
        target = TARGETS.get((session, scenario))
        left = "" if target is None else max(target - logged, 0)
        print(f"| {session} | {owner} | {tester} | {scenario} | {logged} | {accepted} | {target or '-'} | {left} |")

    unknown = sum(1 for r in records if r["rejection"] == "deviceUnknown")
    blank = sum(1 for r in records if r["mode"] == "verify" and not r["tester"])
    print("\n## Checks")
    print(f"- Attempts with no tester name: {blank}")
    print(f"- Attempts where the AirPods weren't the sound output (excluded from analysis): {unknown}")
    print("- Discarded attempts (finger slipped, too short) are not logged by the app: tally them by hand.")
    print("- A4 in S1 stops at 15 even though the app shows /25; the other 10 are in S3 with the screen hidden.")


if __name__ == "__main__":
    main()
