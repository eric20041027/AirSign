"""Reference implementations of the bake-off challengers, pure Python, written for a quick look at the spike data.

Pre-registered challengers: gyro_x2, normalized_nfm, dtw_plus_global (see docs/algorithm-bakeoff.md).
AUC alone is misleading here: always test with the real threshold rule. Usage:
    python3 -I quick_candidates.py <folder with spike attempt-*.json>
"""
import cmath
import glob
import json
import math
import os
import sys

SESSIONS = sys.argv[1]
ROUNDS = {
    "round1": (["143432-081", "143437-789", "143444-477"], "143445", "144241"),
    "round2": (["144527-280", "144533-012", "144616-034"], "144617", "145000"),
}


def load():
    out = {}
    for path in glob.glob(os.path.join(SESSIONS, "attempt-*.json")):
        d = json.load(open(path))
        d["id"] = os.path.basename(path)[17:27]
        out[d["id"]] = d
    return out


def feats(rows, rot_scale=3.0):
    return [[r[5] / rot_scale, r[6] / rot_scale, r[7] / rot_scale, r[8] / 0.5, r[9] / 0.5, r[10] / 0.5, r[11], r[12], r[13]] for r in rows]


def diff(f):
    return [[b - a for a, b in zip(f[i], f[i + 1])] for i in range(len(f) - 1)] or f


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
            for k in range(len(ai)):
                d = ai[k] - bj[k]
                s += d * d
            cur[j] = math.sqrt(s) + min(prev[j], cur[j - 1], prev[j - 1])
        prev = cur
    return prev[m] / (n + m)


def dur_factor(da, db, w=0.5):
    return 1 + w * abs(math.log(max(da, 1e-3) / max(db, 1e-3)))


def global_vec(rows):
    """Duration, RMS of the 9 channels, gyro path length, mean |jerk|, gyro-speed peaks, 8-12 Hz band share."""
    f = feats(rows)
    n = len(f)
    dur = rows[-1][0] - rows[0][0]
    rms = [math.sqrt(sum(x[k] ** 2 for x in f) / n) for k in range(9)]
    speed = [math.sqrt(r[5] ** 2 + r[6] ** 2 + r[7] ** 2) for r in rows]
    path = sum(speed) * (dur / max(n - 1, 1))
    jerk = sum(math.sqrt(sum((rows[i + 1][k] - rows[i][k]) ** 2 for k in (8, 9, 10))) for i in range(n - 1)) / max(n - 1, 1)
    peaks = sum(1 for i in range(1, n - 1) if speed[i] > speed[i - 1] and speed[i] > speed[i + 1] and speed[i] > 1.0)
    return [dur] + rms + [path, jerk, peaks, tremor_share(rows)]


def tremor_share(rows):
    """Share of gyro-speed spectral energy in 8-12 Hz (naive DFT; rate from timestamps)."""
    n = len(rows)
    rate = (n - 1) / max(rows[-1][0] - rows[0][0], 1e-3)
    speed = [math.sqrt(r[5] ** 2 + r[6] ** 2 + r[7] ** 2) for r in rows]
    mean = sum(speed) / n
    x = [s - mean for s in speed]
    total = band = 0.0
    for k in range(1, n // 2):
        f = k * rate / n
        p = abs(sum(x[t] * cmath.exp(-2j * math.pi * k * t / n) for t in range(n))) ** 2
        total += p
        if 8 <= f <= 12:
            band += p
    return band / total if total else 0.0


def std_distance(v, refs):
    k = len(v)
    out = 0.0
    for i in range(k):
        vals = [r[i] for r in refs]
        mu = sum(vals) / len(vals)
        sd = math.sqrt(sum((x - mu) ** 2 for x in vals) / len(vals))
        sd = max(sd, 0.1 * abs(mu), 1e-3)
        out += ((v[i] - mu) / sd) ** 2
    return math.sqrt(out / k)


def auc(owner, fake):
    wins = sum((f > o) + 0.5 * (f == o) for f in fake for o in owner)
    return wins / (len(owner) * len(fake))


def evaluate(data, tids, lo, hi):
    T = [data[t] for t in tids]
    side = T[0]["loc"]
    V = [d for d in data.values() if d["mode"] == "verify" and lo <= d["id"] <= hi and d["dur"] > 1.2
         and (d["who"] == "genuine" or d["loc"] == side)]
    tf = {"base": [feats(t["rows"]) for t in T], "g2": [feats(t["rows"], 1.5) for t in T]}
    tf["deriv"] = [diff(f) for f in tf["base"]]
    tdur = [t["dur"] for t in T]
    tglob = [global_vec(t["rows"]) for t in T]

    def pair(kind, i, j):
        return dtw(tf[kind][i], tf[kind][j]) * (dur_factor(tdur[i], tdur[j]) if kind != "deriv" else 1)

    enrolled = {k: [[pair(k, i, j) if i != j else 0 for j in range(3)] for i in range(3)] for k in ("base", "g2", "deriv")}
    worst = {k: max(enrolled[k][i][j] for i in range(3) for j in range(3)) for k in enrolled}
    loo_glob = sum(std_distance(tglob[i], [tglob[j] for j in range(3) if j != i]) for i in range(3)) / 3

    # Kholmatov-style references: average nearest, farthest, medoid distances among templates
    base_e = enrolled["base"]
    near = sum(min(base_e[i][j] for j in range(3) if j != i) for i in range(3)) / 3
    far = sum(max(base_e[i][j] for j in range(3) if j != i) for i in range(3)) / 3
    medoid = min(range(3), key=lambda i: sum(base_e[i]))
    med_ref = sum(base_e[medoid][j] for j in range(3) if j != medoid) / 2

    rows = {name: {"genuine": [], "forgery": []} for name in
            ["baseline", "gyro_x2", "mean_templates", "normalized_nfm", "derivative_fusion", "global_features",
             "dtw_plus_global", "tremor_only"]}
    for v in V:
        f = feats(v["rows"])
        d = [dtw(f, tf["base"][i]) * dur_factor(v["dur"], tdur[i]) for i in range(3)]
        g2 = [dtw(feats(v["rows"], 1.5), tf["g2"][i]) * dur_factor(v["dur"], tdur[i]) for i in range(3)]
        dv = [dtw(diff(f), tf["deriv"][i]) for i in range(3)]
        gv = std_distance(global_vec(v["rows"]), tglob)
        who = v["who"]
        rows["baseline"][who].append(min(d))
        rows["gyro_x2"][who].append(min(g2))
        rows["mean_templates"][who].append(sum(d) / 3)
        rows["normalized_nfm"][who].append(min(d) / max(near, 1e-3) + max(d) / max(far, 1e-3) + d[medoid] / max(med_ref, 1e-3))
        rows["derivative_fusion"][who].append(min(d) / worst["base"] + min(dv) / worst["deriv"])
        rows["global_features"][who].append(gv)
        rows["dtw_plus_global"][who].append(min(d) / worst["base"] + gv / max(loo_glob, 1e-3))
        tr = tremor_share(v["rows"])
        rows["tremor_only"][who].append(abs(tr - sum(t[-1] for t in tglob) / 3))
    return rows, len([v for v in V if v["who"] == "genuine"]), len([v for v in V if v["who"] == "forgery"])


data = load()
print(f"{'algorithm':20s} " + " ".join(f"{r:>14s}" for r in ROUNDS))
results = {r: evaluate(data, *ROUNDS[r]) for r in ROUNDS}
for name in results["round1"][0]:
    cells = []
    for r in ROUNDS:
        scores, _, _ = results[r]
        cells.append(f"AUC {auc(scores[name]['genuine'], scores[name]['forgery']):.3f}")
    print(f"{name:20s} " + " ".join(f"{c:>14s}" for c in cells))
for r in ROUNDS:
    print(f"{r}: owner {results[r][1]} attempts, same-bud imitator {results[r][2]} attempts")
