"""Grid-search the AirSign matcher settings on recorded attempts.

Usage:
  python tune.py DATA_DIR [--report ../../docs/tuning.md] [--quick]
  python tune.py DATA_DIR --templates 20261107-144527-280,20261107-144533-012,20261107-144616-034 \
      --from 20261107-144617 --to 20261107-145000

DATA_DIR holds the spike's attempt-*.json files. Keep it OUTSIDE the repo:
signature recordings are biometric-like personal data and must never be committed.

Without --templates, each run of enroll attempts followed by verify attempts is
one session, and its last 3 enrolls are the templates. Verify attempts on the
other bud or not longer than --min-dur seconds are left out.

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
class Row:
    params: M.Params
    owner_ok: int
    owner_n: int
    imitator_ok: int
    imitator_n: int
    auc: float


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


def run_grid(sessions: list[M.Session], grid: Grid, progress: bool = False) -> list[Row]:
    rows = []
    total = len(grid.bands) * len(grid.weights)
    done = 0
    for band in grid.bands:
        for w in grid.weights:
            tables = [M.plain_dtw(s, band, w) for s in sessions]
            for dw in grid.duration_weights:
                owner, imitator = [], []
                for s, table in zip(sessions, tables):
                    sc = M.score_ratios(s, table, dw)
                    owner += sc.owner
                    imitator += sc.imitator
                a = M.auc(owner, imitator)
                for f in grid.factors:
                    rows.append(Row(M.Params(band, dw, f, w), M.accepted(owner, f), len(owner),
                                    M.accepted(imitator, f), len(imitator), a))
            done += 1
        if progress:
            print(f"[tuning] band {band:g} done ({done}/{total} band/weight combos)", file=sys.stderr, flush=True)
    return rows


def _closeness(p: M.Params) -> float:
    """How far a setting is from the plan's defaults; breaks ties toward fewer changes."""
    d = M.DEFAULT
    return (abs(p.band - d.band) / 0.15 + abs(p.duration_weight - d.duration_weight) / 0.5
            + abs(p.threshold_factor - d.threshold_factor) / 0.75 + sum(abs(x - 1) for x in p.weights))


def rank_key(r: Row):
    return (r.imitator_ok, -r.owner_ok, -(0 if math.isnan(r.auc) else r.auc), _closeness(r.params))


def pick_best(rows: list[Row], owner_min: float = 0.9, where=lambda r: True) -> Row | None:
    ok = [r for r in rows if where(r) and r.owner_ok >= math.ceil(owner_min * r.owner_n - 1e-9)]
    return min(ok, key=rank_key) if ok else None


def evaluate(sessions: list[M.Session], p: M.Params) -> Row:
    grid = Grid([p.band], [p.duration_weight], [p.threshold_factor], [p.weights])
    return run_grid(sessions, grid)[0]


def swift_constants(p: M.Params) -> str:
    """Turn group weights into the Swift feature scales (grav has no scale, so normalize to it)."""
    wr, wa, wg = p.weights
    if wg == 0:
        return "grav weight 0: Swift would need to drop the grav columns (interface change)"
    parts = []
    for name, w, base in (("rot", wr, M.ROT_SCALE), ("acc", wa, M.ACC_SCALE)):
        parts.append(f"{name} ÷ {base * wg / w:g}" if w else f"drop {name} columns (interface change)")
    return ", ".join(parts) + ", grav as is"


def fmt_w(w) -> str:
    return "/".join(f"{x:g}" for x in w)


def table_row(label: str, r: Row) -> str:
    p = r.params
    return (f"| {label} | {p.band:g} | {p.duration_weight:g} | {p.threshold_factor:g} | {fmt_w(p.weights)} "
            f"| {r.owner_ok}/{r.owner_n} | {r.imitator_ok}/{r.imitator_n} | {r.auc:.3f} |")


HEAD = ("| Setting | band | durationWeight | thresholdFactor | weights gyro/acc/grav | Owner accepted | Imitators accepted | AUC |\n"
        "|---|---|---|---|---|---|---|---|")


def report(sessions: list[M.Session], rows: list[Row], owner_min: float, data_note: str) -> str:
    base = evaluate(sessions, M.DEFAULT)
    best = pick_best(rows, owner_min)
    same_feats = pick_best(rows, owner_min, where=lambda r: r.params.weights == (1.0, 1.0, 1.0))
    lines = [
        "# AirSign matcher tuning",
        "",
        f"Generated by `tools/tuning/tune.py` on {datetime.now():%Y-%m-%d %H:%M}. {data_note}",
        f"Goal: owner accepted ≥ {owner_min:.0%}, as few imitators accepted as possible.",
        "",
        "## Data",
        "",
        "| Session | Bud | Templates | Owner attempts | Imitator attempts | Skipped: other bud | Skipped: too short |",
        "|---|---|---|---|---|---|---|",
    ]
    for s in sessions:
        own = sum(a.who == "genuine" for a in s.attempts)
        lines.append(f"| {s.name} | {s.side} | {len(s.templates)} | {own} | {len(s.attempts) - own} "
                     f"| {s.skipped['other bud']} | {s.skipped['too short']} |")
    lines += ["", "## Result", "", HEAD, table_row("Plan default (Task 3)", base)]
    if same_feats:
        lines.append(table_row("Best, same features", same_feats))
    if best:
        lines.append(table_row("**Best overall**", best))
    lines.append("")
    if not best:
        lines += [f"No setting in the grid reached owner ≥ {owner_min:.0%}.", ""]
    else:
        p = best.params
        lines += [
            "Swift `MatcherConfig` for the best overall:",
            "",
            f"- `thresholdFactor = {p.threshold_factor:g}`, `durationWeight = {p.duration_weight:g}`, DTW `band = {p.band:g}`",
            f"- Features: {swift_constants(p)}",
            "",
            "## Threshold sweep for the best band, durationWeight and weights",
            "",
            "| thresholdFactor | Owner accepted | Imitators accepted |",
            "|---|---|---|",
        ]
        sweep = [r for r in rows if r.params.band == p.band and r.params.duration_weight == p.duration_weight
                 and r.params.weights == p.weights]
        lines += [f"| {r.params.threshold_factor:g} | {r.owner_ok}/{r.owner_n} | {r.imitator_ok}/{r.imitator_n} |"
                  for r in sweep]
        lines += ["", "## Top 10 settings", "", HEAD]
        top = sorted((r for r in rows if r.owner_ok >= math.ceil(owner_min * r.owner_n - 1e-9)), key=rank_key)[:10]
        lines += [table_row(str(i + 1), r) for i, r in enumerate(top)]
    lines += [
        "",
        "## Caveats",
        "",
        "- Few attempts, so one attempt moves a rate by 5–10 points. Prefer a setting whose neighbours in the sweep are also good.",
        "- AUC does not depend on thresholdFactor; it shows how well band, durationWeight and weights separate owner from imitators.",
        "- Gate 1 (wrong bud, wrong AirPods) is hard and not part of these numbers: other-bud attempts are rejected before scoring.",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("data", type=Path, help="folder with attempt-*.json (outside the repo)")
    ap.add_argument("--templates", help="comma-separated template ids (prefixes ok); default: auto sessions")
    ap.add_argument("--from", dest="lo", help="first verify id to use (prefix), with --templates")
    ap.add_argument("--to", dest="hi", help="last verify id to use (prefix), with --templates")
    ap.add_argument("--min-dur", type=float, default=1.2, help="drop verify attempts not longer than this (s)")
    ap.add_argument("--owner-min", type=float, default=0.9, help="required owner acceptance rate")
    ap.add_argument("--report", type=Path, help="write the markdown report here (e.g. docs/tuning.md)")
    ap.add_argument("--quick", action="store_true", help="small grid for a dry run")
    ap.add_argument("--note", default="", help="extra sentence about the data for the report")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")  # the report has ≥ and ÷; Windows pipes default to cp950

    data = args.data.resolve()
    if data.is_relative_to(REPO):
        print(f"[tuning] WARNING: {data} is inside the repo. Never commit signature recordings.", file=sys.stderr)

    attempts = M.load_dir(data)
    if args.templates:
        s = M.manual_session(attempts, args.templates.split(","), args.lo, args.hi, args.min_dur)
        sessions = [s] if s else []
    else:
        sessions = M.auto_sessions(attempts, args.min_dur)
    sessions = [s for s in sessions if s.attempts]
    if not sessions:
        sys.exit("[tuning] no usable session (need 3 enrolls followed by verify attempts)")
    owners = sum(a.who == "genuine" for s in sessions for a in s.attempts)
    fakes = sum(a.who == "forgery" for s in sessions for a in s.attempts)
    print(f"[tuning] {len(attempts)} files, {len(sessions)} session(s), {owners} owner and {fakes} imitator attempts",
          file=sys.stderr)
    if not owners or not fakes:
        print("[tuning] WARNING: need both owner and imitator attempts for a meaningful result", file=sys.stderr)

    rows = run_grid(sessions, QUICK if args.quick else FULL, progress=True)
    note = f"{len(sessions)} session(s), {owners} owner and {fakes} imitator attempts. {args.note}".strip()
    md = report(sessions, rows, args.owner_min, note)
    if args.report:
        args.report.write_text(md, encoding="utf-8")
        print(f"[tuning] wrote {args.report}", file=sys.stderr)
    else:
        print(md)


if __name__ == "__main__":
    main()
