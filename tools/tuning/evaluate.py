"""Test protocol v2 analysis (archive/makeuc-2026/test-protocol.md, archive/makeuc-2026/algorithm-bakeoff.md): shared core plus archive/makeuc-2026/evaluation.md.

Run through tune.py:
  python tune.py --test-logs /path/to/airsign-data/mac1 /path/to/airsign-data/mac2 --report ../../archive/makeuc-2026/evaluation.md

Rules this file encodes:
- The baseline (the app today, thresholdFactor 1.25) is frozen and primary.
- Owners enroll once, at the start of S1. Every attempt, S2 and S3 included, is scored
  against the owner's S1 templates.
- A tuned factor is chosen from S1 owner attempts only: the smallest factor with S1
  owner acceptance ≥ 95%, plus 0.10. It is then applied unchanged to S2/S3.
- Rates are reported per owner and scenario as k/n with Wilson 95% intervals.
  A2 is the false accept rate (FAR); A3 and A4 are attacks, reported as attack
  success rates (ISO/IEC 30107-3 style). EER is reported for S1 only.
"""
from __future__ import annotations

import math
import statistics
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import matcher as M
import svgchart

OWNER, A2, A3, A4 = "A1-owner", "A2-zero-effort", "A3-watched-once", "A4-skilled"
IMITATION = [A2, A3, A4]
GATE1 = ["A5-other-bud", "A5-other-pair"]
SCENARIOS = [OWNER, *IMITATION, *GATE1]
S1, S2, S3, S4 = "S1-tonight", "S2-midnight", "S3-morning", "S4-extra"
SESSIONS = [S1, S2, S3, S4]
LATER = [S2, S3, S4]
GATE1_REJECTIONS = {"wrongBud", "wrongDevice"}
FROZEN_FACTOR = M.DEFAULT.threshold_factor  # 1.25
OWNER_TARGET = 0.95
MARGIN = 0.10
Z95 = 1.959964
DISCLOSURE = ("Disclosure: C (teammate) was both an imitator in these tests and the person who wrote this analysis. "
              "The baseline and its 1.25 factor were frozen and committed before any test data existed, and every "
              "tuned factor uses S1 owner attempts only, never imitator data.")
FACTORS = [round(1.0 + 0.05 * i, 2) for i in range(21)]


# ---------- data ----------

@dataclass
class Case:
    rec: M.Logged
    templates: tuple  # the owner's S1 enroll records
    key: str  # their enrollment fingerprint
    side: str

    @property
    def gate1(self) -> bool:
        return self.rec.rejection in GATE1_REJECTIONS or self.rec.loc != self.side


@dataclass
class Data:
    cases: list[Case]
    dropped_device_unknown: int = 0
    not_replayable: int = 0
    reenrolled_after_s1: int = 0  # later records whose own enrollment wasn't the owner's S1 one
    unknown_scenario: int = 0
    sample_rates: dict[str, float] = field(default_factory=dict)


def _folder(rec_id: str) -> str:
    return rec_id.split("/", 1)[0] if "/" in rec_id else "all"


def build(records: list[M.Logged]) -> Data:
    enrolls: dict[str, list[M.Logged]] = defaultdict(list)
    s1_by_owner: dict[str, list[str]] = defaultdict(list)
    for r in records:
        if r.mode == "enroll":
            enrolls[r.enrollment].append(r)
            if r.session == S1 and r.enrollment not in s1_by_owner[r.owner]:
                s1_by_owner[r.owner].append(r.enrollment)
    data = Data(cases=[])
    rates = defaultdict(list)
    for r in records:
        if r.dur > 0:
            rates[_folder(r.id)].append((len(r.rows) - 1) / r.dur)
        if r.mode != "verify":
            continue
        if r.rejection == "deviceUnknown":
            data.dropped_device_unknown += 1
            continue
        if r.scenario not in SCENARIOS:
            data.unknown_scenario += 1
            continue
        s1 = s1_by_owner.get(r.owner, [])
        if r.session == S1 and r.enrollment in s1:
            fp = r.enrollment
        elif s1:
            fp = s1[-1]
            if r.session != S1 and r.enrollment != fp:
                data.reenrolled_after_s1 += 1
        else:
            fp = r.enrollment
        templates = enrolls.get(fp, [])
        if len(templates) < 2 or len({t.loc for t in templates}) != 1:
            data.not_replayable += 1
            continue
        data.cases.append(Case(r, tuple(templates), fp, templates[0].loc))
    data.sample_rates = {k: statistics.median(v) for k, v in sorted(rates.items())}
    return data


# ---------- scoring ----------

def reference(alg, templates: list, normalized: bool | None = None) -> float:
    """The templates' own spread under this algorithm: threshold = factor × reference.

    A self-normalized score (already divided by the templates' spread) has reference 1, so its
    threshold is the factor itself. `normalized` overrides the function's `self_normalized` mark.
    """
    if normalized if normalized is not None else getattr(alg, "self_normalized", False):
        return 1.0
    ts = templates
    return max(alg(ts[i], [ts[j]]) for i in range(len(ts)) for j in range(i + 1, len(ts)))


def ratios(alg, cases: list[Case], normalized: bool | None = None) -> list[float]:
    """score ÷ reference per case; inf when gate 1 rejects (or the score is undefined)."""
    refs: dict[str, float] = {}
    out = []
    for c in cases:
        if c.gate1:
            out.append(math.inf)
            continue
        if c.key not in refs:
            refs[c.key] = max(reference(alg, list(c.templates), normalized), 1e-9)
        s = alg(c.rec, list(c.templates))
        out.append(s / refs[c.key] if math.isfinite(s) else math.inf)
    return out


# ---------- statistics ----------

def wilson(k: int, n: int, z: float = Z95) -> tuple[float, float]:
    if n == 0:
        return math.nan, math.nan
    p = k / n
    den = 1 + z * z / n
    mid = (p + z * z / (2 * n)) / den
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return max(0.0, mid - half), min(1.0, mid + half)


@dataclass
class Rate:
    k: int
    n: int

    @property
    def rate(self) -> float:
        return self.k / self.n if self.n else math.nan

    @property
    def ci(self) -> tuple[float, float]:
        return wilson(self.k, self.n)

    def __str__(self) -> str:
        if not self.n:
            return "–"
        lo, hi = self.ci
        return f"{self.k}/{self.n} ({pct(lo)}–{pct(hi)})"

    def __add__(self, other: "Rate") -> "Rate":
        return Rate(self.k + other.k, self.n + other.n)


def pct(x: float) -> str:
    if x is None or math.isnan(x):
        return "–"
    return f"{x * 100:.0f}%" if x == 0 or x == 1 or x >= 0.1 else f"{x * 100:.1f}%"


def rate(cases: list[Case], rs: list[float], factor: float, pred) -> Rate:
    sel = [r for c, r in zip(cases, rs) if pred(c.rec)]
    return Rate(sum(r <= factor for r in sel), len(sel))


def is_(scenario: str, sessions=None, owner: str | None = None):
    def pred(rec: M.Logged) -> bool:
        return (rec.scenario == scenario and (sessions is None or rec.session in sessions)
                and (owner is None or rec.owner == owner))
    return pred


def s1_factor(cases: list[Case], rs: list[float]) -> float | None:
    """Smallest factor with S1 owner acceptance ≥ 95%, plus the 0.10 margin. Owner data only."""
    owner = sorted(r for c, r in zip(cases, rs) if c.rec.scenario == OWNER and c.rec.session == S1)
    if not owner:
        return None
    need = math.ceil(OWNER_TARGET * len(owner) - 1e-9)
    f0 = owner[need - 1]
    return f0 + MARGIN if math.isfinite(f0) else None


def eer(owner: list[float], imitator: list[float]) -> tuple[float, float]:
    """Equal error rate and the factor where false accepts ≈ false rejects."""
    if not owner or not imitator:
        return math.nan, math.nan
    cands = sorted({0.0, *[x for x in owner + imitator if math.isfinite(x)]})
    best = (math.inf, math.nan, math.nan)
    for t in cands + [cands[-1] * 1.001 + 1e-9]:
        frr = sum(x > t for x in owner) / len(owner)
        far = sum(x <= t for x in imitator) / len(imitator)
        if abs(far - frr) < best[0]:
            best = (abs(far - frr), (far + frr) / 2, t)
    return best[1], best[2]


def s1_eer(cases: list[Case], rs: list[float]) -> tuple[float, float]:
    owner = [r for c, r in zip(cases, rs) if c.rec.scenario == OWNER and c.rec.session == S1]
    imit = [r for c, r in zip(cases, rs) if c.rec.scenario in IMITATION and c.rec.session == S1]
    return eer(owner, imit)


def auc(owner: list[float], imitator: list[float]) -> float:
    if not owner or not imitator:
        return math.nan
    wins = sum((f > o) + 0.5 * (f == o) for f in imitator for o in owner)
    return wins / (len(owner) * len(imitator))


def mcnemar_one_sided(b: int, c: int) -> float:
    """P(at least b of the b+c discordant pairs favour the challenger | no real difference)."""
    n = b + c
    return sum(math.comb(n, i) for i in range(b, n + 1)) / 2 ** n if n else 1.0


def upper_rule_of_three(n: int) -> float:
    return min(1.0, 3 / n) if n else math.nan


def owners(cases: list[Case]) -> list[str]:
    return sorted({c.rec.owner for c in cases})


def sessions_present(cases: list[Case]) -> list[str]:
    have = {c.rec.session for c in cases}
    return [s for s in SESSIONS if s in have]


def app_match(cases: list[Case], alg) -> float:
    """Median relative gap between the app's logged score and the replay, where both used the same templates."""
    gaps = []
    for c in cases:
        if c.key == c.rec.enrollment and c.rec.score and math.isfinite(c.rec.score):
            gaps.append(abs(alg(c.rec, list(c.templates)) - c.rec.score) / c.rec.score)
    return statistics.median(gaps) if gaps else math.nan


# ---------- report pieces shared with bakeoff.py ----------

def data_section(data: Data, note: str = "", extra: list[str] | None = None) -> list[str]:
    cases = data.cases
    L = ["## Data", "", "| Owner | Bud | Session | " + " | ".join(SCENARIOS) + " |",
         "|---|---|---|" + "---|" * len(SCENARIOS)]
    for o in owners(cases):
        side = next(c.side for c in cases if c.rec.owner == o)
        for s in sessions_present(cases):
            counts = [sum(c.rec.owner == o and c.rec.session == s and c.rec.scenario == sc for c in cases)
                      for sc in SCENARIOS]
            if any(counts):
                L.append(f"| {o} | {side} | {s} | " + " | ".join(map(str, counts)) + " |")
    rates = ", ".join(f"{k} {v:.1f}/s" for k, v in data.sample_rates.items())
    L += ["",
          f"- Sample rate (median rows ÷ seconds, per folder): {rates}.",
          "- Every attempt is scored against its owner's S1 enrollment (owners don't re-enroll after S1)."
          + (f" {data.reenrolled_after_s1} later attempts were logged against a newer enrollment; they are scored "
             "against S1 anyway." if data.reenrolled_after_s1 else ""),
          f"- Left out: {data.dropped_device_unknown} attempts the app didn't count (sound output wasn't the AirPods), "
          f"{data.not_replayable} without logged templates, {data.unknown_scenario} with an unknown scenario. "
          "Discarded tries (finger slipped, too short) are never logged; see the paper tally."]
    if note:
        L.append(f"- {note}")
    return L + (extra or []) + [""]


def owner_table(cases: list[Case], rs: list[float], factor: float) -> list[str]:
    """Per owner × scenario k/n (Wilson 95%). A1 by session; A4 split S1 (saw the screen) vs S3 (blind)."""
    cols = [(f"A1 {s[:2]}", is_(OWNER, [s])) for s in sessions_present(cases)]
    cols += [("A2 FAR", is_(A2)), ("A3 attack", is_(A3)), ("A4 attack S1", is_(A4, [S1])),
             ("A4 attack S3", is_(A4, [S3])), ("A5 gate 1", lambda r: r.scenario in GATE1)]
    L = ["| Owner | " + " | ".join(n for n, _ in cols) + " |", "|---|" + "---|" * len(cols)]
    for o in owners(cases) + ["all"]:
        cells = []
        for _, pred in cols:
            p = pred if o == "all" else (lambda r, pred=pred, o=o: pred(r) and r.owner == o)
            cells.append(str(rate(cases, rs, factor, p)))
        L.append(f"| {'**all**' if o == 'all' else o} | " + " | ".join(cells) + " |")
    return L


def quotable(cases: list[Case], rs: list[float], factor: float) -> list[str]:
    own = rate(cases, rs, factor, is_(OWNER))
    a2 = rate(cases, rs, factor, is_(A2))
    a3 = rate(cases, rs, factor, is_(A3))
    a4 = rate(cases, rs, factor, is_(A4))
    out = []
    if own.n:
        lo, hi = own.ci
        out.append(f"- The owners got in {own.k}/{own.n} times (Wilson 95% interval {pct(lo)}–{pct(hi)}).")
    for label, r in (("zero-effort imitations (FAR) got in", a2), ("watched-once attacks succeeded", a3),
                     ("skilled attacks succeeded", a4)):
        if r.n:
            lo, hi = r.ci
            extra = f"; rule of three: below {pct(upper_rule_of_three(r.n))}" if r.k == 0 else ""
            out.append(f"- For these imitators, {label} {r.k}/{r.n} times (Wilson 95% interval {pct(lo)}–{pct(hi)}{extra}).")
    return out


# ---------- archive/makeuc-2026/evaluation.md ----------

def report(data: Data, rs: list[float], tuned: float | None, match: float, charts: dict[str, str],
           note: str = "") -> str:
    cases = data.cases
    eer_v, eer_f = s1_eer(cases, rs)
    L = ["# AirSign evaluation", "",
         f"Generated by `tools/tuning/tune.py --test-logs` on {datetime.now():%Y-%m-%d %H:%M}, following test protocol v2 "
         "([test-protocol.md](test-protocol.md), [algorithm-bakeoff.md](algorithm-bakeoff.md)). The recordings stay off "
         "the repo. Only 2 owners and a handful of imitators: these numbers describe **these imitators**, not people in "
         "general.", "", f"> {DISCLOSURE}", ""]
    L += data_section(data, note, [f"- Check: the Python baseline matches the app's logged scores to a median {pct(match)}."])
    L += [f"## Frozen baseline (the app today, thresholdFactor {FROZEN_FACTOR:g})", "",
          "k/n accepted, Wilson 95% interval. A2 is the false accept rate; A3 and A4 are attack success rates "
          "(ISO/IEC 30107-3 style), kept apart from FAR.", ""]
    L += owner_table(cases, rs, FROZEN_FACTOR)
    L += ["", "### Quotable", ""] + quotable(cases, rs, FROZEN_FACTOR)
    L += [f"- S1 equal error rate (owner vs A2–A4): {pct(eer_v)}, at factor {eer_f:.2f}. Reported for S1 only.", ""]
    L += ["## Threshold from S1 owners only", ""]
    if tuned is None:
        L += ["Not enough S1 owner attempts to choose a factor.", ""]
    else:
        L += [f"The smallest factor that accepts ≥ {OWNER_TARGET:.0%} of S1 owner attempts, plus {MARGIN:.2f}, is "
              f"**{tuned:.3f}**. It was chosen without looking at any imitator data and is applied unchanged to S2/S3. "
              f"This is secondary: the frozen {FROZEN_FACTOR:g} stays primary.", ""]
        L += owner_table(cases, rs, tuned)
        if tuned > FROZEN_FACTOR:
            L += ["", f"It is above {FROZEN_FACTOR:g}; the demo threshold override can only tighten, so using it means "
                      "changing the default in code."]
        L.append("")
    L += ["## Charts", "", f"![Scores by scenario]({charts['scores']})", "",
          "Each dot is one attempt: its score divided by the worst distance between the owner's own S1 templates. "
          "It is accepted when it sits left of the threshold line.", "",
          f"![Acceptance vs thresholdFactor]({charts['sweep']})", "",
          "## Caveats", "",
          "- 2 owners and few imitators: no claim about the general population.",
          "- A4 imitators saw the score and gate lights in S1; in S3 they signed blind.",
          "- Gate 1 (A5) comes from the app's record: the replay can't see the AirPods' device ID.",
          f"- {DISCLOSURE}", ""]
    return "\n".join(L)


def draw_scores(cases: list[Case], rs: list[float], tuned: float | None, path: Path) -> None:
    rows = [svgchart.StripRow("A1 owner, S1", [r for c, r in zip(cases, rs) if is_(OWNER, [S1])(c.rec)], "owner"),
            svgchart.StripRow("A1 owner, S2+S3", [r for c, r in zip(cases, rs) if is_(OWNER, LATER)(c.rec)], "owner")]
    for sc, label in ((A2, "A2 zero-effort"), (A3, "A3 watched once"), (A4, "A4 skilled")):
        rows.append(svgchart.StripRow(label, [r for c, r in zip(cases, rs) if c.rec.scenario == sc], "imitator"))
    marks = [svgchart.Mark(FROZEN_FACTOR, f"frozen {FROZEN_FACTOR:g}")]
    if tuned is not None and abs(tuned - FROZEN_FACTOR) > 1e-6:
        marks.append(svgchart.Mark(tuned, f"S1 owner-only {tuned:.2f}", dashed=True))
    svgchart.strip_plot(path, "Baseline score ÷ worst S1 template pair, by scenario", rows, marks)


def draw_sweep(cases: list[Case], rs: list[float], path: Path) -> None:
    preds = [("Owner S1", is_(OWNER, [S1])), ("Owner S2+S3", is_(OWNER, LATER)), ("A2 FAR", is_(A2)),
             ("A3+A4 attacks", lambda r: r.scenario in (A3, A4))]
    series = [svgchart.Series(name, [rate(cases, rs, f, p).rate for f in FACTORS]) for name, p in preds]
    svgchart.line_chart(path, "Baseline acceptance vs thresholdFactor", FACTORS, series,
                        hline=(OWNER_TARGET, f"owner target {OWNER_TARGET:.0%}"),
                        vline=(FROZEN_FACTOR, f"frozen {FROZEN_FACTOR:g}"))


def load(dirs: list[Path]) -> Data:
    records = M.load_logs(dirs)
    data = build(records)
    print(f"[tuning] {len(records)} records, {len(data.cases)} replayable attempts", file=sys.stderr)
    if not data.cases:
        sys.exit("[tuning] nothing to replay: need S1 enroll records and verify records from the same owner")
    return data


def run(dirs: list[Path], report_path: Path, note: str = "") -> None:
    import algorithms_ref as R  # the app's baseline; bakeoff.py compares the challengers
    data = load(dirs)
    rs = ratios(R.baseline, data.cases)
    tuned = s1_factor(data.cases, rs)
    chart_dir = report_path.parent / "evaluation"
    chart_dir.mkdir(parents=True, exist_ok=True)
    draw_scores(data.cases, rs, tuned, chart_dir / "scores.svg")
    draw_sweep(data.cases, rs, chart_dir / "acceptance.svg")
    text = report(data, rs, tuned, app_match(data.cases, R.baseline),
                  {"scores": "evaluation/scores.svg", "sweep": "evaluation/acceptance.svg"}, note)
    report_path.write_text(text, encoding="utf-8")
    print(f"[tuning] wrote {report_path} and {chart_dir}", file=sys.stderr)
