# Architecture and CI: design

Sub-project C of four (A open-source basics, B security fixes, C architecture and CI, D release). Date: 2026-11-13.

## Intent

After sub-project B the app has no open security weakness that a code change can close. What is left before the first release (sub-project D) is that the project is hard to change safely:

- Nothing checks a pull request automatically. Every check in B was run by hand.
- The rules that decide when a file opens, when a try counts and when keys are replaced sit in one 941-line UI class with no tests.
- Locking or unlocking a large file or folder freezes the window, because all file work runs on the main thread.
- Evaluation tooling from the hackathon is still part of the core library, and B left a short list of small defects and untested paths.

This sub-project fixes those four things, so that the maintainers and outside contributors can change the app and trust the result. It adds no feature.

## Goals

"Now" is `main` at d73424e (after PR #16).

### 1. Every pull request is checked automatically

**Now.** The repository has no CI. The checks B relied on (build with 0 warnings in three configurations, the tests, the strings check on the built app, the scan for machine paths) are commands someone runs by hand. The README states the number of unit tests (107) and is kept right by hand.

**After.**

- **One script runs every check**: `airsign/scripts/check.sh`. Contributors run it locally; CI runs the same script, so the two can't drift apart. It fails on the first problem and says which check failed. It does these, in this order:
  1. Build debug, release and lab release (`-DAIRSIGN_LAB`). Any compiler warning fails the check.
  2. Run the tests with coverage. A test failure fails the check.
  3. The number of tests in the run (skipped ones included, as Swift Testing counts them) must equal the number the README states. Only two tests may be skipped, each for one known reason: the replay test in `MatcherReplayTests` when the recordings folder is absent (the recordings are never committed), and the exFAT test when the script runs without `--with-test-volume`. Any other skip fails the check.
  4. Line coverage of `AirSignCore` must be at least 85% (it is 94.8% now).
  5. Build the app bundle twice with ad-hoc signing (`AIRSIGN_SIGN_ID=-`), default and lab. `strings` on the default binary must find none of `--test-mode`, `--probe`, `--selftest-keychain`; on the lab binary it must find all three. The app is built, never launched.
  6. No tracked file outside `docs/superpowers/` contains `/Users/` or `C:/airsign-data` (the scan B used; the plans and designs under `docs/superpowers/` quote those strings on purpose). The script must not trip over its own pattern.
- **The exFAT test runs in CI.** With `--with-test-volume` the script creates a small exFAT disk image, mounts it, runs `lockAndUnlockWorkOnAVolumeWithoutExclusiveRename` against it and detaches it; with that flag the exFAT test must have run, not been skipped. CI always passes the flag, so on CI the replay test is the only skip. Without the flag the script still passes on a fresh clone. If the image can't be created or mounted the check fails; it is never skipped silently.
- **The workflow** (`.github/workflows/ci.yml`) runs on every pull request and on every push to `main`, on the GitHub-hosted `macos-26` runner with Xcode 26.5 selected explicitly (Swift 6.3.2, the toolchain the maintainers use). It has `contents: read` permission only, uses no secrets and no signing certificate, uploads nothing, pins each action to a full commit SHA, cancels a superseded run of the same branch, and has a 20-minute timeout. It uses `pull_request`, never `pull_request_target`.
- **Documents.** CONTRIBUTING.md says what CI runs and how to run the same script locally. The PR template's first checklist line becomes "CI passes (or `airsign/scripts/check.sh` passes locally)". README gets a CI status badge.
- **After the workflow is on `main`**, the maintainer is asked whether to require the CI check before merging into `main` (a repository setting). That is the maintainer's step and needs their OK at that moment.

### 2. The rules live in the tested library, not in the UI model

**Now.** `AppModel.swift` is 941 lines: one `@MainActor` class that holds the screen state and also decides the rules. The app target has no tests. Some pieces of the rules below are already in `AirSignCore` with tests (the lockout arithmetic including `Lockout.recoveryEffect`, the launch state, replacing the profile and keys on a reset in `ProfileStore`). What is still in `AppModel`, with no test, is the rest of each rule: who calls those pieces, when, and in what order.

- which key opens a file (this Mac's master key first, then the key of each paired Mac), and when the answer is "wrong key";
- what an unlock run reports for each file (restored, wrong key, error) and which files stay waiting;
- when a try is refused without being counted (a cooldown is running; the profile can't be saved);
- what each result does to the lockout (a failed signature, a passed signature, a malformed code, a wrong code, a code that opened some files and not others);
- the identity check with the recovery code (the code must give the profile's recovery public key);
- which actions need the recovery code and not only a signature (changing the signature);
- pairing (only a Mac with its own enrolled signature can be paired, and only after the code has opened a file);
- enrollment: how many signatures, refusing a weak one, the confirmation checks, nothing saved until the recovery code is confirmed, changing a signature keeps its recovery code, a reset replaces the old keys only when the new enrollment is saved;
- routing of opened items (`.airsign` unlocks, anything else locks).

**After.**

- Each rule above is decided, whole, by code in `AirSignCore` and pinned by tests there. The rules move **unchanged**: same decisions, same order, as on `main` now. Library code that already holds a piece of a rule is reused, not copied. `AppModel` asks the library and shows the answer; it keeps the screen state, the capture loop, the timer and the wording of messages.
- For each rule, the test is written first from the behaviour read in `AppModel` and fails (the type or function it needs does not exist yet); then the rest of the rule moves.
- The pull request lists every rule that moved with the test that pins it.
- `AppModel` is split by feature into several files. No Swift file under `airsign/Sources` is longer than 400 lines and no function is longer than 50 lines. Test files stay under 800 lines.
- Lab-only code of the app (`#if AIRSIGN_LAB`) sits in its own files, so the default build's flows read without conditionals where that is possible.
- `AirSignCore` line coverage stays at or above 85% (goal 1 enforces it).

### 3. File work no longer freezes the window

**Now.** Locking and unlocking (reading the file, encryption, `ditto` for folders, the move to the Trash, the scratch-folder sweeps) run on the main thread. A large file or folder freezes the window until it is done. The sweep at launch runs on the main thread too.

**After.**

- Lock and unlock work, and both sweeps, run off the main thread. While one runs the window still moves, resizes and redraws.
- **The app says what is running**: a progress indicator and a line such as "Locking 3 items…" or "Unlocking 2 items…" in the place messages appear now. No percentage and no Cancel button.
- **One file operation at a time, and nothing else changes while it runs.** While a file operation is running the app accepts only: new open requests (which wait, see the next point), moving and resizing the window, looking at Settings, and Quit. Everything that uses or changes the profile, the keys or the lockout is unavailable until it ends: a signature or recovery-code try, an enrollment step, changing the signature, Reset, Forget paired Macs, demo mode, adding or removing a sample, the test lab's actions, and leaving the current screen with Cancel. Their controls are disabled, or the action is refused with a message. Nothing refused is counted as a try. So an operation's result is always applied to the same profile it started with.
- **Requests that arrive while a file operation is running wait in arrival order** and are handled when it ends, each exactly as it would be handled had it arrived then: a lock request locks; opened `.airsign` items replace the waiting list and show the unlock screen, as now. Nothing is dropped. Files that arrive during a try are never opened by that try.
- **Lockout accounting does not change.** A signature try is still counted before any file is opened. A recovery-code try is still counted from what it opened, when its file work ends. Because no second try can start in between, running file work in the background gives nobody extra tries. The rules in the two points above are in `AirSignCore` with tests (goal 2).
- Results are reported exactly as now: same lines, same tone, same Finder reveal.
- Quitting during an operation is allowed, as now. What a quit can leave behind is what README and SECURITY.md already say after B.
- Mechanism: Swift concurrency (`async`/`await`, actors or tasks). No new dependency.

### 4. Data-race checking is on, with no warnings

**Now.** The package builds in Swift 5 language mode with minimal concurrency checking. With `-strict-concurrency=complete` it gives 18 warnings in four files (`HeadphoneMotionSource` 8, `ProbeMode` 7, `ServicesProvider` 2, `Matcher` 1).

**After.**

- Complete concurrency checking is switched on in `Package.swift` for all three targets, so every build has it, and the build has 0 warnings. Goal 1's script then keeps it at 0.
- The warnings are fixed by making the code right (isolation, `Sendable`), not by silencing them. Where a system API leaves no other way, one narrowly placed `@preconcurrency import`, `@unchecked Sendable` or `nonisolated(unsafe)` with a one-line comment is allowed, and the pull request lists each one.
- The language mode stays Swift 5 in this sub-project (see the calls table).

### 5. Evaluation tooling leaves the core library; dead code goes

**Now.** `AirSignCore` contains `AttemptLog` and `AttemptLabels` (the test lab's plaintext log) and `MotionSample.fromSpikeRow` (reads the hackathon recordings). `FileLockerError.isDirectory` is never thrown but still has a message in `AppModel`. `HeadphoneMotionSource.stop()` is never called.

**After.**

- `AttemptLog`, `AttemptLabels` and the types only they use move to a new library target, `AirSignLab`, which depends on `AirSignCore`. The app imports it only inside `#if AIRSIGN_LAB`. Their tests move with them. `AirSignCore` then holds only what the product needs.
- `MotionSample.fromSpikeRow` moves to where it is used: the tests' support code if only tests use it, otherwise `AirSignLab`.
- `FileLockerError.isDirectory`, its message, and `HeadphoneMotionSource.stop()` are removed.
- CONTRIBUTING.md's table of folders gains `AirSignLab`.

### 6. What sub-project B left open

**Fixed here**, each with a test that fails first:

- **Saving the profile can't half-succeed.** `ProfileStore.save` sets the file's permissions after the atomic write, so a failure there reports an error although the new profile is already in place. After: the file has its final permissions before it replaces the old one, and no step that can fail comes after the replace.
- **A lockout saved by an older build can't outlast the longest cooldown.** Such a record has no length of its own, and after a restart its time left is taken from the wall clock uncapped, so a clock set back can stretch it. After: it is capped at the longest cooldown (4 hours).
- **"Forget paired Macs" works when the pairing keys can't be read.** Now the count shows 0 and the button is disabled. After: Settings says the paired Macs can't be read, and Forget stays available and removes the item.
- **Missing tests are added**: the partial-name rule for a folder restore and for a name collision (only the file restore is tested now); a reset whose profile write fails (only Keychain failures are injected now).

**Documented, not changed:**

- **Three races that need another process, running as the same user, to act within microseconds**: swapping a scratch folder between the sweep's checks and its delete; swapping the empty folder that reserves a name on exFAT or FAT; replacing a file between a failed copy's check and its clean-up on exFAT or FAT. SECURITY.md gains one bullet under Known limitations that names them and says why they stay: such a process can already read and delete everything the owner can, so winning the race gives it nothing new; AirSign has no more rights than that process.
- **The one-time 4-hour cooldown** for an install whose Keychain has no lockout item is by design (B). README's upgrade or troubleshooting text says so if it does not already; the release notes are sub-project D.

## Delivery

Two pull requests, in this order, each with its own plan:

1. **`ci/checks-and-tidy-up`**: goals 1, 4, 5 and 6. Nothing a user sees changes except the Settings fix in goal 6. CI is green on the pull request itself (a workflow added by a pull request runs on it).
2. **`refactor/rules-into-core`**: goals 2 and 3, checked by CI from the first push. It needs the maintainer's hand checks below.

## Non-goals

- No new feature and no change to wording, layout or flows, except the progress line (goal 3) and the Settings fix (goal 6).
- No change to the `.airsign` format, the HPKE info string, the HKDF salt, the Keychain service or account names, the bundle id, or the profile's encryption or stored fields.
- No Swift 6 language mode (later; see the calls table).
- No tests for the app target itself, no UI tests, no injected fake motion source. The rules get tests in the library; the thin layer left in `AppModel` is checked by hand.
- No streaming encryption. A file is still read into memory whole; very large files stay limited by memory. That needs a format change.
- No Cancel for a running operation, no percentage.
- No linter, formatter or any new tool or dependency. No checks for the Python tools under `tools/`.
- No scan for testers' names in CI: the list of names is private and stays on the maintainer's Mac. The maintainer's own scan before a push stays.
- No signing, notarization, versioning, CHANGELOG or release workflow (sub-project D).
- No Keychain access-control or Secure Enclave work (README roadmap).

## Anti-goals

- A refactor that changes a decision: a file that opened before and doesn't now, a try that was counted and isn't now, a key replaced at a different moment. "Unchanged" in goal 2 is the whole point.
- Background work that lets two tries run at once, or lets a try start before the last one was counted.
- A CI that can pass while tests are skipped or not run, that needs a secret, or that launches the app.
- A hand-written recursive delete, or any new code path that removes files, in order to close the three documented races.
- A change that makes a profile or a locked file written by this branch unreadable by the app at d73424e, or the reverse.
- Silencing concurrency warnings wholesale (`@unchecked Sendable` on a class with unprotected state, module-wide `@preconcurrency`).

## Constraints

- TDD: every behaviour change and every moved rule in `AirSignCore` gets a test that fails first.
- All builds stay at 0 warnings, now with complete concurrency checking. The 107 tests keep passing; tests that move to `AirSignLab` keep their assertions. The README's test count is updated whenever the number changes.
- English for all new text. Commit prefixes `ci:`, `refactor:`, `fix:`, `test:`, `docs:`, `chore:`; no attribution lines.
- Never open or print `.local/recovery-code.txt`. No real tester names in tracked files, commit messages or PR text. No test, check or script touches the real Keychain items under `com.makeuc.airsign` or the real `~/Library/Application Support/AirSign`. Nobody launches the built app from a script, in CI or locally.
- Pushing, opening each PR, merging, and changing a repository setting each need the maintainer's OK at that moment.
- The maintainer checks by hand on their Mac before the second PR merges:
  1. Default build, with AirPods: lock and unlock a file and a folder; one wrong signature; the lockout message counts down; `open -a AirSign --args --test-mode` shows no banner and no test-lab button.
  2. Lock a file of 500 MB or more and drag the window while it runs: the window follows, the progress line shows, and the result line appears at the end.
  3. Lab build with `AIRSIGN_SANDBOX`: enroll from scratch (signatures, confirmations, recovery code), then change the signature (it asks for the recovery code), then unlock a file with the new signature.

## Decisions taken by the maintainer

| Question | Decision |
|---|---|
| Scope | CI; rules out of `AppModel` into the tested library; file work off the main thread; tidy-up (dead code, lab tooling in the core, concurrency warnings, the test skipped on a fresh clone); B's leftovers |
| Order | B, then C, then D, each with its own spec, plan and PR |
| Questions | Skipped: the maintainer asked for the design to be written from the scope above. Every other choice in this document is the designer's call |

## Calls made by the designer (for the maintainer to check)

| Question | Call | Why |
|---|---|---|
| One PR or two | Two: CI and tidy-up first, then the refactor | CI is on `main` before the risky change; each diff is small enough to review; only the second needs hand checks with AirPods |
| How CI and local checks stay the same | One script that both run | A check that only exists in a workflow file can't be run before pushing |
| Runner and toolchain | `macos-26`, Xcode 26.5 pinned | The same Swift (6.3.2) as the maintainers' Macs; a pinned Xcode means a new toolchain can't turn warnings into a red build overnight. The repository is public, so hosted macOS minutes are free |
| Coverage floor | 85% of lines in `AirSignCore` | The maintainer's own rule is 80% minimum; the library is at 94.8%, and CI skips the replay test, so 85% leaves room without letting coverage slide |
| Test count check | Tests run must equal the README's number, one known skip allowed | Catches both a test that silently stopped running and a stale README |
| exFAT test in CI | Yes, on a disk image the script creates | It is the only test of B's fallback for drives with no exclusive rename, and it is skipped everywhere else |
| Swift 6 language mode | Not now; complete checking as warnings, kept at 0 | The mode switch adds run-time isolation checks that trap on a wrongly isolated callback. The AirPods motion callback can't be exercised in CI, so a trap there would show up only on a maintainer's Mac. With the warnings at 0 the switch is a one-line change that can get its own hand test later |
| Where the rules go | New small types in `AirSignCore`; `AppModel` stays the only observable object | Smallest change that makes the rules testable; no new architecture pattern for the views to learn |
| Tests for `AppModel` | None | It would need fakes for motion, Keychain and timers: a larger refactor than this sub-project, for the thinnest layer |
| Busy behaviour | While a file operation runs, only open requests, the window, Settings viewing and Quit are accepted; everything that uses or changes the profile, keys or lockout waits or is refused, uncounted | Letting a try run in parallel breaks lockout accounting; letting a Reset or an enrollment finish in the middle would apply a result to a different profile than the one the operation started with |
| Requests arriving while busy | They wait in order and are then handled as if they had just arrived | Dropping one loses the user's intent; opening a late file under a try that was made before it arrived would widen what that try authorized |
| Skips the script accepts | The replay test without recordings; the exFAT test without `--with-test-volume` | Both are skipped for a reason outside the code; any other skip is a test that stopped running |
| `AttemptLog` | Own library target `AirSignLab` | B's design left the move to this sub-project; the core library should hold only what the product needs |
| The three races | Documented in SECURITY.md, no code change | The racing process already has every right AirSign has; a hand-written delete to close them would add risk to the one path that must never remove the wrong thing |
| Legacy lockout cap | 4 hours | No cooldown is longer, so a legitimate record is never shortened |
| Branch protection | Asked after the first PR merges, not done by the builder | A repository setting is the maintainer's to change |

## Left to the builder

The names of new types, files and the test target for `AirSignLab`; how the script detects warnings and reads the coverage number; how complete checking is switched on in the manifest; the exact wording of the progress line and of the Settings line for unreadable pairing keys, and where the indicator sits (it follows the existing screens' style); how the one-at-a-time rule is built (actor, queue or task chain); the commit SHAs the actions are pinned to; the order of work inside each pull request.
