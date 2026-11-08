"""Pre-registered analysis for the final test session (S3), written before S3 ran.

Implements the rules fixed in docs/test-protocol.md:
  * 1.25 vs 1.35: replay every owner and imitator attempt at the candidate factor 1.35. Adopt 1.35 only if no imitator
    attempt (S1, plus S3's screen-hidden A4) is accepted at 1.35; otherwise keep 1.25.
  * Cross-time enrollment: arm A = the 3 S1 enrollment records (worst pair); arm B = A + the first accepted S2 and the
    first accepted S4-extra owner attempt (mean pair). Each arm's factor = 0.95 x the largest factor that rejects every
    S1 imitator. Report S3 owner acceptance (Wilson 95%) and S3 A4 acceptance for both arms.

A factor f accepts an attempt when score <= threshold * f / 1.25, because the app's threshold is 1.25 x the spread.

Usage (standard library only):
  python3 -I tools/session_analysis.py MAC1_LOGS [--enrollment 6f1a57e8182d] [--new-enrollment 98e6546cb7e2]
                                       [--also MAC2_LOGS:c468b7f068e6]
The 1.35 decision pools the imitators of every Mac given.
"""
import argparse
import glob
import json
import math
import os
import statistics
from itertools import combinations

BASE = 1.25
CANDIDATE = 1.35
IMITATION = ("A2-zero-effort", "A3-watched-once", "A4-skilled")
# An owner attempt shorter than half the enrolled signatures' median length is a false start (Mac 1 S4: 0.8 s, 1.9 s).
FALSE_START_FRACTION = 0.5


def load(directory):
    records = []
    for path in sorted(glob.glob(os.path.join(directory, "*.json"))):
        r = json.load(open(path))
        r["file"] = os.path.basename(path)
        records.append(r)
    return records


def scored(r):
    return r.get("mode") == "verify" and r.get("rejection") in (None, "scoreTooHigh")


def false_start_cutoff(records, enrollment):
    durations = [r["dur"] for r in records if r.get("mode") == "enroll" and r.get("enrollment") == enrollment]
    return FALSE_START_FRACTION * statistics.median(durations) if durations else 0.0


def ratio(r):
    return r["score"] / r["threshold"]


def similarity(r):
    value = math.floor(min(max(100 - 25 * ratio(r), 0), 100))
    return max(value, 75) if r["accepted"] else min(value, 74)


def wilson(k, n, z=1.96):
    if n == 0:
        return (float("nan"), float("nan"))
    p, d = k / n, 1 + z * z / n
    c, h = p + z * z / (2 * n), z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - h) / d, (c + h) / d)


def fmt(k, n):
    lo, hi = wilson(k, n)
    return f"{k}/{n} ({100 * k / n:.0f}%, 95% {100 * lo:.0f}-{100 * hi:.0f}%)" if n else "0/0"


# ---- the app's matcher, ported (tools/tuning/quick_candidates.py; checked equal to the app's scores) ----

def features(rows):
    return [[r[5] / 3.0, r[6] / 3.0, r[7] / 3.0, r[8] / 0.5, r[9] / 0.5, r[10] / 0.5, r[11], r[12], r[13]] for r in rows]


def dtw(a, b, band=0.25):
    n, m = len(a), len(b)
    w = math.ceil(band * max(n, m))
    inf = float("inf")
    prev = [inf] * (m + 1)
    prev[0] = 0.0
    for i in range(1, n + 1):
        cur = [inf] * (m + 1)
        c = int(math.floor(i * m / n + 0.5))
        ai = a[i - 1]
        for j in range(max(1, c - w), min(m, c + w) + 1):
            bj = b[j - 1]
            s = 0.0
            for k in range(9):
                d = ai[k] - bj[k]
                s += d * d
            cur[j] = math.sqrt(s) + min(prev[j], cur[j - 1], prev[j - 1])
        prev = cur
    return prev[m] / (n + m)


def distance(x, y):
    fx = x.setdefault("_f", features(x["rows"]))
    fy = y.setdefault("_f", features(y["rows"]))
    return dtw(fx, fy) * (1 + 0.5 * abs(math.log(max(x["dur"], 1e-3) / max(y["dur"], 1e-3))))


# ---- sections ----

def factor_section(records, enrollment, label):
    """Prints owner and imitator results at 1.25 and 1.35; returns (imitators checked, accepted at 1.35)."""
    print(f"\n== Threshold factor: {label}, enrollment {enrollment} ==")
    cutoff = false_start_cutoff(records, enrollment)
    owner = [r for r in records if scored(r) and r["enrollment"] == enrollment and r["scenario"] == "A1-owner"]
    imit = [r for r in records if scored(r) and r["enrollment"] == enrollment and r["scenario"] in IMITATION]
    cut = CANDIDATE / BASE
    for session in ("S1-tonight", "S2-midnight", "S4-extra", "S3-morning"):
        rs = [r for r in owner if r["session"] == session and r["dur"] >= cutoff]
        if not rs:
            continue
        ok_base = sum(r["accepted"] for r in rs)
        ok_cand = sum(ratio(r) <= cut for r in rs)
        sims = [similarity(r) for r in rs]
        print(f"  owner {session:12s} at 1.25: {fmt(ok_base, len(rs))}   at 1.35: {fmt(ok_cand, len(rs))}"
              f"   similarity median {statistics.median(sims)}, min {min(sims)}")
    checked = [r for r in imit if r["session"] == "S1-tonight" or (r["session"] == "S3-morning" and r["scenario"] == "A4-skilled")]
    passed = [r for r in checked if ratio(r) <= cut]
    print(f"  imitators checked (S1 + S3 A4): {len(checked)}; accepted at 1.25: {sum(r['accepted'] for r in checked)};"
          f" accepted at 1.35: {len(passed)}")
    if checked:
        print(f"  closest imitator: {min(ratio(r) for r in checked):.3f} x threshold (1.35 accepts up to {cut:.3f})")
    return len(checked), len(passed)


def cross_time_section(records, enrollment):
    print(f"\n== Cross-time enrollment (enrollment {enrollment}) ==")
    enroll = [r for r in records if r.get("mode") == "enroll" and r.get("enrollment") == enrollment]
    cutoff = false_start_cutoff(records, enrollment)
    owner = lambda s: [r for r in records if scored(r) and r["enrollment"] == enrollment and r["session"] == s
                       and r["scenario"] == "A1-owner" and r["dur"] >= cutoff]
    firsts = [next((r for r in owner(s) if r["accepted"]), None) for s in ("S2-midnight", "S4-extra")]
    if len(enroll) != 3 or None in firsts:
        print("  skipped: needs 3 enrollment records and an accepted S2 and S4-extra owner attempt")
        return
    templates = enroll + firsts
    s1_imit = [r for r in records if scored(r) and r["enrollment"] == enrollment and r["session"] == "S1-tonight"
               and r["scenario"] in IMITATION]
    s3_owner = owner("S3-morning")
    s3_a4 = [r for r in records if scored(r) and r["enrollment"] == enrollment and r["session"] == "S3-morning"
             and r["scenario"] == "A4-skilled"]
    if not s3_owner:
        print("  no S3 owner attempts yet")
        return
    arms = {
        "A (3 from S1, worst pair)": (3, max(distance(a, b) for a, b in combinations(enroll, 2))),
        "B (+ S2 and S4, mean pair)": (5, statistics.mean(distance(a, b) for a, b in combinations(templates, 2))),
    }
    for name, (k, spread) in arms.items():
        best = lambda r: min(distance(r, t) for t in templates[:k]) / spread
        factor = 0.95 * min(best(r) for r in s1_imit)
        ok = sum(best(r) <= factor for r in s3_owner)
        a4 = sum(best(r) <= factor for r in s3_a4)
        print(f"  {name}: factor {factor:.3f}; S3 owner {fmt(ok, len(s3_owner))}; S3 A4 accepted {a4}/{len(s3_a4)}")


def new_signature_section(records, enrollment):
    print(f"\n== New signature (enrollment {enrollment}) ==")
    for session in ("S4-extra", "S3-morning"):
        for scen in ("A1-owner",) + IMITATION:
            rs = [r for r in records if scored(r) and r["enrollment"] == enrollment and r["session"] == session
                  and r["scenario"] == scen]
            if rs:
                print(f"  {session:12s} {scen:16s} {fmt(sum(r['accepted'] for r in rs), len(rs))}"
                      f"   similarity median {statistics.median(similarity(r) for r in rs)}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("logs")
    p.add_argument("--enrollment", default="6f1a57e8182d")
    p.add_argument("--new-enrollment", default="98e6546cb7e2")
    p.add_argument("--also", action="append", default=[], metavar="LOGS:ENROLLMENT", help="another Mac's logs")
    p.add_argument("--skip-dtw", action="store_true", help="skip the slow cross-time replay")
    a = p.parse_args()
    records = [r for r in load(a.logs) if r.get("mode") != "excluded"]
    checked, passed = factor_section(records, a.enrollment, "Mac 1")
    for i, extra in enumerate(a.also, start=2):
        logs, enrollment = extra.rsplit(":", 1)
        c, k = factor_section([r for r in load(logs) if r.get("mode") != "excluded"], enrollment, f"Mac {i}")
        checked, passed = checked + c, passed + k
    print(f"\n== DECISION (pre-registered): {passed} of {checked} imitator attempts accepted at 1.35 -> "
          + ("keep 1.25" if passed else "adopt 1.35") + " ==")
    if not a.skip_dtw:
        cross_time_section(records, a.enrollment)
    new_signature_section(records, a.new_enrollment)


if __name__ == "__main__":
    main()
