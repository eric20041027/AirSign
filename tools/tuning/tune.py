"""Grid-search the AirSign matcher settings on recorded attempts.

Usage:
  python tune.py DATA_DIR [--report ../../archive/makeuc-2026/tuning.md] [--quick]
  python tune.py DATA_DIR \
      --round "Round 1" 20261107-143432-081,20261107-143437-789,20261107-143444-477 20261107-143445 20261107-144241 \
      --round "Round 2" 20261107-144527-280,20261107-144533-012,20261107-144616-034 20261107-144617 20261107-145000
  python tune.py --test-logs /path/to/airsign-data/mac1 /path/to/airsign-data/mac2 --report ../../archive/makeuc-2026/evaluation.md

--test-logs reads the app's test-mode records (archive/makeuc-2026/test-protocol.md) instead
and writes the evaluation report plus two SVG charts next to it; see evaluate.py.

DATA_DIR holds the spike's attempt-*.json files. Keep it OUTSIDE the repo:
signature recordings are biometric-like personal data and must never be committed.

Each --round names its templates and the first and last verify ids to use
(ids compare as prefixes, both ends included). Without --round, each run of
enroll attempts followed by verify attempts is one round, and its last 3
enrolls are the templates. Verify attempts on the other bud (gate 1 rejects
them in the app) or not longer than --min-dur seconds are left out.

One setting is picked for all rounds together: every round must reach
--owner-min, then the fewest imitators accepted wins.

The report holds only counts and settings, never recordings.
"""
from __future__ import annotations

import argparse
import itertools
import math
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import matcher as M

REPO = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Grid:
    bands: list[float]
    duration_weights: list[float]
    factors: list[float]
    weights: list[tuple[float, float, float]]


@dataclass
class Count:
    owner_ok: int
    owner_n: int
    imitator_ok: int
    imitator_n: int
    auc: float


@dataclass
class Row:
    params: M.Params
    rounds: list[Count]  # one per session, same order
    total: Count  # all rounds pooled; AUC on score / worst template pair

    @property
    def owner_ok(self) -> int:
        return self.total.owner_ok

    @property
    def owner_n(self) -> int:
        return self.total.owner_n

    @property
    def imitator_ok(self) -> int:
        return self.total.imitator_ok

    @property
    def imitator_n(self) -> int:
        return self.total.imitator_n


def frange(lo: float, hi: float, step: float) -> list[float]:
    return [round(lo + i * step, 4) for i in range(int(round((hi - lo) / step)) + 1)]


def weight_grid(values: list[float]) -> list[tuple[float, float, float]]:
    """All gyro/acc/grav weight triples, scaled so the largest is 1, without duplicates.

    Scaling every weight by the same amount scales every distance the same way,
    which the threshold factor cancels, so only the ratios matter.
    """
    out, seen = [], set()
    for combo in itertools.product(values, repeat=3):
        top = max(combo)
        if top == 0:
            continue
        key = tuple(round(c / top, 6) for c in combo)
        if key not in seen:
            seen.add(key)
            out.append(key)
    return out


FULL = Grid(bands=frange(0.1, 0.4, 0.05), duration_weights=frange(0, 1, 0.25),
            factors=frange(1.0, 2.0, 0.05), weights=weight_grid([0.0, 0.5, 1.0, 2.0]))
QUICK = Grid(bands=[0.15, 0.25, 0.35], duration_weights=[0, 0.5, 1.0],
             factors=frange(1.0, 2.0, 0.05), weights=weight_grid([0.0, 1.0]))


def _count(owner: list[float], imitator: list[float], factor: float, auc: float) -> Count:
    return Count(M.accepted(owner, factor), len(owner), M.accepted(imitator, factor), len(imitator), auc)


def run_grid(sessions: list[M.Session], grid: Grid, progress: bool = False) -> list[Row]:
    rows = []
    total = len(grid.bands) * len(grid.weights)
    done = 0
    for band in grid.bands:
        for w in grid.weights:
            tables = [M.plain_dtw(s, band, w) for s in sessions]
            for dw in grid.duration_weights:
                scores = [M.score_ratios(s, table, dw) for s, table in zip(sessions, tables)]
                aucs = [M.auc(sc.owner, sc.imitator) for sc in scores]
                owner = [r for sc in scores for r in sc.owner]
                imitator = [r for sc in scores for r in sc.imitator]
                pooled_auc = M.auc(owner, imitator)
                for f in grid.factors:
                    per = [_count(sc.owner, sc.imitator, f, a) for sc, a in zip(scores, aucs)]
                    rows.append(Row(M.Params(band, dw, f, w), per, _count(owner, imitator, f, pooled_auc)))
            done += 1
        if progress:
            print(f"[tuning] band {band:g} done ({done}/{total} band/weight combos)", file=sys.stderr, flush=True)
    return rows


def _closeness(p: M.Params) -> float:
    """How far a setting is from the plan's defaults; breaks ties toward fewer changes."""
    d = M.DEFAULT
    return (abs(p.band - d.band) / 0.15 + abs(p.duration_weight - d.duration_weight) / 0.5
            + abs(p.threshold_factor - d.threshold_factor) / 0.75 + sum(abs(x - 1) for x in p.weights))


def _nz(x: float) -> float:
    return 0.0 if math.isnan(x) else x


def changed_constants(p: M.Params) -> int:
    """How many Swift constants differ from today's: band, durationWeight, thresholdFactor, two FeatureScales."""
    d = M.DEFAULT
    n = (p.band != d.band) + (p.duration_weight != d.duration_weight) + (p.threshold_factor != d.threshold_factor)
    wr, wa, wg = p.weights
    if wg == 0:
        return n + 3  # dropping grav is an interface change
    return n + (wr != wg) + (wa != wg)


def rank_key(r: Row):
    """Fewest imitators, then most owners, then the fewest code changes, then separation."""
    mean_auc = sum(_nz(c.auc) for c in r.rounds) / max(1, len(r.rounds))
    return (r.imitator_ok, -r.owner_ok, changed_constants(r.params), -mean_auc, _closeness(r.params))


def owners_ok(r: Row, owner_min: float) -> bool:
    return all(c.owner_ok >= math.ceil(owner_min * c.owner_n - 1e-9) for c in r.rounds)


def pick_best(rows: list[Row], owner_min: float = 0.9, where=lambda r: True) -> Row | None:
    ok = [r for r in rows if where(r) and owners_ok(r, owner_min)]
    return min(ok, key=rank_key) if ok else None


def evaluate(sessions: list[M.Session], p: M.Params) -> Row:
    grid = Grid([p.band], [p.duration_weight], [p.threshold_factor], [p.weights])
    return run_grid(sessions, grid)[0]


def swift_constants(p: M.Params) -> str:
    """Turn group weights into the Swift FeatureScale values (grav has no scale, so normalize to it)."""
    wr, wa, wg = p.weights
    if wg == 0:
        return "grav weight 0: Swift would need to drop the grav columns (interface change)"
    parts = []
    for name, w, base in (("FeatureScale.rotation", wr, M.ROT_SCALE), ("FeatureScale.acceleration", wa, M.ACC_SCALE)):
        parts.append(f"`{name} = {base * wg / w:g}`" if w else f"drop the {name} columns (interface change)")
    return ", ".join(parts) + ", grav unscaled"


def fmt_w(w) -> str:
    return "/".join(f"{x:g}" for x in w)


def fmt_count(c: Count) -> str:
    return f"{c.owner_ok}/{c.owner_n} | {c.imitator_ok}/{c.imitator_n} | {c.auc:.3f}"


RESULT_HEAD = ("| Setting | Round | band | durationWeight | thresholdFactor | weights gyro/acc/grav "
               "| Owners accepted | Imitators accepted | AUC |\n|---|---|---|---|---|---|---|---|---|")


def result_rows(label: str, r: Row, names: list[str]) -> list[str]:
    p = r.params
    cols = f"{p.band:g} | {p.duration_weight:g} | {p.threshold_factor:g} | {fmt_w(p.weights)}"
    out = [f"| {label} | {n} | {cols} | {fmt_count(c)} |" for n, c in zip(names, r.rounds)]
    if len(names) > 1:
        out.append(f"| {label} | all | {cols} | {fmt_count(r.total)} |")
    return out


def report(sessions: list[M.Session], rows: list[Row], owner_min: float, data_note: str) -> str:
    names = [s.name for s in sessions]
    base = evaluate(sessions, M.DEFAULT)
    best = pick_best(rows, owner_min)
    same_feats = pick_best(rows, owner_min, where=lambda r: r.params.weights == (1.0, 1.0, 1.0))
    lines = [
        "# AirSign matcher tuning",
        "",
        f"Generated by `tools/tuning/tune.py` on {datetime.now():%Y-%m-%d %H:%M}. {data_note}",
        "",
        "Same matcher as the Swift app: score = minimum DTW over the 3 templates × (1 + durationWeight·|ln duration ratio|);",
        "threshold = thresholdFactor × worst pairwise template distance.",
        f"Goal: every round accepts the owner ≥ {owner_min:.0%} of the time, with as few imitators accepted as possible.",
        "",
        "## Data",
        "",
        "| Round | Bud | Templates | Owner attempts | Imitator attempts | Dropped: other bud (gate 1) | Dropped: ≤ 1.2 s |",
        "|---|---|---|---|---|---|---|",
    ]
    for s in sessions:
        own = sum(a.who == "genuine" for a in s.attempts)
        lines.append(f"| {s.name} | {s.side} | {len(s.templates)} | {own} | {len(s.attempts) - own} "
                     f"| {s.skipped['other bud']} | {s.skipped['too short']} |")
    lines += ["", "## Result", "", RESULT_HEAD]
    lines += result_rows("Current defaults", base, names)
    if same_feats and same_feats.params != base.params:
        lines += result_rows("Best, same features", same_feats, names)
    if best and best.params not in (base.params, getattr(same_feats, "params", None)):
        lines += result_rows("**Best grid point**", best, names)
    lines.append("")
    if not best:
        lines += [f"No setting in the grid reached owner ≥ {owner_min:.0%} in every round.", ""]
    else:
        p = best.params
        n_changes = changed_constants(p)
        only_factor = n_changes == (p.threshold_factor != M.DEFAULT.threshold_factor)
        if n_changes == 0:
            how = "Same as today's defaults: no code change."
        elif only_factor and p.threshold_factor < M.DEFAULT.threshold_factor:
            how = "Only the factor changes and it is tighter, so a threshold override can reach it without a code change."
        elif only_factor:
            how = "The factor is above 1.25. Overrides can only tighten the threshold, so role A must change the default."
        else:
            how = f"{n_changes} constant(s) change, so role A must change the code; a threshold override cannot do this."
        lines += [
            "Best grid point as Swift constants:",
            "",
            f"- `MatcherConfig.thresholdFactor = {p.threshold_factor:g}`, `MatcherConfig.durationWeight = {p.duration_weight:g}`, "
            f"`MatcherConfig.band = {p.band:g}`",
            f"- {swift_constants(p)}",
            f"- {how}",
            "",
            "## Threshold sweep at the best band, durationWeight and weights",
            "",
            "| thresholdFactor | " + " | ".join(f"{n} owners | {n} imitators" for n in names) + " |",
            "|---|" + "---|---|" * len(names),
        ]
        sweep = [r for r in rows if r.params.band == p.band and r.params.duration_weight == p.duration_weight
                 and r.params.weights == p.weights]
        for r in sweep:
            cells = " | ".join(f"{c.owner_ok}/{c.owner_n} | {c.imitator_ok}/{c.imitator_n}" for c in r.rounds)
            lines.append(f"| {r.params.threshold_factor:g} | {cells} |")
        lines += ["", "## Top 10 grid points (all rounds pooled)", "",
                  "| # | band | durationWeight | thresholdFactor | weights gyro/acc/grav | Owners accepted | Imitators accepted | AUC |",
                  "|---|---|---|---|---|---|---|---|"]
        top = sorted((r for r in rows if owners_ok(r, owner_min)), key=rank_key)[:10]
        for i, r in enumerate(top):
            q = r.params
            lines.append(f"| {i + 1} | {q.band:g} | {q.duration_weight:g} | {q.threshold_factor:g} | {fmt_w(q.weights)} "
                         f"| {fmt_count(r.total)} |")
    lines += [
        "",
        "## Caveats",
        "",
        "- Few attempts per round, so one attempt moves a rate by 3–10 points, and the best grid point is fitted to this",
        "  data. Prefer a setting whose neighbours in the sweep are also good.",
        "- AUC does not depend on thresholdFactor: it shows how well band, durationWeight and weights separate owner",
        "  from imitators. Pooled AUC compares score ÷ worst template pair across rounds.",
        "- Gate 1 (wrong bud, wrong AirPods) is hard and runs before scoring, so other-bud attempts are not in these numbers.",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("data", type=Path, nargs="?", help="folder with spike attempt-*.json (outside the repo)")
    ap.add_argument("--test-logs", type=Path, nargs="+", metavar="DIR",
                    help="folders with the app's test-mode records (searched recursively); needs --report")
    ap.add_argument("--round", dest="rounds", action="append", nargs=4, metavar=("NAME", "TEMPLATES", "FROM", "TO"),
                    help="a named round: comma-separated template ids, first and last verify id (prefixes ok)")
    ap.add_argument("--min-dur", type=float, default=1.2, help="drop verify attempts not longer than this (s)")
    ap.add_argument("--owner-min", type=float, default=0.9, help="required owner acceptance rate in every round")
    ap.add_argument("--report", type=Path, help="write the markdown report here (e.g. archive/makeuc-2026/tuning.md)")
    ap.add_argument("--quick", action="store_true", help="small grid for a dry run")
    ap.add_argument("--note", default="", help="extra sentence about the data for the report")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")  # the report has ≥ and ÷; Windows pipes default to cp950

    if args.test_logs:
        for d in args.test_logs:
            if d.resolve().is_relative_to(REPO):
                print(f"[tuning] WARNING: {d} is inside the repo. Never commit signature recordings.", file=sys.stderr)
        if not args.report:
            ap.error("--test-logs needs --report (the charts are written next to it)")
        import evaluate
        evaluate.run(args.test_logs, args.report, args.note)
        return
    if args.data is None:
        ap.error("give DATA_DIR or --test-logs")
    data = args.data.resolve()
    if data.is_relative_to(REPO):
        print(f"[tuning] WARNING: {data} is inside the repo. Never commit signature recordings.", file=sys.stderr)

    attempts = M.load_dir(data)
    if args.rounds:
        sessions = []
        for name, templates, lo, hi in args.rounds:
            s = M.manual_session(attempts, templates.split(","), lo, hi, args.min_dur)
            if s:
                s.name = name
                sessions.append(s)
    else:
        sessions = M.auto_sessions(attempts, args.min_dur)
    sessions = [s for s in sessions if s.attempts]
    if not sessions:
        sys.exit("[tuning] no usable round (need templates followed by verify attempts)")
    owners = sum(a.who == "genuine" for s in sessions for a in s.attempts)
    fakes = sum(a.who == "forgery" for s in sessions for a in s.attempts)
    print(f"[tuning] {len(attempts)} files, {len(sessions)} round(s), {owners} owner and {fakes} imitator attempts",
          file=sys.stderr)
    if not owners or not fakes:
        print("[tuning] WARNING: need both owner and imitator attempts for a meaningful result", file=sys.stderr)

    rows = run_grid(sessions, QUICK if args.quick else FULL, progress=True)
    note = f"{len(sessions)} round(s), {owners} owner and {fakes} imitator attempts in total. {args.note}".strip()
    md = report(sessions, rows, args.owner_min, note)
    if args.report:
        args.report.write_text(md, encoding="utf-8")
        print(f"[tuning] wrote {args.report}", file=sys.stderr)
    else:
        print(md)


if __name__ == "__main__":
    main()
