# Matcher tuning (role C)

Python copy of the plan's Task 3 matcher, used to pick `thresholdFactor`,
`durationWeight`, the DTW band and the gyro/acc/grav balance from real
recordings. Needs Python 3.10+ and numpy.

**Never put recordings in this repo.** Keep the spike's `attempt-*.json` files in
a folder outside it. The report only contains counts and settings.

## Run

```bash
cd tools/tuning
python -m unittest discover -s .
python tune.py /path/outside/repo/sessions --report ../../archive/makeuc-2026/tuning.md
```

The two fair rounds from 2026-11-07, each with its own 3 templates (this produced `archive/makeuc-2026/tuning.md`):

```bash
python tune.py /path/outside/repo/sessions \
  --round "Round 1" 20261107-143432-081,20261107-143437-789,20261107-143444-477 20261107-143445 20261107-144241 \
  --round "Round 2" 20261107-144527-280,20261107-144533-012,20261107-144616-034 20261107-144617 20261107-145000
```

One setting is picked for all rounds: every round must reach the owner target,
then the fewest imitators accepted wins, then the fewest Swift constants changed.

- `--quick` runs a small grid for a dry run.
- `--owner-min 0.9` is the owner acceptance target.
- `--min-dur 1.2` drops verify attempts that are 1.2 s or shorter.
- `python synth.py OUT_DIR` writes fake attempts for a dry run. Don't tune on them.

## Test-mode records (archive/makeuc-2026/test-protocol.md)

After each session, unzip each Mac's `airsign-test-logs-*.zip` into its own folder
**outside the repo**, then:

```bash
python tune.py --test-logs /path/to/airsign-data/mac1-S1 /path/to/airsign-data/mac2-S1 --report ../../archive/makeuc-2026/evaluation.md
```

Pass every session's folders at once; folders are searched recursively. Add
`--note "Discarded: ..."` for the paper tally of discarded tries. This follows test
protocol v2 and writes `archive/makeuc-2026/evaluation.md` plus two charts in `archive/makeuc-2026/evaluation/`:

- Owners enroll once, in S1. Every attempt, S2 and S3 included, is scored against
  the owner's S1 templates.
- Attempts with `rejection: deviceUnknown` are left out (the app didn't count them).
- The frozen baseline (the app today, factor 1.25) is primary.
- A secondary factor comes from S1 owner attempts only: the smallest with ≥ 95%
  accepted, plus 0.10, applied unchanged to S2/S3.
- Results are k/n per owner and scenario with Wilson 95% intervals. A2 is reported
  as FAR; A3 and A4 as attack success rates. EER is for S1 only.
- It checks that the Python replay matches the scores the app logged.

## Algorithm bake-off (archive/makeuc-2026/algorithm-bakeoff.md)

```bash
python bakeoff.py /path/to/airsign-data/mac1-S1 /path/to/airsign-data/mac2-S1 --report ../../archive/makeuc-2026/algorithm-comparison.md
```

- Compares the frozen `baseline` with exactly three challengers: `gyro_x2`, `normalized_nfm`, `dtw_plus_global`.
- Challengers come from role B's `algorithms.py` when it has them, otherwise from `algorithms_ref.py`, a
  tested port of `quick_candidates.py`. The report says which was used.
- Each challenger's factor comes from S1 owners only (+0.10).
- The report ends with the switch rule: paired owner rejections no worse; S1 factor holds on S2 and S3;
  on S3 A4 plus all A3, a paired advantage at least as strong as 7:0.

`python synth.py OUT_DIR --test-logs` writes fake records in the same format for a dry run.

## Files

- `matcher.py`: loading, features, banded DTW, distance, scoring
- `tune.py`: grid search and the markdown report; `--test-logs` hands off to `evaluate.py`
- `evaluate.py`: protocol v2 core (S1 templates, Wilson, S1 factor, EER) and `archive/makeuc-2026/evaluation.md`
- `bakeoff.py`: baseline vs the three challengers and the switch rule, `archive/makeuc-2026/algorithm-comparison.md`
- `algorithms_ref.py`: reference baseline and challengers (fallback until `algorithms.py` lands)
- `quick_candidates.py`: the prototype reference the port is tested against
- `svgchart.py`: the two static SVG charts (standard library only)
- `synth.py`: fake data in the spike's format
- `test_matcher.py`: tests, including a check that the fast DTW matches a literal port of the spike's `dtw()`
