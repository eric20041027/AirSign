"""Write fake attempt-*.json files in the spike's format, for tests and dry runs.

Usage: python synth.py OUT_DIR [--seed N]

The shapes match the Swift MatcherTests (ownerShape / forgeryShape). This is
not real signature data; never use it to pick the final numbers.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np

from matcher import COLUMNS


def owner_shape(u: np.ndarray) -> np.ndarray:
    return np.stack([3 * np.sin(4 * math.pi * u), 2 * np.cos(6 * math.pi * u) + 0.8, 1.5 * np.sin(2 * math.pi * u) + 1], 1)


def forgery_shape(u: np.ndarray) -> np.ndarray:
    return np.stack([3 * np.sin(4 * math.pi * u + 0.9), 2 * np.cos(4 * math.pi * u) + 0.8, 1.5 * np.sin(3 * math.pi * u) + 1], 1)


def rows_for(shape, n: int, noise: float, grav: tuple[float, float, float], rng: np.random.Generator) -> np.ndarray:
    u = np.arange(n) / n
    rot = shape(u) + rng.uniform(-noise, noise, (n, 3))
    acc = rot * 0.05
    g = np.tile(np.asarray(grav), (n, 1)) + rng.uniform(-0.02, 0.02, (n, 3))
    t = np.arange(n) * 0.02
    q = np.tile([0.0, 0.0, 0.0, 1.0], (n, 1))
    return np.hstack([t[:, None], q, rot, acc, g])


def write(out: Path, stamp: str, mode: str, who: str, loc: str, rows: np.ndarray) -> None:
    body = {
        "mode": mode, "who": who, "loc": loc, "dur": float(rows[-1, 0] - rows[0, 0]),
        "columns": COLUMNS, "rows": rows.round(6).tolist(),
    }
    (out / f"attempt-{stamp}.json").write_text(json.dumps(body), encoding="utf-8")


def make_round(out: Path, rng: np.random.Generator, day: str = "20991231", hour: int = 10,
               owners: int = 10, imitators: int = 15, other_bud: int = 2) -> None:
    """One enroll + verify round: 3 owner templates, then owner and imitator attempts."""
    out.mkdir(parents=True, exist_ok=True)
    owner_grav, fake_grav = (0.0, 0.7, -0.7), (0.1, 0.65, -0.72)
    k = 0

    def stamp() -> str:
        nonlocal k
        k += 1
        return f"{day}-{hour:02d}{k // 60:02d}{k % 60:02d}-{k:03d}"

    for _ in range(3):
        write(out, stamp(), "enroll", "genuine", "right", rows_for(owner_shape, int(rng.integers(105, 116)), 0.25, owner_grav, rng))
    for _ in range(owners):
        write(out, stamp(), "verify", "genuine", "right", rows_for(owner_shape, int(rng.integers(95, 130)), 0.3, owner_grav, rng))
    for i in range(imitators):
        # imitators get closer as they practice: blend the owner shape in
        mix = 0.3 + 0.5 * i / max(1, imitators - 1)
        shape = lambda u, mix=mix: mix * owner_shape(u) + (1 - mix) * forgery_shape(u)
        write(out, stamp(), "verify", "forgery", "right", rows_for(shape, int(rng.integers(90, 140)), 0.3, fake_grav, rng))
    for _ in range(other_bud):
        write(out, stamp(), "verify", "forgery", "left", rows_for(owner_shape, 110, 0.3, owner_grav, rng))


def b_shape(u: np.ndarray) -> np.ndarray:
    return np.stack([2.5 * np.cos(3 * math.pi * u), 2 * np.sin(5 * math.pi * u) - 0.5, 1.2 * np.cos(2 * math.pi * u)], 1)


def make_test_logs(out: Path, rng: np.random.Generator, owner_n: int = 20, imit_n: tuple[int, int] = (10, 10),
                   a4_n: tuple[int, int] = (15, 10), a5_n: int = 5, unknown_n: int = 2,
                   sessions=("S1-tonight", "S2-midnight", "S3-morning")) -> None:
    """Fake test-mode records like AttemptLog.swift writes, under test protocol v2, for two Macs (mac1: A, mac2: B).

    Owners enroll once, in S1, and every later attempt is logged against that enrollment.
    S1: A1, A2, A3, A4 (a4_n[0] per imitator), A5. S2: A1 only. S3: A1 and A4 (a4_n[1], blind).
    Later sessions drift the owner's grip a little. The logged score/threshold/accepted come from
    the Python matcher at today's settings, the way the app computes them.
    """
    from matcher import DEFAULT, Attempt, distance  # local: keep the module import light

    owners = [("mac1", "A", "right", owner_shape, (0.0, 0.7, -0.7), ["B", "C"]),
              ("mac2", "B", "left", b_shape, (0.2, 0.6, -0.75), ["A", "C"])]
    for mac, owner, side, shape, grav, imitators in owners:
        d = out / mac / "test-logs"
        d.mkdir(parents=True, exist_ok=True)
        k = 0

        def save(body: dict) -> None:
            nonlocal k
            k += 1
            stamp = f"20991231-{k // 3600:02d}{k // 60 % 60:02d}{k % 60:02d}-{k % 1000:03d}"
            (d / f"attempt-{stamp}.json").write_text(json.dumps(body), encoding="utf-8")

        def body(mode, tester, scenario, session, fp, loc, rows) -> dict:
            return {"mode": mode, "who": "genuine" if scenario == "A1-owner" else "forgery", "tester": tester,
                    "scenario": scenario, "session": session, "owner": owner, "enrollment": fp,
                    "savedAt": "2099-12-31T00:00:00Z", "dur": float(rows[-1, 0] - rows[0, 0]), "loc": loc,
                    "columns": COLUMNS, "rows": rows.round(6).tolist()}

        fp = "".join(rng.choice(list("0123456789abcdef"), 12))
        templates = [rows_for(shape, int(rng.integers(105, 116)), 0.25, grav, rng) for _ in range(3)]
        for rows in templates:
            save(body("enroll", owner, "A1-owner", sessions[0], fp, side, rows))
        tmpl = [Attempt("t", "enroll", "genuine", side, r) for r in templates]
        worst = max(distance(tmpl[i], tmpl[j]) for i in range(3) for j in range(i + 1, 3))
        threshold = DEFAULT.threshold_factor * worst
        other = forgery_shape if shape is owner_shape else owner_shape

        for si, session in enumerate(sessions):
            def verify(tester, scenario, rows, loc=side, gate1=None, session=session):
                b = body("verify", tester, scenario, session, fp, loc, rows)
                score = min(distance(Attempt("a", "verify", "x", loc, rows), t) for t in tmpl)
                rejection = gate1 or (None if score <= threshold else "scoreTooHigh")
                b.update(accepted=rejection is None, score=score, threshold=threshold, rejection=rejection,
                         lights={"grip": 0.5, "sizeTempo": 0.5, "rhythm": 0.5})
                save(b)

            drift = tuple(np.add(grav, (0.03 * si, -0.02 * si, 0.0)))
            for _ in range(owner_n):
                verify(owner, "A1-owner", rows_for(shape, int(rng.integers(100, 125)), 0.3, drift, rng))
            plan = []
            if si == 0:
                plan = [("A2-zero-effort", imit_n[0], (0.0, 0.0)), ("A3-watched-once", imit_n[1], (0.3, 0.5)),
                        ("A4-skilled", a4_n[0], (0.6, 0.9))]
            elif session.startswith("S3"):
                plan = [("A4-skilled", a4_n[1], (0.55, 0.85))]
            for imitator in imitators:
                for scenario, n, (lo, hi) in plan:
                    for _ in range(n):
                        mix = float(rng.uniform(lo, hi))
                        g = tuple(np.add(grav, (0.25 - mix * 0.28, -0.1 + mix * 0.08, 0.05)))
                        s = lambda u, mix=mix: mix * shape(u) + (1 - mix) * other(u)
                        verify(imitator, scenario, rows_for(s, int(rng.integers(95, 135)), 0.35, g, rng))
            if si == 0:
                other_side = "left" if side == "right" else "right"
                for _ in range(a5_n):
                    verify(owner, "A5-other-bud", rows_for(shape, 110, 0.3, grav, rng), loc=other_side, gate1="wrongBud")
                    verify(owner, "A5-other-pair", rows_for(shape, 110, 0.3, grav, rng), gate1="wrongDevice")
                for _ in range(unknown_n):
                    verify(owner, "A1-owner", rows_for(shape, 110, 0.3, grav, rng), gate1="deviceUnknown")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", type=Path)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--test-logs", action="store_true", help="write fake test-mode records (mac1/, mac2/) instead")
    args = ap.parse_args()
    rng = np.random.default_rng(args.seed)
    if args.test_logs:
        make_test_logs(args.out, rng)
    else:
        make_round(args.out, rng)
    print(f"wrote fake attempts to {args.out}")


if __name__ == "__main__":
    main()
