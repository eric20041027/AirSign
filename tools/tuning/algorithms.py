"""Bake-off challenger scorers for AirSign (protocol v2).

Each scorer has signature:
    score(attempt: matcher.Attempt, templates: list[matcher.Attempt]) -> float
where lower scores indicate a closer match to the enrolled owner templates.
"""

from __future__ import annotations

from typing import Callable, Sequence
import numpy as np

import matcher as M

Scorer = Callable[[M.Attempt, Sequence[M.Attempt]], float]

GYRO_X2_PARAMS = M.Params(weights=(2.0, 1.0, 1.0))


def baseline(attempt: M.Attempt, templates: Sequence[M.Attempt]) -> float:
    """Current production scorer: minimum DTW distance across templates."""
    return float(min(M.distance(attempt, t) for t in templates))


def gyro_x2(attempt: M.Attempt, templates: Sequence[M.Attempt]) -> float:
    """Double rotation weight relative to orientation and acceleration."""
    return float(min(M.distance(attempt, t, GYRO_X2_PARAMS) for t in templates))


def _pairwise_base(
    tf: list[np.ndarray], tdur: np.ndarray, p: M.Params = M.DEFAULT
) -> np.ndarray:
    """Pairwise baseline distances between enrolled templates (0 on diagonal)."""
    k = len(tf)
    base_e = np.zeros((k, k), dtype=float)
    for i in range(k):
        for j in range(k):
            if i != j:
                base_e[i, j] = M.dtw(tf[i], tf[j], p.band) * M.duration_factor(
                    float(tdur[i]), float(tdur[j]), p.duration_weight
                )
    return base_e


def normalized_nfm(attempt: M.Attempt, templates: Sequence[M.Attempt]) -> float:
    """Nearest + farthest + medoid template distances normalized by enrollment spread."""
    p = M.DEFAULT
    k = len(templates)
    tf = [M.features(t.rows, p.weights) for t in templates]
    tdur = np.array([t.dur for t in templates], dtype=float)

    f = M.features(attempt.rows, p.weights)
    d = np.array(
        [
            M.dtw(f, tf[i], p.band)
            * M.duration_factor(attempt.dur, float(tdur[i]), p.duration_weight)
            for i in range(k)
        ],
        dtype=float,
    )
    if float(d.min()) == 0.0:
        return 0.0

    base_e = _pairwise_base(tf, tdur, p)
    if k > 1:
        off_diag = ~np.eye(k, dtype=bool)
        row_other = np.where(off_diag, base_e, np.inf)
        near = float(row_other.min(axis=1).mean())
        row_other_max = np.where(off_diag, base_e, -np.inf)
        far = float(row_other_max.max(axis=1).mean())
        medoid = int(np.argmin(base_e.sum(axis=1)))
        med_ref = float(base_e[medoid].sum() / (k - 1))
    else:
        near = 0.0
        far = 0.0
        medoid = 0
        med_ref = 0.0

    return float(
        float(d.min()) / max(near, 1e-3)
        + float(d.max()) / max(far, 1e-3)
        + float(d[medoid]) / max(med_ref, 1e-3)
    )


def tremor_share(rows: np.ndarray) -> float:
    """Share of rotational-speed spectrum power in the 8-12 Hz physiological band."""
    n = len(rows)
    half = n // 2
    if half <= 1:
        return 0.0
    dur = float(rows[-1, 0] - rows[0, 0])
    rate = (n - 1) / max(dur, 1e-3)
    speed = np.sqrt((rows[:, M.ROT] ** 2).sum(axis=1))
    x = speed - speed.mean()

    spec = np.fft.rfft(x)[1:half]
    power = (spec.real ** 2) + (spec.imag ** 2)
    total = float(power.sum())
    if total == 0.0:
        return 0.0
    ks = np.arange(1, half, dtype=float)
    freqs = ks * rate / n
    band_mask = (freqs >= 8.0) & (freqs <= 12.0)
    band = float(power[band_mask].sum())
    return band / total


def global_vec(rows: np.ndarray) -> np.ndarray:
    """14-D summary vector: duration, 9-channel RMS, angular path, jerk, peaks, tremor."""
    f = M.features(rows)
    n = len(f)
    dur = float(rows[-1, 0] - rows[0, 0])
    rms = np.sqrt((f ** 2).mean(axis=0))
    speed = np.sqrt((rows[:, M.ROT] ** 2).sum(axis=1))
    path = float(speed.sum()) * (dur / max(n - 1, 1))
    if n >= 2:
        acc_diff = np.diff(rows[:, M.ACC], axis=0)
        jerk = float(np.sqrt((acc_diff ** 2).sum(axis=1)).sum()) / (n - 1)
    else:
        jerk = 0.0
    if n >= 3:
        peaks = float(
            (
                (speed[1:-1] > speed[:-2])
                & (speed[1:-1] > speed[2:])
                & (speed[1:-1] > 1.0)
            ).sum()
        )
    else:
        peaks = 0.0
    return np.concatenate(
        ([dur], rms, [path, jerk, peaks, tremor_share(rows)])
    ).astype(float)


def std_distance(v: np.ndarray, refs: Sequence[np.ndarray] | np.ndarray) -> float:
    """Standardized root-mean-square z-score distance from v to reference vectors."""
    ref_arr = np.asarray(refs, dtype=float)
    mu = ref_arr.mean(axis=0)
    sd = np.sqrt(((ref_arr - mu) ** 2).mean(axis=0))
    sd = np.maximum(np.maximum(sd, 0.1 * np.abs(mu)), 1e-3)
    return float(np.sqrt(np.mean(((v - mu) / sd) ** 2)))


def dtw_plus_global(attempt: M.Attempt, templates: Sequence[M.Attempt]) -> float:
    """Normalized nearest-DTW distance plus leave-one-out normalized global z-distance."""
    p = M.DEFAULT
    k = len(templates)
    tf = [M.features(t.rows, p.weights) for t in templates]
    tdur = np.array([t.dur for t in templates], dtype=float)

    f = M.features(attempt.rows, p.weights)
    d = np.array(
        [
            M.dtw(f, tf[i], p.band)
            * M.duration_factor(attempt.dur, float(tdur[i]), p.duration_weight)
            for i in range(k)
        ],
        dtype=float,
    )
    min_d = float(d.min())
    if min_d == 0.0:
        return 0.0

    base_e = _pairwise_base(tf, tdur, p)
    worst = max(float(base_e.max()), 1e-3)

    tglob = [global_vec(t.rows) for t in templates]
    if k > 1:
        loo_glob = float(
            np.mean(
                [
                    std_distance(tglob[i], [tglob[j] for j in range(k) if j != i])
                    for i in range(k)
                ]
            )
        )
    else:
        loo_glob = 0.0
    gv = std_distance(global_vec(attempt.rows), tglob)
    return float(min_d / worst + gv / max(loo_glob, 1e-3))


ALGORITHMS: dict[str, Scorer] = {
    "baseline": baseline,
    "gyro_x2": gyro_x2,
    "normalized_nfm": normalized_nfm,
    "dtw_plus_global": dtw_plus_global,
}
