# CI checks and tidy-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every pull request is checked by one script that contributors can also run; the test lab's log leaves the core library; data-race checking is on with 0 warnings; what sub-project B left open is fixed or documented.

**Architecture:** `airsign/scripts/check.sh` is the only gate: the workflow does nothing but select the toolchain and run it. The package gains three targets: `AirSignLab` (the test lab's log), `AirSignTestSupport` (helpers both test targets share) and `AirSignLabTests`. Complete concurrency checking is one manifest setting used by every target; the language mode stays Swift 5.

**Tech Stack:** Swift 6.3.2 (tools version 6.0, language mode 5), SwiftPM, Swift Testing, CryptoKit, bash, GitHub Actions on `macos-26`.

**Spec:** `docs/superpowers/specs/2026-11-13-architecture-and-ci-design.md`. This plan is pull request 1 of 2 (`ci/checks-and-tidy-up`): goals 1, 4, 5 and 6. Goals 2 and 3 get their own plan.

## Global Constraints

- No change to the `.airsign` format, the HPKE info string `airsign-file-v1`, the HKDF salt, the Keychain service `com.makeuc.airsign` or its account names, the bundle id, or the profile's encryption or stored fields.
- The language mode stays Swift 5. No new dependency, linter, formatter or tool.
- No change to wording, layout or flows, except the Settings line in Task 5.
- Every build has 0 warnings. Tests that move keep their assertions. README's test count is updated in the same task whenever the number changes.
- TDD: every behaviour change in `AirSignCore` gets a test that fails first.
- New Swift files under `airsign/Sources` stay under 400 lines, functions under 50 lines, test files under 800 lines. `AppModel.swift` is split by the second pull request, not here.
- English for all new text. Commit prefixes `ci:`, `refactor:`, `fix:`, `test:`, `docs:`, `chore:`; no attribution lines.
- Never read anything under `.local/`. No real tester names in tracked files, commit messages or PR text.
- No test, check or script touches the real Keychain items under `com.makeuc.airsign` or the real `~/Library/Application Support/AirSign`. Tests use `InMemorySecretStore` and folders under the temporary directory. Nobody launches the built app from a script.
- Not allowed: a hand-written recursive delete in app or library code; `@unchecked Sendable` on a class with unprotected state; a module-wide `@preconcurrency`; a check that passes while a test is skipped for an unknown reason.
- Pushing, opening the PR, merging and changing a repository setting are the controller's steps, not a task's.

## Measured on `main` (d73424e)

- `swift test`: `Test run with 107 tests in 0 suites passed`. A skipped test prints `Test <name>() skipped.` and is included in the 107. On the maintainer's Mac one test is skipped (`lockAndUnlockWorkOnAVolumeWithoutExclusiveRename`); on a fresh clone `roundTwoOwnerVersusImitatorAUC` is skipped too, because `spikes/airpods-motion/sessions` is never committed.
- `AirSignCore` line coverage: 94.8% (1137 of 1199 lines).
- With `.enableUpcomingFeature("StrictConcurrency")` on every target, `swift build --build-tests` gives 21 warnings: `Sources/AirSign/HeadphoneMotionSource.swift` 8, `Sources/AirSign/ProbeMode.swift` 7, `Sources/AirSign/ServicesProvider.swift` 2, `Sources/AirSignCore/Matcher.swift` 1 (`ThresholdRule` is not `Sendable`), `Tests/AirSignCoreTests/Support.swift` 2 and `Tests/AirSignCoreTests/SampleUpdateTests.swift` 1 (global closures `ownerShape`, `forgeryShape`, `driftedShape`).
- This works and the real-volume test passes on it: `hdiutil create -size 16m -fs ExFAT -volname AIRSIGNCHK -ov <dir>/vol.dmg`, `hdiutil attach <dir>/vol.dmg -nobrowse -mountpoint <dir>/mnt`, `AIRSIGN_TEST_VOLUME=<dir>/mnt swift test`, `hdiutil detach <dir>/mnt`.
- `actions/checkout` v7.0.1 is commit `3d3c42e5aac5ba805825da76410c181273ba90b1`.
- `README.md` states the count once: "(107 unit tests)" on the line about the tested `AirSignCore` library.
- Disk images, code signing and reading the boot session do not work inside a restricted sandbox. A worker in one runs `swift build` and `swift test` as far as it can and says which steps it could not run; the controller runs the whole of `check.sh` outside.

## Review Focus

1. **A warning that was already reported once.** SwiftPM does not print a warning again for a file it does not recompile. Running `check.sh` twice without fixing the warning must fail both times. Pinned in Task 1, step 6.
2. **Skips.** Fresh clone, no flag: exactly the two known skips pass. Recordings present but the replay test skipped, or `--with-test-volume` given but the exFAT test skipped, or any third skip: the check fails. The disk image is detached on every exit path, including a failure and Ctrl-C. Pinned in Task 1, steps 5 and 6.
3. **The maintainer's built app.** `check.sh` never replaces or re-signs `airsign/build/AirSign.app`. `build-app.sh` removes its output path before building, so it must refuse an output path whose name does not end in `.app`. Pinned in Task 1, steps 2 and 5.
4. **Order of motion samples.** After Task 3 the AirPods samples still reach the main thread in the order CoreMotion delivered them. No test can cover it (the app target has none, and CI has no AirPods), so the reviewer reads `HeadphoneMotionSource` for it: delivery stays `DispatchQueue.main.async`, never `Task {}`.
5. **Pairing keys that are there but not usable.** The Keychain refuses to read the item, or the item holds bytes that are not keys: Settings says so, Forget is available, and after Forget the count is 0. Pinned in Task 5.

---

### Task 1: `check.sh`, the one script that runs every check

**Files:**
- Create: `airsign/scripts/check.sh` (executable)
- Modify: `airsign/scripts/build-app.sh`

**Interfaces:**
- Produces: `airsign/scripts/check.sh [--with-test-volume]`. Exit 0 and a last line `All checks passed.` when everything passes. On the first problem it prints `check failed: <name>` to stderr and exits non-zero, where `<name>` is one of `build`, `tests`, `test count`, `skipped tests`, `coverage`, `app bundle`, `machine paths`, `test volume`. It prints one line as each check starts (`==> 1/6 build` … `==> 6/6 machine paths`). Any other argument is a usage error.
- Produces: `build-app.sh` reads two optional variables. `AIRSIGN_APP`: where the bundle is written (default `build/AirSign.app`). `AIRSIGN_SWIFT_ARGS`: extra arguments, split on spaces, appended to both of its `swift build` calls. `check.sh` also appends `AIRSIGN_SWIFT_ARGS` to every `swift` command it runs itself (an environment that needs `--disable-sandbox` uses it).

What the script does, in this order (the spec fixes the order and the meaning; the commands are the intended mechanism):

| # | Check | Mechanism |
|---|---|---|
| 1 | Build debug with tests, release, lab release; any warning fails | `-Xswiftc -warnings-as-errors` on all three. Debug uses the default scratch path with `--build-tests --enable-code-coverage`; release uses `--scratch-path .build/check-default`; lab release adds `-Xswiftc -DAIRSIGN_LAB` and uses `--scratch-path .build/check-lab` |
| 2 | Tests with coverage | one `swift test --enable-code-coverage` run with the same flags as the debug build, output kept in a log. With `--with-test-volume` the image is created and mounted first and the run has `AIRSIGN_TEST_VOLUME` set |
| 3 | Test count and skips | the number in `Test run with N tests` equals the one number before ` unit tests` in `README.md` (exactly one such place, else fail). Every line in which Swift Testing says a test or a suite was skipped counts, whatever follows the word (`skipped.` or `skipped: "reason"`). Skipped test names: `roundTwoOwnerVersusImitatorAUC` is allowed only when `spikes/airpods-motion/sessions` does not exist; `lockAndUnlockWorkOnAVolumeWithoutExclusiveRename` only without `--with-test-volume`; nothing else |
| 4 | `AirSignCore` line coverage at least 85% | `xcrun llvm-cov report` on the test binary and `default.profdata`, restricted to `Sources/AirSignCore`; print covered, total and percent. The floor is one constant at the top of the script |
| 5 | Default and lab app bundles | `AIRSIGN_SIGN_ID=-` and `AIRSIGN_APP=<work dir>/…/AirSign.app`, calling `build-app.sh` twice with `AIRSIGN_SWIFT_ARGS` set so it reuses check 1's two release builds. `strings` on `Contents/MacOS/AirSign`: none of `--test-mode`, `--probe`, `--selftest-keychain` in the default binary, all three in the lab binary. Nothing is launched |
| 6 | No machine paths | `git grep` over tracked files, excluding `docs/superpowers`, for the two strings the spec names. The script builds the pattern from pieces so that it does not match itself |

Requirements the mechanism serves; if a command does not behave as the table assumes, change the command, keep the requirement, and say so in the report:
- A warning fails the script on every run until it is fixed (Review Focus 1).
- No configuration is compiled twice in one run.
- Everything the script creates outside `.build` lives in one `mktemp -d` folder named `airsign-check.XXXXXX` that an exit trap removes; the same trap detaches the image if it is mounted. With `--with-test-volume`, a failure to create or mount is `check failed: test volume`.
- The script works from any current directory and never writes to `airsign/build`.

- [ ] **Step 1: `build-app.sh` options.** Read `AIRSIGN_APP` and `AIRSIGN_SWIFT_ARGS` as described. Refuse, before removing anything, an `AIRSIGN_APP` whose last path component does not end in `.app`. With neither variable set the script behaves exactly as now.

- [ ] **Step 2: Check the options.**

Run: `cd airsign && AIRSIGN_SIGN_ID=- AIRSIGN_APP="$(mktemp -d)/x/AirSign.app" scripts/build-app.sh && AIRSIGN_APP=/tmp/not-an-app scripts/build-app.sh; echo "second exit=$?"`
Expected: the first call prints `Built …/x/AirSign.app (signed with: -)`; the second prints an error and `second exit=1`; `/tmp/not-an-app` was not created or removed; `git status --short` shows nothing under `airsign/build`.

- [ ] **Step 3: Write `check.sh`** with `set -euo pipefail`, following the table and the requirements.

- [ ] **Step 4: Run it on the unchanged tree.**

Run: `airsign/scripts/check.sh`
Expected: six `==>` lines, a coverage line close to `94.8%`, `All checks passed.`, exit 0. Running it again right away also exits 0 and is faster.

- [ ] **Step 5: Run it with the volume, and look at what it left.**

Run: `shasum airsign/build/AirSign.app/Contents/MacOS/AirSign > /tmp/before.sum 2>/dev/null; airsign/scripts/check.sh --with-test-volume; echo "exit=$?"; hdiutil info | grep -c airsign-check; shasum airsign/build/AirSign.app/Contents/MacOS/AirSign | diff - /tmp/before.sum && echo "app untouched"`
Expected: `exit=0`; the test log shows `lockAndUnlockWorkOnAVolumeWithoutExclusiveRename` passed, not skipped; `0` volumes still attached; `app untouched` (when a built app exists).

- [ ] **Step 6: Make each check fail once.** One at a time, make the change, run the script, confirm the message, undo the change (`git checkout -- <file>`), and confirm `git status --short` is clean at the end.

| Temporary change | Expected |
|---|---|
| add `let unused = 1` inside a function in `Sources/AirSignCore/Similarity.swift`; run the script **twice** | `check failed: build` both times |
| change `107 unit tests` to `108 unit tests` in `README.md` | `check failed: test count` |
| add `.disabled("x")` to `@Test func successResetsFailures` | `check failed: skipped tests` |
| set the coverage floor constant to `99` | `check failed: coverage` |
| append a line containing the first of the two machine-path strings to `CONTRIBUTING.md` | `check failed: machine paths` |
| press Ctrl-C (or `kill -INT`) during the tests of a `--with-test-volume` run | non-zero exit, and `hdiutil info \| grep -c airsign-check` prints `0` |

- [ ] **Step 7: Commit.**

```bash
git add airsign/scripts/check.sh airsign/scripts/build-app.sh
git commit -m "ci: add check.sh, the one script that runs every check"
```

---

### Task 2: The test lab's log moves to `AirSignLab`; dead code goes

**Files:**
- Modify: `airsign/Package.swift`
- Move: `airsign/Sources/AirSignCore/AttemptLog.swift` → `airsign/Sources/AirSignLab/AttemptLog.swift` (whole file: `AttemptLabels`, the `Enrollment.fingerprint` extension, `AttemptLog`; it gains `import AirSignCore`)
- Move: `airsign/Tests/AirSignCoreTests/AttemptLogTests.swift` → `airsign/Tests/AirSignLabTests/AttemptLogTests.swift`
- Create: `airsign/Tests/AirSignTestSupport/Support.swift`
- Modify: `airsign/Tests/AirSignCoreTests/Support.swift`, and each test file that uses a moved helper (one `import` line)
- Modify: `airsign/Sources/AirSignCore/MotionSample.swift` (remove `fromSpikeRow`), `airsign/Sources/AirSignCore/FileLocker.swift` (remove `case isDirectory`), `airsign/Sources/AirSign/HeadphoneMotionSource.swift` (remove `stop()`), `airsign/Sources/AirSign/AppModel.swift` (the import; remove the `isDirectory` message), `airsign/Sources/AirSign/Views/TestLabView.swift` (the import)
- Modify: `README.md` (the count sentence), `CONTRIBUTING.md` (the table of folders)

**Interfaces:**
- Produces, in `Package.swift`:

```swift
.target(name: "AirSignCore"),
.target(name: "AirSignLab", dependencies: ["AirSignCore"]),
.executableTarget(name: "AirSign", dependencies: ["AirSignCore", "AirSignLab"], swiftSettings: […as now…]),
.target(name: "AirSignTestSupport", dependencies: ["AirSignCore"], path: "Tests/AirSignTestSupport"),
.testTarget(name: "AirSignCoreTests", dependencies: ["AirSignCore", "AirSignTestSupport"]),
.testTarget(name: "AirSignLabTests", dependencies: ["AirSignCore", "AirSignLab", "AirSignTestSupport"]),
```

- Produces: module `AirSignTestSupport` with `public` versions of exactly the helpers both test targets use: `strokes(_:n:noise:side:)`, `ownerShape`, and `MotionSample.fromSpikeRow(_:loc:)` as a `public extension` (same signature and body as now, so call sites do not change). Helpers only `AirSignCoreTests` uses (`sample`, `run`, `forgeryShape`, `FailingSecretStore`, `tempDir`, `testProfile`) stay where they are.
- The app imports `AirSignLab` only between `#if AIRSIGN_LAB` and `#endif`. `AirSignCore` no longer contains `AttemptLog`, `AttemptLabels`, `fingerprint` or `fromSpikeRow`.

- [ ] **Step 1: Move the tests first.** Add the three targets to `Package.swift`, create `Tests/AirSignTestSupport/Support.swift` with the shared helpers, `git mv` `AttemptLogTests.swift` and give it `import AirSignCore`, `import AirSignLab` and `import AirSignTestSupport` (keep `@testable` on an import only if a test needs an internal name). Do not move `AttemptLog.swift` yet.

- [ ] **Step 2: See it fail.**

Run: `cd airsign && swift build --build-tests 2>&1 | tail -5`
Expected: FAIL, because `Sources/AirSignLab` has no sources yet (or `AttemptLog` is not found in `AirSignLab`).

- [ ] **Step 3: Move the source and fix the imports.** `git mv` `AttemptLog.swift`; add `import AirSignCore` to it; remove `fromSpikeRow` from `MotionSample.swift` and the moved helpers from `AirSignCoreTests/Support.swift`; add `import AirSignTestSupport` where a test file needs it; add the guarded `import AirSignLab` to `AppModel.swift` and `TestLabView.swift`. The three moved tests keep every assertion.

- [ ] **Step 4: Remove the dead code.** `FileLockerError.isDirectory`, its line in `AppModel.describe`, and `HeadphoneMotionSource.stop()`.

- [ ] **Step 5: Documents.** In `README.md` the sentence becomes "…core logic in a tested `AirSignCore` library; the package has 107 unit tests." (the number still appears once, before ` unit tests`). In `CONTRIBUTING.md`'s table add `airsign/Sources/AirSignLab` (the test lab's plaintext attempt log; only lab builds use it; tested in `airsign/Tests/AirSignLabTests`) and `airsign/Tests/AirSignTestSupport` (helpers shared by the test targets).

- [ ] **Step 6: Verify.**

Run: `airsign/scripts/check.sh && grep -rn 'AttemptLog\|AttemptLabels\|fingerprint\|fromSpikeRow\|case isDirectory' airsign/Sources/AirSignCore; grep -rn 'FileLockerError.isDirectory\|func stop()' airsign/Sources`
Expected: `All checks passed.` with 107 tests; both `grep` commands print nothing.

- [ ] **Step 7: Commit.**

```bash
git add -A airsign/Package.swift airsign/Sources airsign/Tests README.md CONTRIBUTING.md
git commit -m "refactor: move the test lab's log into AirSignLab and remove dead code"
```

---

### Task 3: Complete concurrency checking, 0 warnings

**Files:**
- Modify: `airsign/Package.swift`
- Modify: `airsign/Sources/AirSignCore/Matcher.swift`, `airsign/Sources/AirSign/HeadphoneMotionSource.swift`, `airsign/Sources/AirSign/ProbeMode.swift`, `airsign/Sources/AirSign/ServicesProvider.swift`, and their call sites in `airsign/Sources/AirSign/AppModel.swift` and `airsign/Sources/AirSign/AirSignApp.swift`
- Modify: `airsign/Tests/AirSignTestSupport/Support.swift`, `airsign/Tests/AirSignCoreTests/Support.swift`, `airsign/Tests/AirSignCoreTests/SampleUpdateTests.swift`

**Interfaces:**
- Produces: one `let` in `Package.swift` holding `.enableUpcomingFeature("StrictConcurrency")`, used in `swiftSettings` of all six targets (the app target keeps its `AIRSIGN_LAB` define next to it). `swiftLanguageModes: [.v5]` stays.
- Produces: `HeadphoneMotionSource` and `ServicesProvider` are `@MainActor` classes whose callbacks are typed `@MainActor` (`onSample: (@MainActor (MotionSample) -> Void)?` and so on). Behaviour is unchanged: same statuses, same staleness rule, same samples in the same order.

Decisions the compiler will not make for you:
- **The motion handler runs on CoreMotion's queue, not the main actor.** Write the closure given to `startDeviceMotionUpdates` as `{ @Sendable [weak self] motion, error in … }` so it is checked as off-main code. What it calls directly (`sample(from:)`, `isDenied`) is `nonisolated`. It converts the `CMDeviceMotion` to a `MotionSample` there and hands only that value to the main actor.
- **Delivery to the main actor stays `DispatchQueue.main.async`,** as now. Do not replace it with `Task { @MainActor in … }`: separate tasks are not promised to run in the order they were created, and a signature is the order of its samples.
- **No `MainActor.assumeIsolated` on the motion path.** With the callbacks typed `@MainActor`, the two `MainActor.assumeIsolated` wrappers in `AppModel` (where `onSample` and `onStatus` are set) and the one in `AppDelegate.registerFinderServices` are removed, not kept. The one around `tick()` in `AppModel`'s timer is not part of this task and stays.
- The delegate methods of `CMHeadphoneMotionManagerDelegate` are `nonisolated` and hop the same way.
- `ProbeMode` (lab only) becomes `@MainActor`; its counters stop being captured `var`s. Its timer fires on the main run loop, so `MainActor.assumeIsolated` inside the timer block is acceptable there, with a one-line comment saying why.
- `ThresholdRule` gains `Sendable`. The three global shape closures in the tests are typed `@Sendable (Double) -> SIMD3<Double>`.
- Expected number of `@preconcurrency import`, `@unchecked Sendable` and `nonisolated(unsafe)`: zero. If a system API leaves no other way, one narrowly placed use with a one-line comment; list each one in the report.

- [ ] **Step 1: Turn the checking on and see the warnings.**

Run: `cd airsign && swift build --build-tests 2>&1 | grep -c 'warning:'; swift build --build-tests -Xswiftc -warnings-as-errors >/dev/null 2>&1; echo "strict exit=$?"`
Expected: the first build prints the warnings listed under "Measured" (21 unique places; the shared shape closure is now in `AirSignTestSupport`); the second fails, `strict exit=1`.

- [ ] **Step 2: Fix them** following the decisions above.

- [ ] **Step 3: Verify.**

Run: `airsign/scripts/check.sh && grep -rn 'assumeIsolated\|@preconcurrency\|@unchecked\|nonisolated(unsafe)\|Task {' airsign/Sources`
Expected: `All checks passed.` (three configurations, 0 warnings, 107 tests). The `grep` prints at most two lines, both `assumeIsolated` in a timer block: the one that was already in `AppModel.swift` and the one in `ProbeMode.swift`. No `Task {` anywhere in `HeadphoneMotionSource.swift`.

- [ ] **Step 4: Commit.**

```bash
git add airsign/Package.swift airsign/Sources airsign/Tests
git commit -m "refactor: turn on complete concurrency checking and fix every warning"
```

---

### Task 4: Saving the profile can't half-succeed; a legacy lockout is capped; the missing tests

**Files:**
- Modify: `airsign/Sources/AirSignCore/ProfileStore.swift` (`save`, one internal initializer)
- Modify: `airsign/Sources/AirSignCore/Lockout.swift` (`remaining`)
- Create: `airsign/Tests/AirSignCoreTests/ProfileSaveTests.swift`
- Modify: `airsign/Tests/AirSignCoreTests/LockoutAndProfileTests.swift`, `airsign/Tests/AirSignCoreTests/FileLockerTests.swift`
- Modify: `README.md` (the count)

**Interfaces:**
- Produces: `init(directory: URL, secrets: SecretStore, willReplaceProfile: @escaping (_ staged: URL) throws -> Void)`, internal, next to the public initializer (which passes a hook that does nothing). Same pattern as `FileLocker`'s internal initializer. `save` calls the hook with the staged file's URL immediately before the replace.
- `save` after this task: the Keychain copy of the lockout is written first, as now. The sealed profile is written to a new hidden file in the same folder, created exclusively with mode `0600`. That file then replaces `profile.bin` with one `rename(2)`. Nothing that can throw comes after the rename. Any failure before it removes the staged file this call created and leaves `profile.bin` as it was.
- `Lockout.remaining(now:boot:)` after this task: in the wall-clock branch the result is `min(wall-clock time left, lockedFor ?? the longest cooldown)`. The longest cooldown is the last entry of `Lockout.cooldowns` (14 400 s).

- [ ] **Step 1: Write the failing tests for `save`** in `ProfileSaveTests.swift`.

```swift
@Test func theProfileFileHasItsFinalPermissionsBeforeItReplacesTheOldOne() throws {
    let fm = FileManager.default, dir = tempDir(), secrets = InMemorySecretStore()
    let old = try testProfile("UID-A"), fresh = try testProfile("UID-B")
    try ProfileStore(directory: dir, secrets: secrets).createProfile(old)
    var stagedMode: Int?, stagedFolder: String?, profileAtThatMoment: Profile?
    let store = ProfileStore(directory: dir, secrets: secrets) { staged in
        stagedMode = (try fm.attributesOfItem(atPath: staged.path)[.posixPermissions] as? NSNumber)?.intValue
        stagedFolder = staged.deletingLastPathComponent().standardizedFileURL.path
        profileAtThatMoment = try ProfileStore(directory: dir, secrets: secrets).load()
    }
    try store.save(fresh)
    #expect(stagedMode == 0o600)
    #expect(stagedFolder == dir.standardizedFileURL.path)
    #expect(profileAtThatMoment == old)
    #expect(try store.load() == fresh)
    let url = dir.appendingPathComponent("profile.bin")
    #expect((try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(try fm.contentsOfDirectory(atPath: dir.path) == ["profile.bin"])
}

@Test func aSaveThatFailsBeforeTheReplaceKeepsTheOldProfileAndLeavesNothingBehind() throws {
    struct Stop: Error {}
    let dir = tempDir(), secrets = InMemorySecretStore()
    let old = try testProfile("UID-A")
    try ProfileStore(directory: dir, secrets: secrets).createProfile(old)
    let failing = ProfileStore(directory: dir, secrets: secrets) { _ in throw Stop() }
    #expect(throws: Stop.self) { try failing.save(try testProfile("UID-B")) }
    #expect(try ProfileStore(directory: dir, secrets: secrets).load() == old)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["profile.bin"])
}
```

- [ ] **Step 2: See them fail.**

Run: `cd airsign && swift test --filter ProfileSave 2>&1 | tail -5`
Expected: FAIL to compile: `ProfileStore` has no initializer with a trailing closure.

- [ ] **Step 3: Implement** the initializer and the new `save` as described under Interfaces.

- [ ] **Step 4: Write the failing test for the cap** in `LockoutAndProfileTests.swift`, next to `lockoutsSavedBeforeBootTrackingUseTheWallClock`.

```swift
@Test func aLockoutSavedByAnOlderBuildNeverLastsLongerThanTheLongestCooldown() throws {
    let l = try JSONDecoder().decode(Lockout.self, from: Data(#"{"failures":0,"lockCount":1,"lockedUntil":1000}"#.utf8))
    let setBackADay = Date(timeIntervalSinceReferenceDate: 1000 - 86_400 - 300)
    #expect(l.remaining(now: setBackADay, boot: bootA) == 14_400)
    #expect(l.remaining(now: setBackADay) == 14_400)
    let anchored = l.reanchored(now: setBackADay, boot: bootA)
    #expect(anchored.lockedFor == 14_400 && anchored.remaining(now: setBackADay, boot: bootA) == 14_400)
    #expect(l.remaining(now: Date(timeIntervalSinceReferenceDate: 900), boot: bootA) == 100)   // an honest record is unchanged
}
```

- [ ] **Step 5: See it fail, then implement.**

Run: `cd airsign && swift test --filter aLockoutSavedByAnOlderBuild 2>&1 | tail -5`
Expected: FAIL: `remaining` returns 86 700, not 14 400. Then change `remaining`; the test passes and `lockoutsSavedBeforeBootTrackingUseTheWallClock` still passes.

- [ ] **Step 6: Add the missing tests.** These pin behaviour that is already there; each is expected to pass as written. One that fails is a finding: fix the code, not the test, and say so in the report.

In `FileLockerTests.swift`, using the file's `Fixture`:
- `aRestoredFolderNamedLikeAPartialSurvivesTheNextUnlock`: a folder named `.airsign-partial-<UUID>` holding one file is locked and unlocked. The restored folder's name is that name without its leading dot. After one more lock and unlock of another file in the same folder, the restored folder and the file inside it are still there with the same bytes.
- `aNameCollisionNeverGivesARestoredItemAPartialName`: for a file and for a folder, with the stored name `.airsign-partial-<UUID>` and an item already at the name without the dot: the restored item is named `<that name> (unlocked)`, `Scratch.isPartialName` is false for it, the item that was already there is untouched, and both survive the next unlock in that folder.

In `LockoutAndProfileTests.swift`, next to `aResetThatFailsHalfWayCanBeRunAgain`:
- `aResetWhoseProfileWriteFailsStaysBlockedAndCanBeRunAgain`: after `createProfile(old)`, a store built with a `willReplaceProfile` hook that throws runs `createProfile(fresh, replacingExisting: true)`, which throws. Then, with a plain store on the same folder and secrets: `launchState()` is `.blocked`; the bytes of `profile.bin` are the same as before the reset; `createProfile(fresh, replacingExisting: true)` now succeeds, `launchState() == .ready(fresh)`, and the master key differs from the one before the reset.

- [ ] **Step 7: Update the count and verify.** Set the number in `README.md` to what the run reports.

Run: `airsign/scripts/check.sh`
Expected: `All checks passed.`; the test count is 107 plus the six new tests.

- [ ] **Step 8: Commit.**

```bash
git add airsign/Sources/AirSignCore/ProfileStore.swift airsign/Sources/AirSignCore/Lockout.swift airsign/Tests/AirSignCoreTests README.md
git commit -m "fix: give the profile file its final permissions before the replace; cap a legacy lockout at four hours"
```

---

### Task 5: "Forget paired Macs" works when the pairing keys can't be read

**Files:**
- Modify: `airsign/Sources/AirSignCore/ProfileStore.swift`
- Create: `airsign/Tests/AirSignCoreTests/PairedMacsTests.swift`
- Modify: `airsign/Sources/AirSign/AppModel.swift` (the four places that set `pairedMacCount`), `airsign/Sources/AirSign/Views/SettingsView.swift`
- Modify: `README.md` (the count)

**Interfaces:**
- Produces, in `AirSignCore`:

```swift
public enum PairedMacs: Equatable, Sendable {
    case readable(count: Int)
    case unreadable
    /// There is something to remove, or what is there can't be read.
    public var canForget: Bool { get }
}

extension ProfileStore {
    /// Never throws: a Keychain error or stored bytes that are not keys are `.unreadable`.
    public func pairedMacs() -> PairedMacs
}
```

- `AppModel` publishes `pairedMacs: PairedMacs` in place of `pairedMacCount: Int`, set from `store.pairedMacs()` where the count was read, and to `.readable(count: 0)` where it was set to 0. `pairedRecoveryKeys()`, `addPairedRecoveryKey` and `forgetPairedMacs` keep their behaviour; the unlock flow is not touched.

- [ ] **Step 1: Write the failing tests** in `PairedMacsTests.swift`.

```swift
@Test func pairedMacsReportsTheCountWhenTheKeysCanBeRead() throws {
    let store = ProfileStore(directory: tempDir(), secrets: InMemorySecretStore())
    #expect(store.pairedMacs() == .readable(count: 0) && !store.pairedMacs().canForget)
    try store.addPairedRecoveryKey(RecoveryCode.privateKey(for: RecoveryCode.generate()))
    #expect(store.pairedMacs() == .readable(count: 1) && store.pairedMacs().canForget)
}

@Test func pairingKeysTheKeychainWillNotReadCanStillBeForgotten() throws {
    let secrets = FailingSecretStore()
    let store = ProfileStore(directory: tempDir(), secrets: secrets)
    try store.addPairedRecoveryKey(RecoveryCode.privateKey(for: RecoveryCode.generate()))
    secrets.failingLoads = ["paired-recovery-keys"]
    #expect(store.pairedMacs() == .unreadable && store.pairedMacs().canForget)
    try store.forgetPairedMacs()
    #expect(store.pairedMacs() == .readable(count: 0))
    #expect(try secrets.inner.load("paired-recovery-keys") == nil)
}

@Test func storedBytesThatAreNotKeysCountAsUnreadableAndCanBeForgotten() throws {
    let secrets = InMemorySecretStore()
    let store = ProfileStore(directory: tempDir(), secrets: secrets)
    for junk in [Data("junk".utf8), try JSONEncoder().encode([Data([1, 2, 3])])] {
        try secrets.save(junk, as: "paired-recovery-keys")
        #expect(store.pairedMacs() == .unreadable && store.pairedMacs().canForget)
        try store.forgetPairedMacs()
        #expect(store.pairedMacs() == .readable(count: 0))
    }
}
```

- [ ] **Step 2: See them fail.**

Run: `cd airsign && swift test --filter PairedMacs 2>&1 | tail -5`
Expected: FAIL to compile: `ProfileStore` has no member `pairedMacs`.

- [ ] **Step 3: Implement `PairedMacs` and `pairedMacs()`**, then run the three tests: PASS.

- [ ] **Step 4: Use it in the app.** `AppModel` as under Interfaces. In `SettingsView` the row shows `Paired Macs: <n>` when readable, and when unreadable one plain sentence saying the paired Macs can't be read and that Forget removes them (wording is yours, in the tone of the lines around it). The button is disabled only when `!model.pairedMacs.canForget`. The message after a successful Forget stays as it is.

- [ ] **Step 5: Update the count and verify.**

Run: `airsign/scripts/check.sh && grep -rn 'pairedMacCount' airsign/Sources`
Expected: `All checks passed.` with three more tests than after Task 4; the `grep` prints nothing.

- [ ] **Step 6: Commit.**

```bash
git add airsign/Sources/AirSignCore/ProfileStore.swift airsign/Sources/AirSign/AppModel.swift airsign/Sources/AirSign/Views/SettingsView.swift airsign/Tests/AirSignCoreTests/PairedMacsTests.swift README.md
git commit -m "fix: keep Forget paired Macs available when the pairing keys can't be read"
```

---

### Task 6: The workflow and the documents

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `CONTRIBUTING.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `README.md`, `SECURITY.md`

- [ ] **Step 1: Write the workflow** with exactly this content.

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  check:
    name: check
    runs-on: macos-26
    timeout-minutes: 20
    env:
      DEVELOPER_DIR: /Applications/Xcode_26.5.app/Contents/Developer
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Toolchain
        run: xcodebuild -version && swift --version
      - name: Check
        run: airsign/scripts/check.sh --with-test-volume
```

- [ ] **Step 2: `CONTRIBUTING.md`.** Under "Build and test", add `scripts/check.sh` as the command to run before opening a pull request. Add a short section "Continuous integration" that says, in a few lines: every pull request and every push to `main` runs `airsign/scripts/check.sh --with-test-volume` on `macos-26` with Xcode 26.5; the six things the script checks, one line each; that without the flag the exFAT test is skipped locally, and that the replay test is skipped wherever the recordings are absent; that the README's test count must match the run. In "Rules for changes", the first rule ends with "keep `scripts/check.sh` passing".

- [ ] **Step 3: The PR template.** The first checklist line becomes:

```markdown
- [ ] CI passes (or `airsign/scripts/check.sh` passes locally)
```

- [ ] **Step 4: `README.md`.** Add a CI badge as the first badge of the row, linked to the workflow: image `https://github.com/eric20041027/AirSign/actions/workflows/ci.yml/badge.svg`, link `https://github.com/eric20041027/AirSign/actions/workflows/ci.yml`. At the end of the "Install" section add a short paragraph for people upgrading, with these facts and no more: a build from 13 November 2026 or later treats a missing Keychain copy of the lockout as tampering and starts the longest cooldown, 4 hours, once; an install made by an older build that has never saved a lockout is in that state; `security find-generic-password -s com.makeuc.airsign -a lockout` tells whether the item exists; if it does not, unlocking one file with the old build before upgrading creates it.

- [ ] **Step 5: `SECURITY.md`.** One bullet at the end of "Known limitations": three races are left in place, each needing another process that runs as the same user and acts within microseconds: swapping a scratch folder between the clean-up's checks and its delete; swapping the empty folder that reserves a name on exFAT or FAT; replacing a file between a failed copy's check and its clean-up on exFAT or FAT. Such a process can already read and delete everything the owner can, so winning the race gives it nothing new, and AirSign has no more rights than that process.

- [ ] **Step 6: Verify.**

Run: `ruby -e 'require "yaml"; y = YAML.load_file(".github/workflows/ci.yml"); puts y["jobs"]["check"]["runs-on"], y["permissions"].inspect' && airsign/scripts/check.sh && grep -c 'pull_request_target\|secrets\.' .github/workflows/ci.yml`
Expected: `macos-26`, `{"contents"=>"read"}`, `All checks passed.`, and `0` from the `grep`.

- [ ] **Step 7: Commit.**

```bash
git add .github/workflows/ci.yml .github/PULL_REQUEST_TEMPLATE.md CONTRIBUTING.md README.md SECURITY.md
git commit -m "ci: check every pull request and push to main; document the checks and what stays open"
```

---

## After the tasks (the controller)

1. Whole-branch review against the spec and this plan's Review Focus; one fix pass; scoped re-review.
2. `airsign/scripts/check.sh --with-test-volume` on the final tree. The whole-word scan for testers' names (the list is private and stays on the maintainer's Mac) finds nothing in tracked files or in the PR text.
3. Push `ci/checks-and-tidy-up` and open the pull request. Its description lists every `@preconcurrency import`, `@unchecked Sendable` and `nonisolated(unsafe)` (expected: none) and says that the AirPods motion path changed in Task 3 and is exercised by hand only before the second pull request merges.
4. The workflow runs on its own pull request and must be green there. If the runner has no Xcode 26.5 at that path, or cannot create the disk image, the fix is found in the runner image's documentation; the pin and the exFAT test are not dropped.
5. After the merge, ask the maintainer whether to require the `check` status before merging into `main`.
