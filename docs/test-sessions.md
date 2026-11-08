# AirSign test-lab sessions

Consolidated record of the test-lab sessions in [test-protocol.md](test-protocol.md) (protocol v2), one section
per session per Mac. Counts come from `tools/testlog_summary.py` on each Mac. Discarded tallies are kept by hand
because the app doesn't log them. Johnny (role C) keeps this file.

> **Disclosure:** Johnny is both an imitator in these tests and the analyst who writes
> [evaluation.md](evaluation.md) and [algorithm-comparison.md](algorithm-comparison.md). To limit the
> conflict, the baseline matcher and its 1.25 factor were frozen before any test data existed, and every tuned
> factor uses S1 owner attempts only.

The recordings themselves (`attempt-*.json`, motion data) never go in this repo.

## Protocol checks

Every section is checked against these rules:

1. **Targets** (per tester, from protocol v2):

   | Session | Scenario | Who | Target |
   |---|---|---|---|
   | S1, S2, S3 | A1-owner | owner | 20 per session |
   | S1 | A2-zero-effort | each imitator | 10 |
   | S1 | A3-watched-once | each imitator | 10 |
   | S1 | A4-skilled | each imitator | 15 (the app shows /25) |
   | S3 | A4-skilled | each imitator, screen hidden | 10 |
   | S1 | A5-other-bud | owner | 10 |
   | S1 | A5-other-pair | owner | 10 |

2. **Enrollment:** exactly one, at the start of S1, with exactly 3 records.
3. **No re-enrollment in S2 or S3:** the enrollment fingerprint stays the S1 one.
4. **Every attempt has a tester name.**
5. **Sample rates** are measured per Mac and compared (AirPods Pro 3 ≈ 50 Hz; AirPods 4 may be 25 Hz).
6. **S3 A4** is done with the screen turned away from the imitator.

## Open issues

1. **Mac 2 enrollment (check 2 not met).** Before the enrollment now in use (`c468b7f068e6`), 21 A1-owner
   attempts made on an unlogged normal-mode profile were cleared (18:45 ET), and a first logged enrollment
   (`09b7490a5112`: owner 12/20 accepted, 3 failed lab-entry checks) was reset together with its records at
   18:55 ET, before any imitator attempt. Those records were deleted; if a copy turns up, keep it.
   [evaluation.md](evaluation.md) must say that Mac 2's owner numbers come from the second enrollment and that the
   first was unsteady. The 3-signature check after enrollment (branch `feat/enroll-confirm-3d`) is meant to catch
   exactly this. From now on no record is deleted: to start over, rename the `test-logs` folder and keep it.
2. **Mac 2 relabels: provenance added (resolved 20:15 ET).** 3 enroll records (owner Eric → Leo) and 10
   A2-zero-effort records (saved as A5-other-bud) now carry `relabeledFrom` and `relabelNote`, as on Mac 1; no
   other field changed. All 10 relabeled A2 attempts were scored rather than rejected as the wrong bud, which fits
   their being A2 attempts with Leo's bud.
3. **Mac 2 S1 items skipped, not made up.** Eric's A2 (10), A3 (10) and A4 (15), and Leo's A5-other-pair (10)
   were not done, and the team decided not to make them up in S3 (time goes to the demo build instead). Effects:
   - Leo's signature faces one imitator in S1 (Johnny) instead of two. Eric still attacks it in S3 (A4 with the
     screen hidden, 10), so two different people attack each owner overall.
   - A5-other-pair has run only on Mac 1 (10/10 rejected). Gate 1 compares the device ID, so the result doesn't
     depend on which Mac runs it.
   - After S3 there are about 151 imitator attempts instead of 186: if none is accepted, the 95% upper bound on
     the imitator acceptance rate is about 2.0% instead of 1.6%.
   - Eric had already seen Leo sign during S1, so an A3 by Eric would not have been "watched once" anyway.
4. **Leo's enrolled signature is short.** Median 1.2 s and 2.7 rad of wrist turning, under the strength floors
   (1.5 s, 3 rad) that branch `feat/enroll-confirm-3d` adds, so the new build would refuse it (Eric's: 5.4 s,
   10.3 rad, strong). Mac 2's results are therefore for a signature the new policy calls weak; Johnny's 35
   attempts on it were all rejected, the closest at 1.34× the threshold (Leo's own highest was 1.17×). Don't
   re-enroll Mac 2 before S3 is done, even after the new build is installed.
5. **A4 over target on Mac 1.** Johnny logged 16 and Leo 20 against 15. All are kept. None was accepted, so the S1
   result doesn't depend on which 15 are used.

## Sample rates

| Mac | AirPods | S1 | S2 | S3 |
|---|---|---|---|---|
| Mac 1 MacBook Pro (Eric) | AirPods Pro 3 | 50.0 Hz | – | – |
| Mac 2 MacBook Air (Leo) | AirPods 4 | 25.0 Hz | – | – |

---

## S1-tonight, Mac 1

- **Session:** S1-tonight
- **Time window (ET):** planned 19:00–21:00; actual 18:45–19:18
- **Mac:** Mac 1, MacBook Pro
- **Owner:** Eric
- **AirPods:** AirPods Pro 3, `right` bud
- **Measured sample rate:** 50.0 Hz (median of 120 records)
- **Enrollment fingerprint:** `6f1a57e8182d` (records: 3, `right` bud)

| Tester | Scenario | Logged | Accepted | Target | Left |
|---|---|---|---|---|---|
| Eric | A1-owner | 20 | 20 | 20 | 0 |
| Leo | A2-zero-effort | 10 | 0 | 10 | 0 |
| Leo | A3-watched-once | 10 | 0 | 10 | 0 |
| Leo | A4-skilled | 20 | 0 | 15 | 0 (5 over) |
| Johnny | A2-zero-effort | 10 | 0 | 10 | 0 |
| Johnny | A3-watched-once | 10 | 0 | 10 | 0 |
| Johnny | A4-skilled | 16 | 0 | 15 | 0 (1 over) |
| Eric | A5-other-bud | 10 | 0 | 10 | 0 |
| Eric | A5-other-pair | 10 | 0 | 10 | 0 |

A5-other-bud was rejected by gate 1 every time (wrong bud); A5-other-pair (AirPods 4 on Mac 1) every time as a
different device.

**Discarded tally:** none recorded.

**Anomalies:**
- **19:02–19:03 ET:** 5 of Johnny's attempts saved as `A3-watched-once` were A4 (the scenario picker wasn't
  switched). Relabeled to `A4-skilled`; each file keeps `relabeledFrom`, and the originals are backed up on Mac 1.
- **Timing:** about 1 min between Johnny's last A3 (19:01:24) and first A4 (19:02:27), and about 3 min for Leo
  (19:10–19:13), less than the A4 preparation (video ×3, 5 min practice) takes. Eric confirmed both had done the
  preparation, so all their A4 attempts count.
- **19:06:07 ET:** one extra `A1-owner` record (rejected, score 0.604 vs threshold 0.596) was Eric demonstrating
  for an imitator. Marked `mode: "excluded"`, `scenario: "demo"`, with the original labels kept in the file.
  A1 stays 20/20.

## S1-tonight, Mac 2

- **Session:** S1-tonight
- **Time window (ET):** planned 19:00–21:00; actual 18:35–19:34
- **Mac:** Mac 2, MacBook Air
- **Owner:** Leo
- **AirPods:** AirPods 4, bud on Leo's dominant-hand side (`left` bud)
- **Measured sample rate:** 25.0 Hz (median of 69 records)
- **Enrollment fingerprint:** `c468b7f068e6` (records: 3, `left` bud)

| Tester | Scenario | Logged | Accepted | Target | Left |
|---|---|---|---|---|---|
| Leo | A1-owner | 21 | 20 | 20 | 0 |
| Eric | A2-zero-effort | 0 | 0 | 10 | 10 (skipped) |
| Eric | A3-watched-once | 0 | 0 | 10 | 10 (skipped) |
| Eric | A4-skilled | 0 | 0 | 15 | 15 (skipped) |
| Johnny | A2-zero-effort | 10 | 0 | 10 | 0 |
| Johnny | A3-watched-once | 10 | 0 | 10 | 0 |
| Johnny | A4-skilled | 15 | 0 | 15 | 0 |
| Leo | A5-other-bud | 10 | 0 | 10 | 0 |
| Leo | A5-other-pair | 0 | 0 | 10 | 10 (skipped) |

**Discarded tally:**

| Tester | Scenario | Discarded |
|---|---|---|
| Leo | A1-owner | 0 reported |
| Leo | A5-other-bud | 0 reported |
| Johnny | A2-zero-effort | 0 reported |
| Johnny | A3-watched-once | 0 reported |
| Johnny | A4-skilled | 0 reported |

**Anomalies:**
- **18:35 ET:** Initial 21 `A1-owner` attempts were signed before clicking `Re-enroll owner (logged)` in the test lab (using the prior normal-mode profile without logged `mode: "enroll"` records); cleared at 18:45 ET before re-enrolling.
- **18:53 ET:** First logged test-lab enrollment (`09b7490a5112`) had high template drift (12/20 accepted on `A1-owner` and 3 failed lab-entry checks). At 18:55 ET, before any imitator attempts began, `profile.bin` and `test-logs` were reset and the owner re-enrolled (`c468b7f068e6`).
- **18:56 ET:** During `Re-enroll owner (logged)` for `c468b7f068e6`, the `Owner` field was still at the default `"Eric"` before being switched to `"Leo"` for `A1-owner`; the 3 `enroll` record labels were corrected to `owner: "Leo"`, `tester: "Leo"` at 19:32 ET.
- **19:24–19:25 ET** (file times; first noted as 19:05): Johnny's 10 `A2-zero-effort` attempts were recorded while the scenario dropdown remained on `A5-other-bud` from the preceding run; relabeled to `A2-zero-effort` at 19:32 ET.
- **19:31 ET:** `Eric` imitator scenarios (`A2`–`A4`) and `A5-other-pair` were skipped in `S1-tonight`.

---

## S2-midnight, Mac 1

- **Session:** S2-midnight
- **Time window (ET):** planned around 00:00; actual –
- **Mac:** Mac 1, MacBook Pro
- **Owner:** Eric
- **AirPods:** AirPods Pro 3, right bud
- **Measured sample rate:** –
- **Enrollment fingerprint:** – (must equal S1's; no re-enrollment)

| Tester | Scenario | Logged | Accepted | Target | Left |
|---|---|---|---|---|---|
| Eric | A1-owner | – | – | 20 | – |

**Discarded tally:** –

**Anomalies:** none recorded yet.

## S2-midnight, Mac 2

- **Session:** S2-midnight
- **Time window (ET):** planned around 00:00; actual –
- **Mac:** Mac 2, MacBook Air
- **Owner:** Leo
- **AirPods:** AirPods 4
- **Measured sample rate:** –
- **Enrollment fingerprint:** – (must equal S1's; no re-enrollment)

| Tester | Scenario | Logged | Accepted | Target | Left |
|---|---|---|---|---|---|
| Leo | A1-owner | – | – | 20 | – |

**Discarded tally:** –

**Anomalies:** none recorded yet.

---

## S3-morning, Mac 1

- **Session:** S3-morning
- **Time window (ET):** planned 07:30; actual –
- **Mac:** Mac 1, MacBook Pro
- **Owner:** Eric
- **AirPods:** AirPods Pro 3, right bud
- **Measured sample rate:** –
- **Enrollment fingerprint:** – (must equal S1's; no re-enrollment)
- **A4 with the screen hidden:** –

| Tester | Scenario | Logged | Accepted | Target | Left |
|---|---|---|---|---|---|
| Eric | A1-owner | – | – | 20 | – |
| Leo | A4-skilled | – | – | 10 | – |
| Johnny | A4-skilled | – | – | 10 | – |

**Discarded tally:** –

**Anomalies:** none recorded yet.

## S3-morning, Mac 2

- **Session:** S3-morning
- **Time window (ET):** planned 07:30; actual –
- **Mac:** Mac 2, MacBook Air
- **Owner:** Leo
- **AirPods:** AirPods 4
- **Measured sample rate:** –
- **Enrollment fingerprint:** – (must equal S1's; no re-enrollment)
- **A4 with the screen hidden:** –

| Tester | Scenario | Logged | Accepted | Target | Left |
|---|---|---|---|---|---|
| Leo | A1-owner | – | – | 20 | – |
| Eric | A4-skilled | – | – | 10 | – |
| Johnny | A4-skilled | – | – | 10 | – |

**Discarded tally:** –

**Anomalies:** none recorded yet.
