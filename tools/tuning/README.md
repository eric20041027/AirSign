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
python tune.py /path/outside/repo/sessions --report ../../docs/tuning.md
```

To replay the plan's round-2 split:

```bash
python tune.py /path/outside/repo/sessions --templates 20261107-144527-280,20261107-144533-012,20261107-144616-034 --from 20261107-144617 --to 20261107-145000
```

- `--quick` runs a small grid for a dry run.
- `--owner-min 0.9` is the owner acceptance target.
- `--min-dur 1.2` drops verify attempts that are 1.2 s or shorter.
- `python synth.py OUT_DIR` writes fake attempts for a dry run. Don't tune on them.

## Files

- `matcher.py`: loading, features, banded DTW, distance, scoring
- `tune.py`: grid search and the markdown report
- `synth.py`: fake data in the spike's format
- `test_matcher.py`: tests, including a check that the fast DTW matches a literal port of the spike's `dtw()`
