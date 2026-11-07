"""Tests for the Python matcher. Run: python -m unittest discover -s tools/tuning"""
from __future__ import annotations

import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

import matcher as M  # noqa: E402
import synth  # noqa: E402
import tune  # noqa: E402


def attempt(shape, n=110, noise=0.0, side="right", mode="verify", who="genuine", id="x", seed=0):
    rng = np.random.default_rng(seed)
    return M.Attempt(id=id, mode=mode, who=who, loc=side, rows=synth.rows_for(shape, n, noise, (0, 0.7, -0.7), rng))


class DTWTests(unittest.TestCase):
    def test_identical_is_zero_and_stretch_is_small(self):
        a = M.features(attempt(synth.owner_shape).rows)
        stretched = M.features(attempt(synth.owner_shape, n=140).rows)
        other = M.features(attempt(synth.forgery_shape).rows)
        self.assertEqual(M.dtw(a, a), 0.0)
        self.assertLess(M.dtw(a, stretched), M.dtw(a, other) / 4)

    def test_matches_literal_spike_port(self):
        rng = np.random.default_rng(1)
        for n, m, band in [(30, 30, 0.25), (25, 40, 0.1), (40, 22, 0.4), (17, 33, 0.15), (5, 60, 0.1)]:
            a, b = rng.normal(size=(n, 9)), rng.normal(size=(m, 9))
            fast, slow = M.dtw(a, b, band), M.dtw_reference(a, b, band)
            if math.isinf(slow):
                self.assertTrue(math.isinf(fast))
            else:
                self.assertAlmostEqual(fast, slow, places=9)

    def test_disconnected_band_is_infinite(self):
        a, b = np.zeros((2, 9)), np.zeros((60, 9))
        self.assertTrue(math.isinf(M.dtw(a, b, 0.1)))
        self.assertTrue(math.isinf(M.dtw_reference(a, b, 0.1)))


class DistanceTests(unittest.TestCase):
    def test_duration_factor_scales_distance(self):
        a, b = attempt(synth.owner_shape, n=100), attempt(synth.owner_shape, n=200)
        plain = M.distance(a, b, M.Params(duration_weight=0))
        expected = plain * (1 + 0.5 * abs(math.log(a.dur / b.dur)))
        self.assertAlmostEqual(M.distance(a, b), expected, places=12)

    def test_weights_scale_feature_groups(self):
        rows = attempt(synth.owner_shape, n=10).rows
        f = M.features(rows, (2.0, 0.0, 1.0))
        np.testing.assert_allclose(f[:, 0:3], rows[:, 5:8] * 2 / 3)
        np.testing.assert_allclose(f[:, 3:6], 0)
        np.testing.assert_allclose(f[:, 6:9], rows[:, 11:14])

    def test_auc_counts_ties_half(self):
        self.assertEqual(M.auc([1, 2], [3, 4]), 1.0)
        self.assertEqual(M.auc([1, 2], [0, 0.5]), 0.0)
        self.assertEqual(M.auc([1], [1]), 0.5)


class LoadingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        synth.make_round(self.dir, np.random.default_rng(3), owners=4, imitators=5, other_bud=2)

    def tearDown(self):
        self.tmp.cleanup()

    def test_auto_session_uses_three_templates_and_drops_other_bud(self):
        attempts = M.load_dir(self.dir)
        [s] = M.auto_sessions(attempts)
        self.assertEqual(len(s.templates), 3)
        self.assertEqual(s.side, "right")
        self.assertEqual(s.skipped["other bud"], 2)
        self.assertEqual(sum(a.who == "genuine" for a in s.attempts), 4)
        self.assertEqual(sum(a.who == "forgery" for a in s.attempts), 5)

    def test_manual_session_by_prefix_and_range(self):
        attempts = M.load_dir(self.dir)
        ids = [a.id for a in attempts]
        s = M.manual_session(attempts, ids[:3], ids[3], ids[6])
        self.assertEqual([a.id for a in s.attempts], ids[3:7])

    def test_bad_files_are_skipped(self):
        (self.dir / "attempt-20991231-235959-999.json").write_text(json.dumps({"mode": "verify", "rows": [[1, 2]]}))
        (self.dir / "attempt-20991231-235959-998.json").write_text("not json")
        self.assertEqual(len(M.load_dir(self.dir)), 3 + 4 + 5 + 2)


class TuneTests(unittest.TestCase):
    def test_grid_finds_setting_that_separates_fake_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            synth.make_round(Path(tmp), np.random.default_rng(5), owners=6, imitators=6, other_bud=0)
            sessions = M.auto_sessions(M.load_dir(Path(tmp)))
        grid = tune.Grid(bands=[0.25], duration_weights=[0.5], factors=[1.0, 1.25, 1.5, 2.0],
                         weights=[(1.0, 1.0, 1.0)])
        rows = tune.run_grid(sessions, grid)
        self.assertEqual(len(rows), 4)
        best = tune.pick_best(rows, owner_min=0.9)
        self.assertIsNotNone(best)
        self.assertGreaterEqual(best.owner_ok / best.owner_n, 0.9)
        self.assertEqual(best.imitator_ok, 0)

    def test_weight_grid_drops_scaled_duplicates(self):
        w = tune.weight_grid([0.0, 0.5, 1.0, 2.0])
        self.assertIn((1.0, 1.0, 1.0), w)
        self.assertNotIn((0.5, 0.5, 0.5), w)
        self.assertNotIn((0.0, 0.0, 0.0), w)
        self.assertEqual(len(w), len(set(w)))


if __name__ == "__main__":
    unittest.main()
