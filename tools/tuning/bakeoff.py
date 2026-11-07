"""Algorithm bake-off (docs/algorithm-bakeoff.md): the frozen baseline against the three pre-registered challengers.

Usage:
  python bakeoff.py C:/airsign-data/mac1 C:/airsign-data/mac2 --report ../../docs/algorithm-comparison.md

The folders hold the app's test-mode records (searched recursively); keep them
outside the repo. The baseline is the app today at thresholdFactor 1.25 and is
never tuned. Each challenger's factor comes from S1 owner attempts only
(smallest factor with S1 owner acceptance ≥ 95%, plus 0.10) and is applied
unchanged to S2/S3. A challenger replaces the baseline only if all three rules hold:

1. Paired on the same S2+S3 owner attempts, it rejects the owner no more often.
2. Its S1 factor still holds on S2 and on S3: the owner's Wilson 95% interval
   there still reaches 95%.
3. On S3 A4 plus all A3 attacks, it accepts fewer imitations, with a paired
   advantage at least as strong as 7:0 (exact one-sided McNemar p ≤ 2^-7,
   which is what 7:0 gives; three challengers are being tested at once).
"""
from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import algorithms_ref as R
import evaluate as E

REPO = Path(__file__).resolve().parents[2]
CHALLENGERS = ["gyro_x2", "normalized_nfm", "dtw_plus_global"]
P_7_0 = 0.5 ** 7


def load_algorithms() -> tuple[dict, dict[str, str]]:
    """Baseline from algorithms_ref (checked against the app's logged scores); challengers from
    algorithms.py when role B's file has them, otherwise from the reference port."""
    algs, source = {"baseline": R.baseline}, {"baseline": "algorithms_ref.py (checked against the app's logged scores)"}
    try:
        import algorithms as B  # role B's file, docs/algorithm-bakeoff.md
        theirs = getattr(B, "ALGORITHMS", {})
    except ImportError:
        theirs = {}
    for name in CHALLENGERS:
        if name in theirs:
            algs[name], source[name] = theirs[name], "algorithms.py"
        else:
            algs[name], source[name] = R.ALGORITHMS[name], "algorithms_ref.py (reference port of quick_candidates.py)"
    return algs, source


@dataclass
class Result:
    name: str
    rs: list[float]
    factor: float | None  # None: no factor reaches 95% of S1 owner attempts
    frozen: bool

    def accepted(self, i: int) -> bool:
        return self.factor is not None and self.rs[i] <= self.factor


def evaluate_all(cases: list[E.Case], algs: dict) -> list[Result]:
    out = []
    for name, alg in algs.items():
        rs = E.ratios(alg, cases)
        frozen = name == "baseline"
        out.append(Result(name, rs, E.FROZEN_FACTOR if frozen else E.s1_factor(cases, rs), frozen))
        print(f"[bakeoff] {name}: factor {out[-1].factor}", file=sys.stderr)
    return out


@dataclass
class Rule:
    ok: bool | None  # None = not enough data yet
    text: str


def mark(r: Rule) -> str:
    return {True: "✅", False: "❌", None: "⏳"}[r.ok] + " " + r.text


def switch_rules(cases: list[E.Case], base: Result, ch: Result) -> list[Rule]:
    if ch.factor is None:
        no = Rule(False, "no factor reaches 95% of S1 owner attempts")
        return [no, no, no]
    later = [i for i, c in enumerate(cases) if c.rec.scenario == E.OWNER and c.rec.session in (E.S2, E.S3)]
    rej_b = sum(not base.accepted(i) for i in later)
    rej_c = sum(not ch.accepted(i) for i in later)
    b = sum(not base.accepted(i) and ch.accepted(i) for i in later)
    c = sum(base.accepted(i) and not ch.accepted(i) for i in later)
    r1 = Rule(None if not later else rej_c <= rej_b,
              f"owner rejections on S2+S3: {rej_c} vs baseline {rej_b} (only baseline rejects : only challenger rejects = {b}:{c})" if later else "no S2/S3 owner data yet")

    cells = {s: E.rate(cases, ch.rs, ch.factor, E.is_(E.OWNER, [s])) for s in (E.S2, E.S3)}
    if any(r.n == 0 for r in cells.values()):
        r2 = Rule(None, "needs owner attempts in both S2 and S3")
    else:
        holds = all(r.ci[1] >= E.OWNER_TARGET for r in cells.values())
        r2 = Rule(holds, "; ".join(f"{s[:2]} owner {r}" for s, r in cells.items()))

    attacks = [i for i, cc in enumerate(cases)
               if cc.rec.scenario == E.A3 or (cc.rec.scenario == E.A4 and cc.rec.session == E.S3)]
    has_s3_a4 = any(cases[i].rec.scenario == E.A4 for i in attacks)
    b3 = sum(base.accepted(i) and not ch.accepted(i) for i in attacks)
    c3 = sum(ch.accepted(i) and not base.accepted(i) for i in attacks)
    p = E.mcnemar_one_sided(b3, c3)
    text = (f"S3 A4 + all A3 ({len(attacks)} attempts): only baseline accepts : only challenger accepts = {b3}:{c3}, "
            f"one-sided p = {p:.4f}")
    r3 = Rule(None if not has_s3_a4 else (b3 > c3 and p <= P_7_0 + 1e-12),
              text if has_s3_a4 else "needs S3 A4 attempts")
    return [r1, r2, r3]


def verdict(rules: list[Rule]) -> str:
    if all(r.ok for r in rules):
        return "**switch**"
    if any(r.ok is False for r in rules):
        return "keep baseline"
    return "pending"


def report(data: E.Data, results: list[Result], source: dict[str, str], note: str = "") -> str:
    cases = data.cases
    base = results[0]
    L = ["# Algorithm comparison (bake-off)", "",
         f"Generated by `tools/tuning/bakeoff.py` on {datetime.now():%Y-%m-%d %H:%M} under the rules in "
         "[algorithm-bakeoff.md](algorithm-bakeoff.md) and test protocol v2. Only 2 owners and a handful of imitators: "
         "every number describes **these imitators**, as k/n with a Wilson 95% interval.", "", f"> {E.DISCLOSURE}", "",
         "- `baseline` is the app today at thresholdFactor 1.25: frozen, primary, never tuned.",
         "- Challengers (pre-registered, exactly three): " + ", ".join(f"`{n}`" for n in CHALLENGERS) + ".",
         "- Each challenger's factor = the smallest factor accepting ≥ 95% of **S1 owner** attempts, plus 0.10. No "
         "imitator data is used, and it isn't changed for S2/S3.",
         "- Code used: " + "; ".join(f"`{k}` from {v}" for k, v in source.items()) + ".", ""]
    L += E.data_section(data, note)

    L += ["## Main table", "",
          "A2 is the false accept rate (FAR). A3 and A4 are attacks, reported as attack success rates (ISO/IEC 30107-3 "
          "style). In S1 the A4 imitators saw the score and lights; in S3 they signed blind. EER is for S1 only.", "",
          "| Algorithm | Factor | Owner S1 | Owner S2+S3 | A2 FAR | A3 attack | A4 attack S1 | A4 attack S3 "
          "| A4 AUC | S1 EER |", "|---|---|---|---|---|---|---|---|---|---|"]
    for res in results:
        f = res.factor
        if f is None:
            L.append(f"| `{res.name}` | none reaches 95% on S1 | | | | | | | | |")
            continue
        own = [r for cc, r in zip(cases, res.rs) if cc.rec.scenario == E.OWNER]
        a4 = [r for cc, r in zip(cases, res.rs) if cc.rec.scenario == E.A4]
        eer_v, _ = E.s1_eer(cases, res.rs)
        label = f"{f:g} (frozen)" if res.frozen else f"{f:.3f}"
        cells = [E.rate(cases, res.rs, f, E.is_(E.OWNER, [E.S1])), E.rate(cases, res.rs, f, E.is_(E.OWNER, E.LATER)),
                 E.rate(cases, res.rs, f, E.is_(E.A2)), E.rate(cases, res.rs, f, E.is_(E.A3)),
                 E.rate(cases, res.rs, f, E.is_(E.A4, [E.S1])), E.rate(cases, res.rs, f, E.is_(E.A4, [E.S3]))]
        L.append(f"| `{res.name}` | {label} | " + " | ".join(map(str, cells))
                 + f" | {E.auc(own, a4):.3f} | {E.pct(eer_v)} |")
    a4s = [E.rate(cases, res.rs, res.factor, E.is_(E.A4)) for res in results if res.factor is not None]
    zero = [(res.name, r) for res, r in zip([x for x in results if x.factor is not None], a4s) if r.n and r.k == 0]
    if zero:
        L += ["", "A4 (skilled) with no success: " + "; ".join(
            f"`{n}` 0/{r.n}, rule-of-three 95% upper bound {E.pct(E.upper_rule_of_three(r.n))}" for n, r in zero) + "."]
    L.append("")

    L += ["## Switch rule (all three must hold)", "",
          "| Challenger | 1. Owner rejections, paired (S2+S3) | 2. S1 factor holds on S2 and S3 | "
          "3. S3 A4 + all A3, paired ≥ 7:0 | Verdict |", "|---|---|---|---|---|"]
    verdicts = {}
    for res in results[1:]:
        rules = switch_rules(cases, base, res)
        verdicts[res.name] = verdict(rules)
        L.append(f"| `{res.name}` | " + " | ".join(mark(r) for r in rules) + f" | {verdicts[res.name]} |")
    L += ["", "Rule 2 holds when, in each of S2 and S3 separately, the upper end of the owner's Wilson 95% interval "
              "is still ≥ 95%: the data don't show the owner rate falling below the target. Rule 3's bar is the exact "
              "one-sided McNemar p of a 7:0 split (2^-7 ≈ 0.0078).", ""]

    switch = [n for n, v in verdicts.items() if v == "**switch**"]
    pending = [n for n, v in verdicts.items() if v == "pending"]
    L += ["## Recommendation", ""]
    if switch:
        L.append(f"Switch candidates: {', '.join(f'`{n}`' for n in switch)}. Each passes all three rules; decide by "
                 "09:30, and list the Swift lines to change before committing to it.")
    elif pending:
        L.append(f"Keep `baseline` for now. Still waiting on S2/S3 data for: {', '.join(f'`{n}`' for n in pending)}.")
    else:
        L.append("Keep `baseline`. No challenger passed all three rules, which is the expected outcome and itself "
                 "the evidence: the frozen method was not beaten under a fair, pre-registered test.")
    L += ["", "## Per owner, at each algorithm's factor", ""]
    for res in results:
        if res.factor is None:
            continue
        L += [f"### `{res.name}` (factor {res.factor:.3f})", ""] + E.owner_table(cases, res.rs, res.factor) + [""]
    L += ["## Quotable (frozen baseline)", ""] + E.quotable(cases, base.rs, base.factor) + [""]
    L += ["## Caveats", "",
          "- `normalized_nfm` and `dtw_plus_global` are already divided by the templates' own spread, so their factor "
          "is a global constant on their own scale (about 3 and 2 for typical owner attempts). The fixed +0.10 margin is "
          "relatively smaller for them than for `baseline` and `gyro_x2`.",
          "- AUC alone misleads here: on the prototype data `dtw_plus_global` had the best AUC but let in 11/14 "
          "imitations at its real threshold. Decide by the switch rule, not by AUC.",
          "- Gate 1 (A5) comes from the app's record: the replay can't see the AirPods' device ID.",
          f"- {E.DISCLOSURE}", ""]
    return "\n".join(L)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dirs", type=Path, nargs="+", help="folders with test-mode records (outside the repo)")
    ap.add_argument("--report", type=Path, required=True, help="e.g. ../../docs/algorithm-comparison.md")
    ap.add_argument("--note", default="", help="extra line for the data section, e.g. the paper tally of discarded tries")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    for d in args.dirs:
        if d.resolve().is_relative_to(REPO):
            print(f"[bakeoff] WARNING: {d} is inside the repo. Never commit signature recordings.", file=sys.stderr)
    data = E.load(args.dirs)
    algs, source = load_algorithms()
    results = evaluate_all(data.cases, algs)
    args.report.write_text(report(data, results, source, args.note), encoding="utf-8")
    print(f"[bakeoff] wrote {args.report}", file=sys.stderr)


if __name__ == "__main__":
    main()
