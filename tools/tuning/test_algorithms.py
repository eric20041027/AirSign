"""Unit tests for bake-off challenger algorithms (protocol v2)."""

from __future__ import annotations

import ast
import pathlib
import sys
import tempfile
import unittest
import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import algorithms as A  # noqa: E402
import matcher as M  # noqa: E402
import synth  # noqa: E402


def _load_quick_candidates_functions() -> dict[str, object]:
    """Load pure-Python reference functions from quick_candidates.py without running top-level CLI code."""
    qc_path = pathlib.Path(__file__).resolve().parent / "quick_candidates.py"
    tree = ast.parse(qc_path.read_text(encoding="utf-8"), filename=str(qc_path))
    safe_nodes = [
        node
        for node in tree.body
        if isinstance(node, (ast.Import, ast.ImportFrom, ast.FunctionDef))
    ]
    mod = ast.Module(body=safe_nodes, type_ignores=[])
    ns: dict[str, object] = {}
    exec(compile(mod, filename=str(qc_path), mode="exec"), ns)
    return ns


class AlgorithmsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.rng = np.random.default_rng(42)
        self.owner_grav = (0.0, 0.7, -0.7)
        self.fake_grav = (0.25, 0.55, -0.75)
        self.owner_templates = [
            M.Attempt(
                f"enroll-{i}",
                "enroll",
                "genuine",
                "right",
                synth.rows_for(
                    synth.owner_shape, 108 + 2 * i, 0.15, self.owner_grav, self.rng
                ),
            )
            for i in range(3)
        ]

    def test_registered_algorithms_exact_keys(self) -> None:
        self.assertEqual(
            set(A.ALGORITHMS.keys()),
            {"baseline", "gyro_x2", "normalized_nfm", "dtw_plus_global"},
        )

    def test_baseline_reproduces_matcher_exactly(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            synth.make_round(
                pathlib.Path(tmp),
                np.random.default_rng(7),
                owners=6,
                imitators=6,
                other_bud=0,
            )
            attempts = M.load_dir(pathlib.Path(tmp))
        templates = [a for a in attempts if a.mode == "enroll"]
        verifies = [a for a in attempts if a.mode == "verify"]
        for v in verifies:
            expected = min(M.distance(v, t) for t in templates)
            actual = A.ALGORITHMS["baseline"](v, templates)
            self.assertEqual(actual, expected)

    def test_identical_to_template_scores_near_zero(self) -> None:
        t0 = self.owner_templates[0]
        identical_copy = M.Attempt("copy", "verify", "genuine", t0.loc, t0.rows.copy())
        for name, scorer in A.ALGORITHMS.items():
            with self.subTest(algorithm=name, templates="distinct"):
                s = scorer(identical_copy, self.owner_templates)
                self.assertAlmostEqual(s, 0.0, places=6)
            with self.subTest(algorithm=name, templates="homogeneous"):
                s_hom = scorer(identical_copy, [t0, t0, t0])
                self.assertAlmostEqual(s_hom, 0.0, places=6)

    def test_different_synthetic_signature_scores_higher_than_near_copy(self) -> None:
        near_copy = M.Attempt(
            "near",
            "verify",
            "genuine",
            "right",
            synth.rows_for(synth.owner_shape, 110, 0.05, self.owner_grav, self.rng),
        )
        different = M.Attempt(
            "diff",
            "verify",
            "forgery",
            "right",
            synth.rows_for(synth.forgery_shape, 135, 0.25, self.fake_grav, self.rng),
        )
        for name, scorer in A.ALGORITHMS.items():
            with self.subTest(algorithm=name):
                s_near = scorer(near_copy, self.owner_templates)
                s_diff = scorer(different, self.owner_templates)
                self.assertLess(
                    s_near,
                    s_diff,
                    msg=f"{name}: near_copy ({s_near}) should score lower than forgery ({s_diff})",
                )

    def test_agrees_with_quick_candidates_reference_within_1e6(self) -> None:
        qc = _load_quick_candidates_functions()
        with tempfile.TemporaryDirectory() as tmp:
            synth.make_round(
                pathlib.Path(tmp),
                np.random.default_rng(123),
                owners=6,
                imitators=6,
                other_bud=0,
            )
            attempts = M.load_dir(pathlib.Path(tmp))
        templates = [a for a in attempts if a.mode == "enroll"]
        verifies = [a for a in attempts if a.mode == "verify"]

        # Build dict in the exact schema quick_candidates.evaluate expects
        data: dict[str, dict[str, object]] = {}
        tids: list[str] = []
        for t in templates:
            short_id = t.id[-10:]
            tids.append(short_id)
            data[short_id] = {
                "id": short_id,
                "mode": t.mode,
                "who": t.who,
                "loc": t.loc,
                "dur": t.dur,
                "rows": t.rows.tolist(),
            }

        for v in verifies:
            short_id = v.id[-10:]
            data[short_id] = {
                "id": short_id,
                "mode": v.mode,
                "who": v.who,
                "loc": v.loc,
                "dur": v.dur,
                "rows": v.rows.tolist(),
            }

        # Check helper functions directly on each attempt
        for a in attempts:
            rows_list = a.rows.tolist()
            ref_tremor = qc["tremor_share"](rows_list)  # type: ignore[index]
            np_tremor = A.tremor_share(a.rows)
            self.assertAlmostEqual(np_tremor, ref_tremor, delta=1e-6)

            ref_glob = qc["global_vec"](rows_list)  # type: ignore[index]
            np_glob = A.global_vec(a.rows)
            np.testing.assert_allclose(np_glob, ref_glob, rtol=0, atol=1e-6)

        # Evaluate reference scorers via quick_candidates.evaluate
        ref_rows, _, _ = qc["evaluate"](data, tids, "000000", "999999")  # type: ignore[index]

        side = templates[0].loc
        valid_verifies = [
            v
            for v in verifies
            if v.dur > 1.2 and (v.who == "genuine" or v.loc == side)
        ]
        genuine_v = [v for v in valid_verifies if v.who == "genuine"]
        forgery_v = [v for v in valid_verifies if v.who == "forgery"]

        for name, scorer in A.ALGORITHMS.items():
            with self.subTest(algorithm=name):
                np_genuine = [scorer(v, templates) for v in genuine_v]
                np_forgery = [scorer(v, templates) for v in forgery_v]
                np.testing.assert_allclose(
                    np_genuine, ref_rows[name]["genuine"], rtol=0, atol=1e-6
                )
                np.testing.assert_allclose(
                    np_forgery, ref_rows[name]["forgery"], rtol=0, atol=1e-6
                )


if __name__ == "__main__":
    unittest.main()
