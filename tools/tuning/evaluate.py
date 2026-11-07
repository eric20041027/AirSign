"""Evaluate the app's test-mode records (docs/test-protocol.md) and write docs/evaluation.md.

Run through tune.py:
  python tune.py --test-logs C:/airsign-data/test-logs-mac1 C:/airsign-data/test-logs-mac2 \
      --report ../../docs/evaluation.md

Each verify record is replayed against the templates of its own enrollment (the
enroll records with the same "enrollment" fingerprint), the way the Swift app
does it, so thresholdFactor and FeatureScale.rotation can be changed after the fact.
"""
from __future__ import annotations

import math
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import matcher as M
import svgchart

OWNER = "A1-owner"
IMITATION = ["A2-zero-effort", "A3-watched-once", "A4-skilled"]
GATE1 = ["A5-other-bud", "A5-other-pair"]
SCENARIOS = [OWNER, *IMITATION, *GATE1]
SESSIONS = ["S1-tonight", "S2-midnight", "S3-morning", "S4-extra"]
GATE1_REJECTIONS = {"wrongBud", "wrongDevice"}
OWNER_MIN = 0.95
CURRENT_FACTOR = M.DEFAULT.threshold_factor
FACTORS = [round(1.0 + 0.05 * i, 2) for i in range(21)]


@dataclass(frozen=True)
class Setting:
    name: str
    weights: tuple[float, float, float]  # gyro, acc, grav
    rotation_scale: float


SETTINGS = [Setting("FeatureScale.rotation = 3 (today)", (1.0, 1.0, 1.0), 3.0),
            Setting("FeatureScale.rotation = 1.5", (1.0, 0.5, 0.5), 1.5)]


@dataclass
class Group:
    enrollment: str
    owner: str
    side: str
    templates: list[M.Logged]
    attempts: list[M.Logged]


@dataclass
class Scored:
    rec: M.Logged
    ratio: float  # score ÷ worst template pair; accepted at factor f when ratio <= f; inf when gate 1 rejects
    score: float


@dataclass
class Data:
    groups: list[Group]
    dropped_device_unknown: int = 0
    not_replayable: list[M.Logged] = field(default_factory=list)  # enrollment never logged
    unknown_scenario: int = 0


# ---------- grouping and replay ----------

def build(records: list[M.Logged]) -> Data:
    enrolls, verifies = defaultdict(list), defaultdict(list)
    data = Data(groups=[])
    for r in records:
        if r.mode == "enroll":
            enrolls[r.enrollment].append(r)
        elif r.rejection == "deviceUnknown":
            data.dropped_device_unknown += 1
        elif r.scenario not in SCENARIOS:
            data.unknown_scenario += 1
        else:
            verifies[r.enrollment].append(r)
    for fp, attempts in verifies.items():
        templates = enrolls.get(fp, [])
        sides = {t.loc for t in templates}
        if len(templates) < 2 or len(sides) != 1:
            data.not_replayable += attempts
            continue
        data.groups.append(Group(fp, templates[0].owner or attempts[0].owner, templates[0].loc, templates, attempts))
    data.groups.sort(key=lambda g: (g.owner, g.templates[0].id))
    return data


def score_group(g: Group, weights, band: float = M.DEFAULT.band, dw: float = M.DEFAULT.duration_weight) -> list[Scored]:
    feats = {r.id: M.features(r.rows, weights) for r in g.templates + g.attempts}

    def dist(a: M.Logged, b: M.Logged) -> float:  # Swift order: distance(sig, template)
        return M.dtw(feats[a.id], feats[b.id], band) * M.duration_factor(a.dur, b.dur, dw)

    ts = g.templates
    worst = max(dist(ts[i], ts[j]) for i in range(len(ts)) for j in range(i + 1, len(ts)))
    worst = max(worst, 1e-9)
    out = []
    for a in g.attempts:
        score = min(dist(a, t) for t in ts)
        gate1 = a.rejection in GATE1_REJECTIONS or a.loc != g.side
        out.append(Scored(a, math.inf if gate1 else score / worst, score))
    return out


def score_all(data: Data, setting: Setting) -> list[Scored]:
    return [s for g in data.groups for s in score_group(g, setting.weights)]


# ---------- statistics ----------

def upper95(k: int, n: int) -> float:
    """One-sided 95% upper bound on a rate: the rule of three (3/n) when k = 0, exact Clopper-Pearson otherwise."""
    if n == 0:
        return math.nan
    if k == 0:
        return min(1.0, 3 / n)
    if k >= n:
        return 1.0

    def cdf(p: float) -> float:
        return sum(math.comb(n, i) * p ** i * (1 - p) ** (n - i) for i in range(k + 1))

    lo, hi = k / n, 1.0
    for _ in range(60):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if cdf(mid) > 0.05 else (lo, mid)
    return hi


def exact_zero_bound(n: int) -> float:
    return 1 - 0.05 ** (1 / n) if n else math.nan


def eer(owner: list[float], imitator: list[float]) -> tuple[float, float]:
    """Equal error rate and the factor where false accepts ≈ false rejects."""
    o = [x for x in owner]
    f = [x for x in imitator if math.isfinite(x)]
    if not o or not imitator:
        return math.nan, math.nan
    best = (math.inf, math.nan, math.nan)
    cands = sorted({0.0, *[x for x in o if math.isfinite(x)], *f})
    for t in cands + [cands[-1] * 1.001 + 1e-9]:
        frr = sum(x > t for x in o) / len(o)
        far = sum(x <= t for x in imitator) / len(imitator)
        gap = abs(far - frr)
        if gap < best[0]:
            best = (gap, (far + frr) / 2, t)
    return best[1], best[2]


@dataclass
class Rate:
    k: int
    n: int

    @property
    def rate(self) -> float:
        return self.k / self.n if self.n else math.nan

    def __str__(self) -> str:
        return f"{self.k}/{self.n} ({self.rate:.0%})" if self.n else "–"


def accept(scored: list[Scored], factor: float, pred) -> Rate:
    sel = [s for s in scored if pred(s.rec)]
    return Rate(sum(s.ratio <= factor for s in sel), len(sel))


def owner_cells(scored: list[Scored]) -> list[tuple[str, str]]:
    return sorted({(s.rec.owner, s.rec.session) for s in scored if s.rec.scenario == OWNER},
                  key=lambda c: (c[0], SESSIONS.index(c[1]) if c[1] in SESSIONS else 99, c[1]))


@dataclass
class Choice:
    setting: Setting
    scored: list[Scored]
    factor: float
    feasible: bool  # every owner/session >= OWNER_MIN
    sweep: list[dict]
    eer: float
    eer_factor: float


def sweep_row(scored: list[Scored], f: float) -> dict:
    cells = owner_cells(scored)
    per = {c: accept(scored, f, lambda r, c=c: r.scenario == OWNER and (r.owner, r.session) == c) for c in cells}
    imit = accept(scored, f, lambda r: r.scenario in IMITATION)
    return {
        "factor": f,
        "owner_cells": per,
        "owner_min": min((r.rate for r in per.values()), default=math.nan),
        "owner": accept(scored, f, lambda r: r.scenario == OWNER),
        "imitators": imit,
        **{sc: accept(scored, f, lambda r, sc=sc: r.scenario == sc) for sc in IMITATION + GATE1},
    }


def choose(setting: Setting, scored: list[Scored]) -> Choice:
    """Most secure factor that keeps every owner/session at >= OWNER_MIN."""
    sweep = [sweep_row(scored, f) for f in FACTORS]
    ok = [r for r in sweep if r["owner_min"] >= OWNER_MIN - 1e-9]
    if ok:
        best = min(ok, key=lambda r: (r["imitators"].k, -r["owner"].k, r["factor"]))
    else:  # nothing reaches the target: keep owners as high as possible
        best = max(sweep, key=lambda r: (_nz(r["owner_min"]), -r["imitators"].k, -r["factor"]))
    owner = [s.ratio for s in scored if s.rec.scenario == OWNER]
    imit = [s.ratio for s in scored if s.rec.scenario in IMITATION]
    e, ef = eer(owner, imit)
    return Choice(setting, scored, best["factor"], bool(ok), sweep, e, ef)


def _nz(x: float) -> float:
    return -1.0 if math.isnan(x) else x


def pick(choices: list[Choice]) -> Choice:
    """Feasible first, then fewer imitators accepted, more owners, then today's code."""
    def key(c: Choice):
        row = next(r for r in c.sweep if r["factor"] == c.factor)
        return (not c.feasible, row["imitators"].k, -row["owner"].k, -_nz(row["owner_min"]), choices.index(c))
    return min(choices, key=key)


def app_match(data: Data) -> dict[str, float]:
    """Median relative gap between the app's logged score and the Python replay, per setting."""
    out = {}
    for setting in SETTINGS:
        gaps = []
        for s in score_all(data, setting):
            if s.rec.score is not None and s.rec.score > 0 and math.isfinite(s.score):
                gaps.append(abs(s.score - s.rec.score) / s.rec.score)
        gaps.sort()
        out[setting.name] = gaps[len(gaps) // 2] if gaps else math.nan
    return out


# ---------- report ----------

def pct(x: float) -> str:
    return "–" if math.isnan(x) else f"{x:.0%}" if x >= 0.1 or x == 0 else f"{x:.1%}"


def row_at(c: Choice, f: float) -> dict:
    return next(r for r in c.sweep if r["factor"] == f)


def report(records: list[M.Logged], data: Data, choices: list[Choice], best: Choice, charts: dict[str, str],
           match: dict[str, float]) -> str:
    verifies = [r for r in records if r.mode == "verify" and r.rejection != "deviceUnknown"]
    owners = sorted({g.owner for g in data.groups})
    L = [
        "# AirSign evaluation",
        "",
        f"Generated by `tools/tuning/tune.py --test-logs` on {datetime.now():%Y-%m-%d %H:%M} from the test-mode records of "
        "[docs/test-protocol.md](test-protocol.md). The recordings stay off the repo.",
        "",
        "Every verify attempt is replayed against its own enrollment's 3 templates with the app's matcher (banded DTW, "
        "band 0.25, durationWeight 0.5), so thresholdFactor and `FeatureScale.rotation` can be changed after the fact. "
        f"An owner/session passes when at least {OWNER_MIN:.0%} of its A1 attempts are accepted.",
        "",
        "## Data",
        "",
        "| Owner | Bud | Enrollments | " + " | ".join(SCENARIOS) + " |",
        "|---|---|---|" + "---|" * len(SCENARIOS),
    ]
    for o in owners:
        gs = [g for g in data.groups if g.owner == o]
        counts = [sum(a.scenario == sc for g in gs for a in g.attempts) for sc in SCENARIOS]
        L.append(f"| {o} | {'/'.join(sorted({g.side for g in gs}))} | {len(gs)} | " + " | ".join(map(str, counts)) + " |")
    L += ["", f"- Left out: {data.dropped_device_unknown} attempts the app didn't count (sound output wasn't the AirPods), "
              f"{len(data.not_replayable)} whose enrollment wasn't logged, {data.unknown_scenario} with an unknown scenario."]
    gap = match.get(SETTINGS[0].name, math.nan)
    gap15 = match.get(SETTINGS[1].name, math.nan)
    L += [f"- Check: the Python replay matches the app's logged scores to a median {pct(gap)} at rotation 3 "
          f"and {pct(gap15)} at rotation 1.5, so the app build that recorded them used "
          f"{'rotation 3' if _nz(gap) <= _nz(gap15) else 'rotation 1.5'}.", ""]

    br = row_at(best, best.factor)
    L += ["## Recommendation", ""]
    if best.feasible:
        L.append(f"**{best.setting.name}, thresholdFactor {best.factor:g}.** Every owner/session stays at ≥ {OWNER_MIN:.0%}, "
                 f"and imitators (A2–A4 together) were accepted {br['imitators']}.")
    else:
        L.append(f"**No setting keeps every owner/session at ≥ {OWNER_MIN:.0%}.** The closest is {best.setting.name} at "
                 f"thresholdFactor {best.factor:g}, where the weakest owner/session gets in {pct(br['owner_min'])}.")
    if best.factor > CURRENT_FACTOR:
        L.append(f"The factor is above {CURRENT_FACTOR:g}; the demo threshold override can only tighten, so the default "
                 "must change in code.")
    elif best.factor < CURRENT_FACTOR:
        L.append(f"The factor is below {CURRENT_FACTOR:g}, so the demo threshold override could reach it, "
                 "but changing the default is cleaner.")
    if best.setting is not SETTINGS[0]:
        L.append("Changing `FeatureScale.rotation` is a code change in `Signature.swift` (role A).")
    L.append("")

    L += ["## Rotation 3 vs 1.5", "",
          "| Setting | Chosen factor | Weakest owner/session | Owner (all) | A2 zero-effort | A3 watched once | A4 skilled "
          "| A5 other bud/pair | EER (at factor) |",
          "|---|---|---|---|---|---|---|---|---|"]
    for c in choices:
        r = row_at(c, c.factor)
        a5 = Rate(r["A5-other-bud"].k + r["A5-other-pair"].k, r["A5-other-bud"].n + r["A5-other-pair"].n)
        flag = "" if c.feasible else " (target missed)"
        L.append(f"| {c.setting.name} | {c.factor:g}{flag} | {pct(r['owner_min'])} | {r['owner']} | {r['A2-zero-effort']} "
                 f"| {r['A3-watched-once']} | {r['A4-skilled']} | {a5} | {pct(c.eer)} ({c.eer_factor:.2f}) |")
    cur = row_at(choices[0], CURRENT_FACTOR)
    L += ["", f"For reference, today's app (rotation 3, factor {CURRENT_FACTOR:g}): weakest owner/session "
              f"{pct(cur['owner_min'])}, owner {cur['owner']}, imitators {cur['imitators']}.", ""]

    L += [f"## Acceptance by scenario ({best.setting.name}, factor {best.factor:g})", "",
          "| Scenario | Accepted | 95% upper bound |", "|---|---|---|"]
    for sc in SCENARIOS:
        r = br[sc] if sc != OWNER else br["owner"]
        note = "" if r.n == 0 else (f"{pct(upper95(r.k, r.n))} (rule of three; exact {pct(exact_zero_bound(r.n))})"
                                    if r.k == 0 else f"{pct(upper95(r.k, r.n))} (Clopper-Pearson)")
        L.append(f"| {sc} | {r} | {note if sc != OWNER else '–'} |")
    L += ["", "Owner by session:", "", "| Owner | " + " | ".join(SESSIONS) + " |", "|---|" + "---|" * len(SESSIONS)]
    for o in owners:
        cells = [br["owner_cells"].get((o, s)) for s in SESSIONS]
        L.append(f"| {o} | " + " | ".join(str(c) if c else "–" for c in cells) + " |")
    L.append("")

    L += ["## Quotable", ""]
    for sc in IMITATION:
        r = br[sc]
        if r.n and r.k == 0:
            L.append(f"- {sc}: 0 of {r.n} imitations accepted, so with 95% confidence the success rate is below "
                     f"{pct(3 / r.n)} (rule of three).")
        elif r.n:
            L.append(f"- {sc}: {r.k} of {r.n} imitations accepted ({pct(r.rate)}); 95% upper bound {pct(upper95(r.k, r.n))}.")
    a5n = br["A5-other-bud"].n + br["A5-other-pair"].n
    if a5n:
        L.append(f"- Gate 1: {br['A5-other-bud'].k + br['A5-other-pair'].k} of {a5n} owner attempts with the wrong AirPod "
                 "or the wrong AirPods accepted.")
    L.append(f"- Equal error rate (owner A1 vs imitators A2–A4): {pct(best.eer)}, at thresholdFactor {best.eer_factor:.2f}.")
    L.append("")

    L += ["## Charts", "", f"![Scores by scenario]({charts['scores']})", "",
          "Each dot is one attempt: its score divided by the worst distance between that enrollment's own templates. "
          "An attempt is accepted when its dot is left of the threshold line.", "",
          f"![Acceptance vs thresholdFactor]({charts['sweep']})", ""]

    L += [f"## Threshold sweep ({best.setting.name})", "",
          "| thresholdFactor | Weakest owner/session | Owner | A2 | A3 | A4 |", "|---|---|---|---|---|---|"]
    for r in best.sweep:
        L.append(f"| {r['factor']:g} | {pct(r['owner_min'])} | {r['owner']} | {r['A2-zero-effort']} "
                 f"| {r['A3-watched-once']} | {r['A4-skilled']} |")
    L += ["", "## Caveats", "",
          "- The factor is fitted to these attempts, so the true rates will be a little worse. The 95% bounds show how "
          "little a small sample can prove.",
          "- A4 imitators saw the score and gate lights in the test lab, which is more than a real attacker gets.",
          "- Gate 1 rejections (A5) come from the app's record: the Python replay can't see the AirPods' device ID.",
          f"- Logged verify attempts in total: {len(verifies)}.", ""]
    return "\n".join(L)


def run(dirs: list[Path], report_path: Path) -> None:
    records = M.load_logs(dirs)
    data = build(records)
    n = sum(len(g.attempts) for g in data.groups)
    print(f"[tuning] {len(records)} records, {len(data.groups)} enrollments, {n} replayable attempts", file=sys.stderr)
    if not data.groups:
        sys.exit("[tuning] nothing to replay: need enroll records and verify records with the same enrollment")
    choices = []
    for setting in SETTINGS:
        choices.append(choose(setting, score_all(data, setting)))
        print(f"[tuning] {setting.name}: factor {choices[-1].factor:g}", file=sys.stderr)
    best = pick(choices)
    chart_dir = report_path.parent / "evaluation"
    chart_dir.mkdir(parents=True, exist_ok=True)
    charts = {"scores": "evaluation/scores.svg", "sweep": "evaluation/acceptance.svg"}
    draw_scores(best, chart_dir / "scores.svg")
    draw_sweep(best, chart_dir / "acceptance.svg")
    report_path.write_text(report(records, data, choices, best, charts, app_match(data)), encoding="utf-8")
    print(f"[tuning] wrote {report_path} and {chart_dir}", file=sys.stderr)


# ---------- charts ----------

LABELS = {OWNER: "A1 owner", "A2-zero-effort": "A2 zero-effort", "A3-watched-once": "A3 watched once",
          "A4-skilled": "A4 skilled"}


def draw_scores(c: Choice, path: Path) -> None:
    rows = []
    for sc in [OWNER, *IMITATION]:
        vals = [s.ratio for s in c.scored if s.rec.scenario == sc]
        rows.append(svgchart.StripRow(LABELS[sc], vals, "owner" if sc == OWNER else "imitator"))
    marks = [svgchart.Mark(c.factor, f"chosen {c.factor:g}")]
    if c.factor != CURRENT_FACTOR:
        marks.append(svgchart.Mark(CURRENT_FACTOR, f"today {CURRENT_FACTOR:g}", dashed=True))
    svgchart.strip_plot(path, f"Score ÷ worst template pair, by scenario ({c.setting.name})", rows, marks)


def draw_sweep(c: Choice, path: Path) -> None:
    xs = [r["factor"] for r in c.sweep]
    series = [svgchart.Series("Owner (weakest)", [r["owner_min"] for r in c.sweep])]
    for sc in IMITATION:
        series.append(svgchart.Series(LABELS[sc], [r[sc].rate for r in c.sweep]))
    svgchart.line_chart(path, f"Acceptance vs thresholdFactor ({c.setting.name})", xs, series,
                        hline=(OWNER_MIN, f"owner target {OWNER_MIN:.0%}"), vline=(c.factor, f"chosen {c.factor:g}"))
