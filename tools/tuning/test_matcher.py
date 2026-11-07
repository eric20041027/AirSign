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

import evaluate as E  # noqa: E402
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

    def test_every_round_must_reach_owner_target(self):
        p = M.Params()
        weak_round = tune.Row(p, [tune.Count(10, 10, 0, 5, 1.0), tune.Count(8, 10, 0, 5, 1.0)],
                              tune.Count(18, 20, 0, 10, 1.0))
        strong = tune.Row(M.Params(threshold_factor=1.5), [tune.Count(9, 10, 1, 5, 0.9), tune.Count(9, 10, 1, 5, 0.9)],
                          tune.Count(18, 20, 2, 10, 0.9))
        self.assertIs(tune.pick_best([weak_round, strong], owner_min=0.9), strong)

    def test_ties_go_to_fewest_changed_constants(self):
        c = tune.Count(10, 10, 0, 5, 0.9)
        two = tune.Row(M.Params(duration_weight=0.25, weights=(1.0, 0.5, 0.5)), [tune.Count(10, 10, 0, 5, 0.95)], c)
        one = tune.Row(M.Params(weights=(1.0, 0.5, 0.5)), [c], c)
        self.assertEqual(tune.changed_constants(one.params), 1)
        self.assertIs(tune.pick_best([two, one]), one)

    def test_weight_grid_drops_scaled_duplicates(self):
        w = tune.weight_grid([0.0, 0.5, 1.0, 2.0])
        self.assertIn((1.0, 1.0, 1.0), w)
        self.assertNotIn((0.5, 0.5, 0.5), w)
        self.assertNotIn((0.0, 0.0, 0.0), w)
        self.assertEqual(len(w), len(set(w)))


def logged(scenario, session="S1-tonight", owner="O", mode="verify", enrollment="fp1", loc="right", rid="x",
           rejection=None, n=40, seed=0, shape=None):
    rows = synth.rows_for(shape or synth.owner_shape, n, 0.2, (0, 0.7, -0.7), np.random.default_rng(seed))
    return M.Logged(rid, mode, "genuine", loc, rows, scenario=scenario, session=session, owner=owner,
                    enrollment=enrollment, rejection=rejection, accepted=None if mode == "enroll" else True)


def case(scenario, session="S1-tonight", owner="O"):
    return E.Case(logged(scenario, session, owner), (), "fp1", "right")


class ProtocolV2Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls.tmp.name)
        synth.make_test_logs(cls.dir, np.random.default_rng(11), owner_n=6, imit_n=(2, 2), a4_n=(3, 2), a5_n=1,
                             unknown_n=1)
        cls.data = E.load([cls.dir / "mac1", cls.dir / "mac2"])

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_every_attempt_uses_its_owners_s1_templates(self):
        keys = {}
        for c in self.data.cases:
            keys.setdefault(c.rec.owner, set()).add(c.key)
            self.assertEqual(c.templates[0].session, E.S1)
        self.assertEqual({o: len(k) for o, k in keys.items()}, {"Eric": 1, "B": 1})
        self.assertEqual(self.data.dropped_device_unknown, 2)
        self.assertEqual(self.data.reenrolled_after_s1, 0)
        self.assertEqual({c.rec.session for c in self.data.cases}, {E.S1, E.S2, E.S3})

    def test_later_reenrollment_is_counted_but_scored_against_s1(self):
        recs = [logged(E.OWNER, mode="enroll", enrollment="s1", rid=f"e{i}", seed=i) for i in range(3)]
        recs += [logged(E.OWNER, E.S2, mode="enroll", enrollment="s2", rid=f"f{i}", seed=9 + i) for i in range(3)]
        recs += [logged(E.OWNER, E.S2, enrollment="s2", rid="v")]
        data = E.build(recs)
        self.assertEqual(data.reenrolled_after_s1, 1)
        self.assertEqual(data.cases[0].key, "s1")

    def test_replay_matches_logged_scores_and_gate1_never_accepts(self):
        import algorithms_ref as R
        self.assertLess(E.app_match(self.data.cases, R.baseline), 1e-3)
        rs = E.ratios(R.baseline, self.data.cases)
        a5 = [r for c, r in zip(self.data.cases, rs) if c.rec.scenario in E.GATE1]
        self.assertTrue(a5 and all(math.isinf(r) for r in a5))

    def test_wilson(self):
        lo, hi = E.wilson(0, 100)
        self.assertEqual(lo, 0.0)
        self.assertAlmostEqual(hi, 0.0370, places=3)  # the 3.7% in test-protocol.md
        lo, hi = E.wilson(19, 20)
        self.assertAlmostEqual(lo, 0.7639, places=3)
        self.assertAlmostEqual(hi, 0.9911, places=3)

    def test_s1_factor_uses_s1_owner_attempts_only(self):
        cases = [case(E.OWNER) for _ in range(20)] + [case(E.OWNER, E.S2), case(E.A4)]
        rs = [0.5] * 19 + [2.0] + [9.0, 0.1]
        self.assertAlmostEqual(E.s1_factor(cases, rs), 0.6)  # 19/20 = 95% at 0.5, plus 0.10
        rs[0] = math.inf
        self.assertAlmostEqual(E.s1_factor(cases, rs), 2.1)  # now the 19th smallest is 2.0

    def test_mcnemar(self):
        self.assertAlmostEqual(E.mcnemar_one_sided(7, 0), 1 / 128)
        self.assertAlmostEqual(E.mcnemar_one_sided(9, 1), 11 / 1024)
        self.assertEqual(E.mcnemar_one_sided(0, 0), 1.0)

    def test_switch_rules(self):
        import bakeoff as B
        cases = ([case(E.OWNER, E.S2) for _ in range(20)] + [case(E.OWNER, E.S3) for _ in range(20)]
                 + [case(E.A3) for _ in range(8)] + [case(E.A4, E.S3) for _ in range(4)])
        base = B.Result("baseline", [0.5] * 40 + [1.0] * 7 + [3.0] * 5, 1.25, True)
        good = B.Result("good", [0.5] * 40 + [3.0] * 12, 1.25, False)
        rules = B.switch_rules(cases, base, good)
        self.assertEqual([r.ok for r in rules], [True, True, True])  # 7:0 in its favour
        six = B.Result("six", [0.5] * 40 + [3.0] * 6 + [1.0] + [3.0] * 5, 1.25, False)
        self.assertFalse(B.switch_rules(cases, base, six)[2].ok)  # 6:0 isn't enough
        no_s3 = [c for c in cases if c.rec.session != E.S3]
        r = B.switch_rules(no_s3, B.Result("b", base.rs[:20] + base.rs[40:48], 1.25, True),
                           B.Result("g", good.rs[:20] + good.rs[40:48], 1.25, False))
        self.assertIsNone(r[1].ok)
        self.assertEqual(B.verdict(r), "pending")

    def test_reports_render(self):
        import xml.etree.ElementTree as ET
        import bakeoff as B
        out = self.dir / "docs" / "evaluation.md"
        out.parent.mkdir(exist_ok=True)
        E.run([self.dir / "mac1", self.dir / "mac2"], out, note="Discarded: 0")
        text = out.read_text(encoding="utf-8")
        for needle in ("## Frozen baseline", "Wilson 95%", "Disclosure", "S1 equal error rate", "Discarded: 0"):
            self.assertIn(needle, text)
        for name in ("scores.svg", "acceptance.svg"):
            ET.parse(out.parent / "evaluation" / name)
        algs, source = B.load_algorithms()
        self.assertEqual(list(algs), ["baseline", *B.CHALLENGERS])
        md = B.report(self.data, B.evaluate_all(self.data.cases, algs), source)
        for needle in ("## Main table", "## Switch rule", "## Recommendation", "Disclosure", "A4 attack S3"):
            self.assertIn(needle, md)


class ReferenceAlgorithmTests(unittest.TestCase):
    """algorithms_ref.py must give the same numbers as the prototype's quick_candidates.py."""

    @classmethod
    def setUpClass(cls):
        import ast
        src = (Path(__file__).parent / "quick_candidates.py").read_text(encoding="utf-8")
        tree = ast.parse(src)
        tree.body = [n for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom, ast.FunctionDef))]
        cls.qc = {}
        exec(compile(tree, "quick_candidates.py", "exec"), cls.qc)  # functions only; its script part needs argv
        rng = np.random.default_rng(4)

        def mk(shape, n, i):
            return M.Attempt(f"a{i}", "enroll", "genuine", "right", synth.rows_for(shape, n, 0.3, (0, 0.7, -0.7), rng))

        cls.T = [mk(synth.owner_shape, n, i) for i, n in enumerate((44, 47, 50))]
        cls.v = mk(synth.forgery_shape, 46, 9)

    def test_global_vec(self):
        import algorithms_ref as R
        np.testing.assert_allclose(R.global_vec(self.v.rows), self.qc["global_vec"](self.v.rows.tolist()),
                                   rtol=1e-6, atol=1e-9)

    def test_challenger_scores(self):
        import algorithms_ref as R
        q = self.qc

        def dist(a, b, s=3.0):
            return q["dtw"](q["feats"](a.rows.tolist(), s), q["feats"](b.rows.tolist(), s)) * q["dur_factor"](a.dur, b.dur)

        d = [dist(self.v, t) for t in self.T]
        e = [[dist(self.T[i], self.T[j]) if i != j else 0 for j in range(3)] for i in range(3)]
        near = sum(min(e[i][j] for j in range(3) if j != i) for i in range(3)) / 3
        far = sum(max(e[i][j] for j in range(3) if j != i) for i in range(3)) / 3
        med = min(range(3), key=lambda i: sum(e[i]))
        med_ref = sum(e[med][j] for j in range(3) if j != med) / 2
        nfm = min(d) / max(near, 1e-3) + max(d) / max(far, 1e-3) + d[med] / max(med_ref, 1e-3)
        self.assertAlmostEqual(R.normalized_nfm(self.v, self.T), nfm, places=6)
        self.assertAlmostEqual(R.gyro_x2(self.v, self.T), min(dist(self.v, t, 1.5) for t in self.T), places=6)
        tg = [q["global_vec"](t.rows.tolist()) for t in self.T]
        loo = sum(q["std_distance"](tg[i], [tg[j] for j in range(3) if j != i]) for i in range(3)) / 3
        worst = max(max(r) for r in e)
        dpg = min(d) / worst + q["std_distance"](q["global_vec"](self.v.rows.tolist()), tg) / max(loo, 1e-3)
        self.assertAlmostEqual(R.dtw_plus_global(self.v, self.T), dpg, places=5)


if __name__ == "__main__":
    unittest.main()
