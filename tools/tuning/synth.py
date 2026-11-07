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


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", type=Path)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    make_round(args.out, np.random.default_rng(args.seed))
    print(f"wrote fake attempts to {args.out}")


if __name__ == "__main__":
    main()
