"""AirSign matcher in Python, for tuning.

Mirrors plan Task 3 and the spike's web/index.html so the tuned numbers carry
over to the Swift matcher unchanged:

- features per sample: [rot/3, acc/0.5, grav] (9 columns)
- banded DTW: band half-width ceil(band * max(n, m)) around round(i*m/n),
  frame cost = Euclidean distance, result = total cost / (n + m)
- distance = dtw * (1 + durationWeight * |ln(durA / durB)|)
- score = minimum distance to the enrolled templates
- threshold = thresholdFactor * largest pairwise template distance

Standard library + numpy only.
"""
from __future__ import annotations

import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

# Column order of each saved row (spike saveAttempt).
COLUMNS = "t,qx,qy,qz,qw,rot_x,rot_y,rot_z,acc_x,acc_y,acc_z,grav_x,grav_y,grav_z"
N_COLS = 14
ROT, ACC, GRAV = slice(5, 8), slice(8, 11), slice(11, 14)
ROT_SCALE = 3.0  # rad/s
ACC_SCALE = 0.5  # g
ENROLL_COUNT = 3

STAMP = re.compile(r"attempt-(\d{8}-\d{6}-\d{3})")


@dataclass(frozen=True)
class Params:
    band: float = 0.25
    duration_weight: float = 0.5
    threshold_factor: float = 1.25
    weights: tuple[float, float, float] = (1.0, 1.0, 1.0)  # gyro, acc, grav


DEFAULT = Params()


@dataclass
class Attempt:
    id: str  # timestamp from the file name, e.g. 20261107-144527-280
    mode: str  # "enroll" or "verify"
    who: str  # "genuine" (owner) or "forgery" (imitator)
    loc: str  # "left" or "right" bud
    rows: np.ndarray  # shape (n, 14), spike column order

    @property
    def dur(self) -> float:
        return float(self.rows[-1, 0] - self.rows[0, 0])


@dataclass
class Session:
    name: str
    templates: list[Attempt]
    attempts: list[Attempt]
    skipped: dict[str, int] = field(default_factory=dict)

    @property
    def side(self) -> str:
        return self.templates[0].loc


# ---------- loading ----------

def load_attempt(path: Path) -> Attempt:
    """Load one attempt-*.json. Raises ValueError on anything unexpected."""
    m = STAMP.search(path.name)
    if not m:
        raise ValueError("file name is not attempt-YYYYMMDD-HHMMSS-mmm.json")
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("not a JSON object")
    cols = data.get("columns", COLUMNS)
    if cols != COLUMNS:
        raise ValueError(f"unexpected columns: {cols!r}")
    mode, who, loc = data.get("mode"), data.get("who"), data.get("loc")
    if mode not in ("enroll", "verify"):
        raise ValueError(f"bad mode {mode!r}")
    if who not in ("genuine", "forgery"):
        raise ValueError(f"bad who {who!r}")
    if not isinstance(loc, str):
        raise ValueError(f"bad loc {loc!r}")
    rows = np.asarray(data.get("rows"), dtype=float)
    if rows.ndim != 2 or rows.shape[1] != N_COLS or len(rows) < 2:
        raise ValueError(f"rows must be (n>=2, {N_COLS}), got {rows.shape}")
    if not np.isfinite(rows).all():
        raise ValueError("rows contain NaN or infinity")
    return Attempt(id=m.group(1), mode=mode, who=who, loc=loc, rows=rows)


def load_dir(directory: Path) -> list[Attempt]:
    out = []
    for path in sorted(Path(directory).glob("attempt-*.json")):
        try:
            out.append(load_attempt(path))
        except (ValueError, json.JSONDecodeError) as err:
            print(f"[tuning] skip {path.name}: {err}", file=sys.stderr)
    out.sort(key=lambda a: a.id)
    return out


def _in_range(stamp: str, lo: str | None, hi: str | None) -> bool:
    """Compare stamps as prefixes, so '20261107-1450' includes 20261107-145000-123."""
    if lo and stamp[: len(lo)] < lo:
        return False
    if hi and stamp[: len(hi)] > hi:
        return False
    return True


def _filter(name: str, templates: list[Attempt], verifies: list[Attempt], min_dur: float) -> Session | None:
    if len(templates) < 2:
        print(f"[tuning] {name}: needs at least 2 templates, has {len(templates)}", file=sys.stderr)
        return None
    if len({t.loc for t in templates}) > 1:
        print(f"[tuning] {name}: templates mix left and right buds, skipped", file=sys.stderr)
        return None
    side = templates[0].loc
    skipped = {"other bud": 0, "too short": 0}
    kept = []
    for a in verifies:
        if a.loc != side:
            skipped["other bud"] += 1
        elif a.dur <= min_dur:
            skipped["too short"] += 1
        else:
            kept.append(a)
    return Session(name=name, templates=templates, attempts=kept, skipped=skipped)


def auto_sessions(attempts: list[Attempt], min_dur: float = 1.2) -> list[Session]:
    """Split a time-sorted list into sessions: a run of enrolls, then the verifies after it.

    Templates are the last ENROLL_COUNT enrolls of each run.
    """
    sessions, enrolls, verifies = [], [], []

    def close():
        if enrolls and verifies:
            s = _filter(f"session {len(sessions) + 1}", enrolls[-ENROLL_COUNT:], verifies, min_dur)
            if s:
                sessions.append(s)

    for a in attempts:
        if a.mode == "enroll":
            if verifies:
                close()
                enrolls, verifies = [], []
            enrolls.append(a)
        elif enrolls:
            verifies.append(a)
    close()
    return sessions


def manual_session(attempts: list[Attempt], template_ids: list[str], lo: str | None, hi: str | None,
                   min_dur: float = 1.2) -> Session | None:
    by_id = {a.id: a for a in attempts}
    templates = []
    for tid in template_ids:
        match = [a for i, a in by_id.items() if i.startswith(tid)]
        if len(match) != 1:
            raise ValueError(f"template {tid!r} matches {len(match)} files")
        templates.append(match[0])
    tids = {t.id for t in templates}
    verifies = [a for a in attempts if a.mode == "verify" and a.id not in tids and _in_range(a.id, lo, hi)]
    return _filter("manual", templates, verifies, min_dur)


# ---------- matcher ----------

def features(rows: np.ndarray, weights: tuple[float, float, float] = (1.0, 1.0, 1.0)) -> np.ndarray:
    wr, wa, wg = weights
    return np.hstack([rows[:, ROT] * (wr / ROT_SCALE), rows[:, ACC] * (wa / ACC_SCALE), rows[:, GRAV] * wg])


def dtw(a: np.ndarray, b: np.ndarray, band: float = 0.25) -> float:
    """Banded DTW, same result as the spike's dtw().

    Each row's recurrence cur[j] = c[j] + min(prev[j], prev[j-1], cur[j-1]) is
    solved with a prefix-sum + running minimum so the inner loop runs in numpy.
    """
    n, m = len(a), len(b)
    if n == 0 or m == 0:
        return math.inf
    w = math.ceil(band * max(n, m))
    cost = np.sqrt(((a[:, None, :] - b[None, :, :]) ** 2).sum(axis=-1))
    prev = np.full(m + 1, np.inf)
    prev[0] = 0.0
    for i in range(1, n + 1):
        center = math.floor(i * m / n + 0.5)  # JS Math.round / Swift .rounded() for positives
        lo, hi = max(1, center - w), min(m, center + w)
        cur = np.full(m + 1, np.inf)
        if lo <= hi:
            c = cost[i - 1, lo - 1:hi]
            t = c + np.minimum(prev[lo:hi + 1], prev[lo - 1:hi])
            s = np.cumsum(c)
            cur[lo:hi + 1] = s + np.minimum.accumulate(t - s)
        prev = cur
    return float(prev[m] / (n + m))


def dtw_reference(a: np.ndarray, b: np.ndarray, band: float = 0.25) -> float:
    """Literal port of the spike's dtw(), slow. Used by the tests to check dtw()."""
    n, m = len(a), len(b)
    w = math.ceil(band * max(n, m))
    prev = [math.inf] * (m + 1)
    prev[0] = 0.0
    for i in range(1, n + 1):
        cur = [math.inf] * (m + 1)
        center = math.floor(i * m / n + 0.5)
        for j in range(max(1, center - w), min(m, center + w) + 1):
            d = math.sqrt(sum((x - y) ** 2 for x, y in zip(a[i - 1], b[j - 1])))
            cur[j] = d + min(prev[j], cur[j - 1], prev[j - 1])
        prev = cur
    return prev[m] / (n + m)


def duration_factor(dur_a: float, dur_b: float, weight: float) -> float:
    if dur_a <= 0 or dur_b <= 0:
        return math.inf
    return 1 + weight * abs(math.log(dur_a / dur_b))


def distance(a: Attempt, b: Attempt, p: Params = DEFAULT) -> float:
    d = dtw(features(a.rows, p.weights), features(b.rows, p.weights), p.band)
    return d * duration_factor(a.dur, b.dur, p.duration_weight)


# ---------- evaluation ----------

@dataclass
class Scores:
    """Scores divided by the session's worst template pair, so a factor f accepts ratio <= f."""
    owner: list[float]
    imitator: list[float]


def plain_dtw(session: Session, band: float, weights: tuple[float, float, float]) -> dict[tuple[str, str], float]:
    """DTW without the duration factor for every pair the matcher needs, in the Swift argument order."""
    feats = {a.id: features(a.rows, weights) for a in session.templates + session.attempts}
    table = {}
    ts = session.templates
    for i in range(len(ts)):
        for j in range(i + 1, len(ts)):
            table[ts[i].id, ts[j].id] = dtw(feats[ts[i].id], feats[ts[j].id], band)
    for a in session.attempts:
        for t in ts:
            table[a.id, t.id] = dtw(feats[a.id], feats[t.id], band)
    return table


def score_ratios(session: Session, table: dict[tuple[str, str], float], duration_weight: float) -> Scores:
    durs = {a.id: a.dur for a in session.templates + session.attempts}

    def dist(x: str, y: str) -> float:
        return table[x, y] * duration_factor(durs[x], durs[y], duration_weight)

    ts = session.templates
    worst = max(dist(ts[i].id, ts[j].id) for i in range(len(ts)) for j in range(i + 1, len(ts)))
    worst = max(worst, 1e-9)
    owner, imitator = [], []
    for a in session.attempts:
        ratio = min(dist(a.id, t.id) for t in ts) / worst
        (owner if a.who == "genuine" else imitator).append(ratio)
    return Scores(owner, imitator)


def auc(owner: list[float], imitator: list[float]) -> float:
    """Share of (imitator, owner) pairs where the imitator scores worse (higher). Ties count half."""
    if not owner or not imitator:
        return math.nan
    o = np.asarray(owner)[None, :]
    f = np.asarray(imitator)[:, None]
    return float(((f > o).sum() + 0.5 * (f == o).sum()) / (o.size * f.size))


def accepted(ratios: list[float], factor: float) -> int:
    return sum(1 for r in ratios if r <= factor)
