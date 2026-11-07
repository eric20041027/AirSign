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

None yet.

## Sample rates

| Mac | AirPods | S1 | S2 | S3 |
|---|---|---|---|---|
| Mac 1 MacBook Pro (Eric) | AirPods Pro 3 | – | – | – |
| Mac 2 MacBook Air (Leo) | AirPods 4 | – | – | – |

---

## S1-tonight, Mac 1

- **Session:** S1-tonight
- **Time window (ET):** planned 19:00–21:00; actual –
- **Mac:** Mac 1, MacBook Pro
- **Owner:** Eric
- **AirPods:** AirPods Pro 3, right bud
- **Measured sample rate:** –
- **Enrollment fingerprint:** – (records: –)

| Tester | Scenario | Logged | Accepted | Target | Left |
|---|---|---|---|---|---|
| Eric | A1-owner | – | – | 20 | – |
| Leo | A2-zero-effort | – | – | 10 | – |
| Leo | A3-watched-once | – | – | 10 | – |
| Leo | A4-skilled | – | – | 15 | – |
| Johnny | A2-zero-effort | – | – | 10 | – |
| Johnny | A3-watched-once | – | – | 10 | – |
| Johnny | A4-skilled | – | – | 15 | – |
| Eric | A5-other-bud | – | – | 10 | – |
| Eric | A5-other-pair | – | – | 10 | – |

**Discarded tally:**

| Tester | Scenario | Discarded |
|---|---|---|
| – | – | – |

**Anomalies:** none recorded yet.

## S1-tonight, Mac 2

- **Session:** S1-tonight
- **Time window (ET):** planned 19:00–21:00; actual –
- **Mac:** Mac 2, MacBook Air
- **Owner:** Leo
- **AirPods:** AirPods 4, bud on Leo's dominant-hand side (–)
- **Measured sample rate:** –
- **Enrollment fingerprint:** – (records: –)

| Tester | Scenario | Logged | Accepted | Target | Left |
|---|---|---|---|---|---|
| Leo | A1-owner | – | – | 20 | – |
| Eric | A2-zero-effort | – | – | 10 | – |
| Eric | A3-watched-once | – | – | 10 | – |
| Eric | A4-skilled | – | – | 15 | – |
| Johnny | A2-zero-effort | – | – | 10 | – |
| Johnny | A3-watched-once | – | – | 10 | – |
| Johnny | A4-skilled | – | – | 15 | – |
| Leo | A5-other-bud | – | – | 10 | – |
| Leo | A5-other-pair | – | – | 10 | – |

**Discarded tally:**

| Tester | Scenario | Discarded |
|---|---|---|
| – | – | – |

**Anomalies:** none recorded yet.

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
