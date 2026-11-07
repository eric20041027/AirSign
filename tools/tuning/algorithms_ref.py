"""Reference versions of the frozen baseline and the three pre-registered challengers.

docs/algorithm-bakeoff.md puts the candidates in tools/tuning/algorithms.py (role B).
bakeoff.py uses that file when it has these names, and falls back to this one so
the analysis runs before it lands. The math follows quick_candidates.py (the
prototype reference), with numpy DTW from matcher.py for speed; a test checks
the two agree.

Interface (same as algorithms.py):
    score(attempt, templates) -> float      # smaller = more like the owner
    score.self_normalized = True            # optional: the score is already divided by the
                                            # templates' own spread, so threshold = factor
Otherwise threshold = factor × the largest score(t_i, [t_j]) over template pairs, as in the app.
"""
from __future__ import annotations

import math

import numpy as np

import matcher as M

_pairs: dict[tuple, float] = {}


def _dist(a: M.Attempt, b: M.Attempt, weights=(1.0, 1.0, 1.0)) -> float:
    """The app's distance: banded DTW × (1 + 0.5·|ln duration ratio|). Cached per pair."""
    key = (a.id, b.id, weights, id(a.rows), id(b.rows))
    if key not in _pairs:
        _pairs[key] = M.dtw(M.features(a.rows, weights), M.features(b.rows, weights), 0.25) * \
            M.duration_factor(max(a.dur, 1e-3), max(b.dur, 1e-3), 0.5)
    return _pairs[key]


def baseline(attempt: M.Attempt, templates: list[M.Attempt]) -> float:
    """The app today, frozen: minimum distance to the templates."""
    return min(_dist(attempt, t) for t in templates)


def gyro_x2(attempt: M.Attempt, templates: list[M.Attempt]) -> float:
    """FeatureScale.rotation 3 → 1.5: gyro weighted twice as much."""
    return min(_dist(attempt, t, (2.0, 1.0, 1.0)) for t in templates)


def _template_matrix(templates):
    n = len(templates)
    return [[_dist(templates[i], templates[j]) if i != j else 0.0 for j in range(n)] for i in range(n)]


def normalized_nfm(attempt: M.Attempt, templates: list[M.Attempt]) -> float:
    """Kholmatov & Yanikoglu: nearest, farthest and medoid distances, each over the templates' own average."""
    d = [_dist(attempt, t) for t in templates]
    e = _template_matrix(templates)
    n = len(templates)
    near = sum(min(e[i][j] for j in range(n) if j != i) for i in range(n)) / n
    far = sum(max(e[i][j] for j in range(n) if j != i) for i in range(n)) / n
    medoid = min(range(n), key=lambda i: sum(e[i]))
    med_ref = sum(e[medoid][j] for j in range(n) if j != medoid) / (n - 1)
    return min(d) / max(near, 1e-3) + max(d) / max(far, 1e-3) + d[medoid] / max(med_ref, 1e-3)


normalized_nfm.self_normalized = True


# ---------- global features (port of quick_candidates.global_vec) ----------

def tremor_share(rows: np.ndarray) -> float:
    """Share of gyro-speed spectral energy in 8–12 Hz; the sample rate comes from the timestamps."""
    n = len(rows)
    rate = (n - 1) / max(rows[-1, 0] - rows[0, 0], 1e-3)
    speed = np.linalg.norm(rows[:, 5:8], axis=1)
    x = speed - speed.mean()
    k = np.arange(1, n // 2)
    power = np.abs(np.fft.fft(x)[k]) ** 2
    total = power.sum()
    band = power[(k * rate / n >= 8) & (k * rate / n <= 12)].sum()
    return float(band / total) if total else 0.0


def global_vec(rows: np.ndarray) -> np.ndarray:
    """Duration, RMS of the 9 features, gyro path length, mean |Δacc|, gyro-speed peaks, 8–12 Hz share."""
    f = M.features(rows)
    n = len(f)
    dur = rows[-1, 0] - rows[0, 0]
    rms = np.sqrt((f ** 2).mean(axis=0))
    speed = np.linalg.norm(rows[:, 5:8], axis=1)
    path = speed.sum() * (dur / max(n - 1, 1))
    jerk = np.linalg.norm(np.diff(rows[:, 8:11], axis=0), axis=1).sum() / max(n - 1, 1)
    mid = speed[1:-1]
    peaks = int(((mid > speed[:-2]) & (mid > speed[2:]) & (mid > 1.0)).sum())
    return np.concatenate([[dur], rms, [path, jerk, peaks, tremor_share(rows)]])


def std_distance(v: np.ndarray, refs: list[np.ndarray]) -> float:
    r = np.asarray(refs)
    mu = r.mean(axis=0)
    sd = np.maximum.reduce([r.std(axis=0), 0.1 * np.abs(mu), np.full_like(mu, 1e-3)])
    return float(math.sqrt((((v - mu) / sd) ** 2).mean()))


_globals: dict[tuple, np.ndarray] = {}


def _gvec(a: M.Attempt) -> np.ndarray:
    key = (a.id, id(a.rows))
    if key not in _globals:
        _globals[key] = global_vec(a.rows)
    return _globals[key]


def dtw_plus_global(attempt: M.Attempt, templates: list[M.Attempt]) -> float:
    """baseline over the worst template pair, plus the global-feature distance over its leave-one-out spread."""
    e = _template_matrix(templates)
    n = len(templates)
    worst = max(e[i][j] for i in range(n) for j in range(n) if i != j)
    tg = [_gvec(t) for t in templates]
    loo = sum(std_distance(tg[i], [tg[j] for j in range(n) if j != i]) for i in range(n)) / n
    return baseline(attempt, templates) / max(worst, 1e-9) + std_distance(_gvec(attempt), tg) / max(loo, 1e-3)


dtw_plus_global.self_normalized = True

ALGORITHMS = {"baseline": baseline, "gyro_x2": gyro_x2, "normalized_nfm": normalized_nfm,
              "dtw_plus_global": dtw_plus_global}
