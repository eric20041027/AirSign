# Rules into the core library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The rules that decide when a file opens, when a try counts and when keys are replaced live in `AirSignCore` with tests; `AppModel` is split by feature; file work runs off the main thread, one operation at a time.

**Architecture:** Each rule becomes a small type in `AirSignCore` that takes values in and gives a decision out; `AppModel` stays the only observable object, asks those types, and keeps the screen state, the capture loop, the timer and the wording. The rules move first, unchanged, while `AppModel` is still one file; then the file is split with no code change; then file work moves behind one actor, with a queue type in `AirSignCore` deciding what waits.

**Tech Stack:** Swift 6.3.2 (tools version 6.0, language mode 5, complete concurrency checking), SwiftPM, Swift Testing, CryptoKit, SwiftUI/AppKit.

**Spec:** `docs/superpowers/specs/2026-11-13-architecture-and-ci-design.md`. This plan is pull request 2 of 2 (`refactor/rules-into-core`): goals 2 and 3. "Now" for this plan is `main` at de4d58c.

## Global Constraints

- **Unchanged means unchanged.** A rule that moves makes the same decisions in the same order as `AppModel` does at de4d58c: no file that opened before stops opening, no try that was counted stops being counted, no key is replaced at a different moment. When the code at de4d58c and this plan disagree, the code wins and the report says so.
- No change to the `.airsign` format, the HPKE info string, the HKDF salt, the Keychain service or account names, the bundle id, or the profile's encryption or stored fields.
- No change to wording, layout or flows, except: the progress line and indicator while a file operation runs, and one message for an action refused while it runs (Task 5).
- TDD: every moved rule gets its test first, written from the behaviour read in `AppModel`; the test fails because the type does not exist yet; then the rule moves and `AppModel` calls it. Library code that already holds a piece of a rule (`Lockout.recoveryEffect`, `ProfileStore.createProfile`, `launchState`) is reused, not copied.
- No Swift file under `airsign/Sources` is longer than 400 lines and no function longer than 50 lines when the branch is done. Test files stay under 800 lines.
- `airsign/scripts/check.sh` passes after every task: 0 warnings in three configurations under complete concurrency checking, `AirSignCore` line coverage at least 85%, and the README's test count equal to the run.
- No `@preconcurrency import`, `@unchecked Sendable` or `nonisolated(unsafe)` unless a system API leaves no other way; then one narrowly placed use with a one-line comment, listed in the report. No `Task {}` on the AirPods sample path. The language mode stays Swift 5. No new dependency.
- No tests for the app target, no UI tests, no fake motion source. No Cancel for a running operation, no percentage, no streaming encryption.
- English for all new text. Commit prefixes `refactor:`, `fix:`, `test:`, `docs:`, `chore:`; no attribution lines.
- Never read anything under `.local/`. No real tester names in tracked files, commit messages or PR text. No test, check or script touches the real Keychain items under `com.makeuc.airsign` or the real `~/Library/Application Support/AirSign`. Nobody launches the built app from a script.
- Don't skip or cancel a test. Pushing, opening the PR, merging and changing a repository setting are the controller's steps.

## The rules that move, and where each one is at de4d58c

| # | Rule | In `AppModel.swift` now | New home in `AirSignCore` | Task |
|---|---|---|---|---|
| 1 | Routing of opened items | `handleOpen` | `OpenRouting` | 1 |
| 2 | Which key opens a file | `openWithThisMacsKeys` | `UnlockKeys` | 1 |
| 3 | What an unlock run reports for each file; which files stay waiting | `unlockPending`, `UnlockOutcome` | `UnlockRun`, `UnlockOutcome` | 1 |
| 4 | What a lock run reports for each item | the loop in `lock(_:)` | `LockRun`, `LockOutcome` | 1 |
| 5 | When a try is refused without being counted | the first checks of `toggleCapture` and `submitRecoveryCode` | `AttemptGate` | 2 |
| 6 | What each result does to the lockout | `verifyAndUnlock`, `confirmIdentity`, `submitRecoveryCode` | `AttemptResult.lockoutEffect` | 2 |
| 7 | A signature try is counted before any file is opened; a recovery-code try is counted from what it opened | the order of calls in `verifyAndUnlock` and `submitRecoveryCode` | `UnlockAttempt` | 2 |
| 8 | The identity check with the recovery code | `submitRecoveryCode` (the `.confirmIdentity` branch) | `IdentityCheck` | 2 |
| 9 | Which actions need the recovery code | `IdentityPurpose.needsRecoveryCode` | `SensitiveAction` | 2 |
| 10 | Pairing | `submitRecoveryCode` (`rememberOnThisMac, profile != nil, !outcome.restored.isEmpty`) | `PairingRule` | 2 |
| 11 | Enrollment: how many signatures, the same AirPod, refusing a weak one, the confirmation checks | `addEnrollment`, `finishEnrollment`, `checkEnrollment`, `clearEnrollment`, `restartEnrollment` | `EnrollmentSession` | 3 |
| 12 | Nothing saved until the recovery code is confirmed; changing a signature keeps its recovery code | `finalizeEnrollment` | `EnrollmentCompletion` | 3 |
| 13 | One file operation at a time; what is allowed while it runs; requests that arrive meanwhile wait in order | new (goal 3) | `BusyPolicy`, `OpenQueue` | 5 |

"A reset replaces the old keys only when the new enrollment is saved" is already `ProfileStore.createProfile(_:replacingExisting:)` with tests; `AppModel` keeps calling it from `confirmRecoveryCodeWritten`, unchanged.

## Review Focus

1. **Order of counting and opening.** A signature that is rejected, or accepted but whose count could not be saved, opens no file. A recovery code is counted only after its file work, from what it opened; if that count cannot be saved, nothing more is reported (as now). Pinned in Task 2 by tests that record the order of calls.
2. **A try that must not be counted.** A signature made with the sound output on another device (`Rejection.deviceUnknown`) changes nothing: not the lockout, not the confirmation count during enrollment. Pinned in Tasks 2 and 3.
3. **Requests that arrive while files are being processed.** An item opened from Finder during a lock or an unlock is not dropped, is not handled early, and is never opened by the try that was already running. Several arrivals keep their order. Pinned in Task 5.
4. **Leaving in the middle.** While a file operation runs, Cancel, a second try, Reset, an enrollment step, Change signature, Forget paired Macs, demo mode, adding or removing a sample, Try again and the lab's actions do nothing except show the refusal, and nothing is counted. Pinned in Task 5 (the policy) and read in review (each entry point of `AppModel`).
5. **A wrong-key file among good ones.** Three items in one unlock: one opens, one was locked under another key, one is not an AirSign file. The first is restored, the second stays waiting, the third is reported, in that order; with the recovery code the try counts as a failure (a wrong key was seen). Pinned in Tasks 1 and 2.

---

### Task 1: The file rules: routing, keys, what a run reports

**Files:**
- Create: `airsign/Sources/AirSignCore/OpenRouting.swift`, `airsign/Sources/AirSignCore/UnlockKeys.swift`, `airsign/Sources/AirSignCore/FileRuns.swift`
- Create: `airsign/Tests/AirSignCoreTests/FileRulesTests.swift`
- Modify: `airsign/Sources/AirSign/AppModel.swift` (`handleOpen`, `lock`, `verifyAndUnlock`, `submitRecoveryCode`, `unlockPending`, `report`; remove `openWithThisMacsKeys` and the private `UnlockOutcome`)
- Modify: `README.md` (the count)

**Interfaces:**
- Produces:

```swift
public enum OpenRouting {
    /// `.airsign` items unlock, anything else locks. Each list keeps the order given.
    public static func route(_ urls: [URL]) -> (toLock: [URL], toUnlock: [URL])
}

public struct UnlockKeys {
    public init(master: SymmetricKey, paired: [Curve25519.KeyAgreement.PrivateKey])
    /// This Mac's master key first, then the key of each paired Mac, in order.
    /// Throws `LockedFileError.authenticationFailed` when none opens the file; any other error from the master key is thrown as it is.
    public func open(_ data: Data) throws -> (name: String, plaintext: Data)
}

public struct UnlockOutcome: Sendable {
    public struct Failure: Sendable { public let url: URL; public let error: Error }
    public var restored: [URL]
    /// Locked under another key: these stay waiting.
    public var wrongKey: [URL]
    public var failures: [Failure]
    public var allDone: Bool { get }          // no wrong key and no failure
}

public enum UnlockRun {
    /// Unlocks each item in order. `LockedFileError.authenticationFailed` puts the item in `wrongKey`; any other error in `failures`.
    public static func run(_ urls: [URL], locker: FileLocker,
                           open: (Data) throws -> (name: String, plaintext: Data)) -> UnlockOutcome
}

public struct LockOutcome: Sendable {
    public struct Locked: Sendable { public let source: URL; public let locked: URL }
    public struct Failure: Sendable { public let url: URL; public let error: Error }
    /// One entry per item, in the order given.
    public enum Item: Sendable { case locked(Locked), failed(Failure) }
    public var items: [Item]
    public var anyFailed: Bool { get }
}

public enum LockRun {
    public static func run(_ urls: [URL], locker: FileLocker, masterKey: SymmetricKey,
                           recoveryPublicKey: Curve25519.KeyAgreement.PublicKey) -> LockOutcome
}
```

- `AppModel` after this task: asks these types and turns their answers into the same lines as now ("Locked a → a.airsign (original moved to the Trash)", "name: reason", "Unlocked name", the wrong-key and foreign-Mac lines). The wording and `describe(_:)` stay in the app. `pendingUnlock = outcome.wrongKey` stays where it is.

- [ ] **Step 1: Write the failing tests** in `FileRulesTests.swift`, with a fixture like the one in `FileLockerTests.swift` (a temporary folder, a `FileLocker` whose trash moves items into a subfolder, a master key, a recovery code).

```swift
@Test func openedItemsAreRoutedByTheirExtension() {
    let urls = ["a.txt", "b.airsign", "Docs", "C.AIRSIGN", "d.airsign.txt"].map { URL(fileURLWithPath: "/tmp/x/\($0)") }
    let routed = OpenRouting.route(urls)
    #expect(routed.toLock.map(\.lastPathComponent) == ["a.txt", "Docs", "d.airsign.txt"])
    #expect(routed.toUnlock.map(\.lastPathComponent) == ["b.airsign", "C.AIRSIGN"])
    #expect(OpenRouting.route([]).toLock.isEmpty && OpenRouting.route([]).toUnlock.isEmpty)
}

@Test func thisMacsKeyIsTriedFirstThenEachPairedKey() throws {
    let master = SymmetricKey(size: .bits256), otherMaster = SymmetricKey(size: .bits256)
    let mine = try RecoveryCode.privateKey(for: RecoveryCode.generate())
    let theirs = try RecoveryCode.privateKey(for: RecoveryCode.generate())
    let stranger = try RecoveryCode.privateKey(for: RecoveryCode.generate())
    let local = try LockedFile.seal(Data("local".utf8), originalName: "l.txt", masterKey: master, recoveryPublicKey: mine.publicKey)
    let foreign = try LockedFile.seal(Data("foreign".utf8), originalName: "f.txt", masterKey: otherMaster, recoveryPublicKey: theirs.publicKey)
    let keys = UnlockKeys(master: master, paired: [stranger, theirs])
    #expect(try keys.open(local).plaintext == Data("local".utf8))
    #expect(try keys.open(foreign).plaintext == Data("foreign".utf8))
    #expect(throws: LockedFileError.authenticationFailed) { try UnlockKeys(master: master, paired: [stranger]).open(foreign) }
    #expect(throws: LockedFileError.authenticationFailed) { try UnlockKeys(master: master, paired: []).open(foreign) }
    #expect(throws: LockedFileError.notAirSignFile) { try keys.open(Data("junk".utf8)) }
}
```

Also, as tests with the fixture (names fixed, bodies yours):
- `anUnlockRunRestoresReportsAndKeepsWaitingInOrder`: three locked items in one folder, in this order: one sealed with the fixture's master key, one sealed with another master key, one file named `junk.airsign` holding junk bytes. `UnlockRun.run` with `LockedFile.open($0, masterKey: master)`: `restored` has the first (restored name and bytes checked), `wrongKey` is exactly the second, `failures` has the third with `LockedFileError.notAirSignFile`, `allDone` is false; the second and third `.airsign` files are still on disk and the first is in the trash.
- `anUnlockRunWithNothingWrongIsAllDone`: two good items → both restored, `allDone` true, `wrongKey` and `failures` empty.
- `aLockRunReportsEachItemInOrder`: a file, a folder, and an item that is already `.airsign`: items are `.locked`, `.locked`, `.failed` with `FileLockerError.alreadyLocked`, in that order; `anyFailed` true; both locked copies open with the master key.

- [ ] **Step 2: See them fail.**

Run: `cd airsign && swift test --filter FileRules 2>&1 | tail -5`
Expected: FAIL to compile: `OpenRouting`, `UnlockKeys`, `UnlockRun`, `LockRun` do not exist.

- [ ] **Step 3: Write the four types.** `UnlockKeys.open` is the body of `openWithThisMacsKeys`; `UnlockRun.run` is the loop of `unlockPending` without the assignment to `pendingUnlock`; `LockRun.run` is the loop in `lock(_:)` without the wording.

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Make `AppModel` use them.** `handleOpen` routes with `OpenRouting`. `lock(_:)` calls `LockRun.run` and builds its lines from the outcome. `verifyAndUnlock` builds `UnlockKeys` and passes `keys.open` to the run; `submitRecoveryCode` passes `LockedFile.open($0, recoveryCode:)`. `unlockPending` becomes a call to `UnlockRun.run` followed by `pendingUnlock = outcome.wrongKey`. `report` takes the library's `UnlockOutcome` and describes each failure with `describe(_:)` as before.

- [ ] **Step 6: Update the count and verify.** Set the number in `README.md` to what the run reports.

Run: `airsign/scripts/check.sh && grep -n 'openWithThisMacsKeys\|private struct UnlockOutcome' airsign/Sources/AirSign/AppModel.swift`
Expected: `All checks passed.`; the `grep` prints nothing.

- [ ] **Step 7: Commit.**

```bash
git add airsign/Sources/AirSignCore/OpenRouting.swift airsign/Sources/AirSignCore/UnlockKeys.swift airsign/Sources/AirSignCore/FileRuns.swift airsign/Tests/AirSignCoreTests/FileRulesTests.swift airsign/Sources/AirSign/AppModel.swift README.md
git commit -m "refactor: move routing, key order and run reporting into AirSignCore"
```

---

### Task 2: The attempt rules: refusal, lockout effect, order, identity, pairing

**Files:**
- Create: `airsign/Sources/AirSignCore/AttemptRules.swift`, `airsign/Sources/AirSignCore/UnlockAttempt.swift`
- Create: `airsign/Tests/AirSignCoreTests/AttemptRulesTests.swift`
- Modify: `airsign/Sources/AirSign/AppModel.swift` (`toggleCapture`, `verifyAndUnlock`, `submitRecoveryCode`, `confirmIdentity`, `IdentityPurpose`)
- Modify: `README.md` (the count)

**Interfaces:**
- Consumes: `UnlockOutcome` (Task 1), `Lockout.Effect`, `Lockout.recoveryEffect(restored:wrongKey:)`, `Verdict`, `Rejection`.
- Produces:

```swift
public enum AttemptRefusal: Equatable { case coolingDown(TimeInterval), cannotSave }

public enum AttemptGate {
    /// A try that would count toward the lockout is refused, uncounted: first when a cooldown is running, then when the profile can't be saved.
    public static func refusal(lockout: Lockout?, saveBlocked: Bool, now: Date, boot: BootClock?) -> AttemptRefusal?
}

public enum AttemptResult: Equatable {
    case signature(Verdict)                              // accepted: success; rejected: failure; `.deviceUnknown`: none
    case malformedCode                                   // failure
    case identityCode(matches: Bool)                     // success or failure
    case recoveryUnlock(restored: Int, wrongKey: Int)    // `Lockout.recoveryEffect`
    public var lockoutEffect: Lockout.Effect { get }
}

public enum SensitiveAction: Equatable, CaseIterable {
    case changeSignature, enableDemo, openLab
    /// One lucky imitation must not be enough to replace the owner's signature.
    public var needsRecoveryCode: Bool { get }           // true for `.changeSignature` only
}

public enum IdentityCheck {
    /// The code proves identity when the key it gives is the profile's recovery public key. No profile, or a malformed code: false.
    public static func codeMatches(_ code: String, recoveryPublicKey: Data?) -> Bool
}

public enum PairingRule {
    /// Only a Mac with its own enrolled signature can be paired, and only after the code has opened a file.
    public static func shouldPair(requested: Bool, hasProfile: Bool, restored: Int) -> Bool
}

public enum UnlockAttempt {
    public enum SignatureStep { case notCounted, rejected, countNotSaved, opened(UnlockOutcome) }
    /// Counts the try first. Files are opened only when the signature was accepted and the count was saved.
    public static func signature(_ verdict: Verdict, count: (Lockout.Effect) -> Bool,
                                 openFiles: () throws -> UnlockOutcome) rethrows -> SignatureStep

    public enum RecoveryStep { case counted(UnlockOutcome), countNotSaved(UnlockOutcome) }
    /// Opens first, then counts from what the code opened.
    public static func recoveryCode(openFiles: () -> UnlockOutcome,
                                    count: (Lockout.Effect) -> Bool) -> RecoveryStep
}
```

- `count` is `AppModel.adjustLockout`: it applies the effect, saves, and returns false when the save failed. `AppModel` keeps `adjustLockout`, `persist` and every message. In this task both functions are synchronous, like the code they replace, so nothing can run between the count and the file work. Task 5 makes them `async` together with the gate that keeps a second try out.
- `AppModel.IdentityPurpose` stays in the app (its lab cases are lab-only) and gains `var action: SensitiveAction`; `needsRecoveryCode` comes from the action.

- [ ] **Step 1: Write the failing tests** in `AttemptRulesTests.swift`.

```swift
private let now = Date(timeIntervalSince1970: 1_000_000)
private let boot = BootClock(session: "A", uptime: 1000)
private func locked() -> Lockout { var l = Lockout(); for _ in 0..<5 { l.recordFailure(now: now, boot: boot) }; return l }
private func verdict(accepted: Bool, _ rejection: Rejection? = nil) -> Verdict {
    Verdict(accepted: accepted, score: 1, threshold: 2, rejection: rejection, lights: [])
}

@Test func aTryIsRefusedUncountedDuringACooldownOrWhenNothingCanBeSaved() {
    #expect(AttemptGate.refusal(lockout: Lockout(), saveBlocked: false, now: now, boot: boot) == nil)
    #expect(AttemptGate.refusal(lockout: nil, saveBlocked: false, now: now, boot: boot) == nil)
    #expect(AttemptGate.refusal(lockout: locked(), saveBlocked: false, now: now, boot: boot) == .coolingDown(300))
    #expect(AttemptGate.refusal(lockout: locked(), saveBlocked: true, now: now, boot: boot) == .coolingDown(300))   // the cooldown is named first
    #expect(AttemptGate.refusal(lockout: Lockout(), saveBlocked: true, now: now, boot: boot) == .cannotSave)
    #expect(AttemptGate.refusal(lockout: nil, saveBlocked: true, now: now, boot: boot) == .cannotSave)
}

@Test func eachResultHasItsEffectOnTheLockout() {
    #expect(AttemptResult.signature(verdict(accepted: true)).lockoutEffect == .success)
    #expect(AttemptResult.signature(verdict(accepted: false, .scoreTooHigh)).lockoutEffect == .failure)
    #expect(AttemptResult.signature(verdict(accepted: false, .wrongBud)).lockoutEffect == .failure)
    #expect(AttemptResult.signature(verdict(accepted: false, .wrongDevice)).lockoutEffect == .failure)
    #expect(AttemptResult.signature(verdict(accepted: false, .deviceUnknown)).lockoutEffect == .none)
    #expect(AttemptResult.malformedCode.lockoutEffect == .failure)
    #expect(AttemptResult.identityCode(matches: true).lockoutEffect == .success)
    #expect(AttemptResult.identityCode(matches: false).lockoutEffect == .failure)
    #expect(AttemptResult.recoveryUnlock(restored: 2, wrongKey: 0).lockoutEffect == .success)
    #expect(AttemptResult.recoveryUnlock(restored: 2, wrongKey: 1).lockoutEffect == .failure)
    #expect(AttemptResult.recoveryUnlock(restored: 0, wrongKey: 0).lockoutEffect == .none)
}

@Test func onlyChangingTheSignatureNeedsTheRecoveryCode() {
    #expect(SensitiveAction.allCases.filter(\.needsRecoveryCode) == [.changeSignature])
}

@Test func theRecoveryCodeProvesIdentityOnlyWhenItGivesTheProfilesKey() throws {
    let code = RecoveryCode.generate(), other = RecoveryCode.generate()
    let key = try RecoveryCode.privateKey(for: code).publicKey.rawRepresentation
    #expect(IdentityCheck.codeMatches(code, recoveryPublicKey: key))
    #expect(IdentityCheck.codeMatches(code.lowercased(), recoveryPublicKey: key))     // as `RecoveryCode.normalize` accepts it
    #expect(!IdentityCheck.codeMatches(other, recoveryPublicKey: key))
    #expect(!IdentityCheck.codeMatches(code, recoveryPublicKey: nil))
    #expect(!IdentityCheck.codeMatches("not a code", recoveryPublicKey: key))
}

@Test func pairingNeedsARequestAnEnrolledMacAndAFileTheCodeOpened() {
    #expect(PairingRule.shouldPair(requested: true, hasProfile: true, restored: 1))
    #expect(!PairingRule.shouldPair(requested: false, hasProfile: true, restored: 1))
    #expect(!PairingRule.shouldPair(requested: true, hasProfile: false, restored: 1))
    #expect(!PairingRule.shouldPair(requested: true, hasProfile: true, restored: 0))
}
```

And for the order (Review Focus 1), with a small recorder that appends `"count:<effect>"` and `"open"` to an array:
- `aSignatureIsCountedBeforeAnyFileIsOpened`: accepted, `count` returns true → calls are `["count:success", "open"]`, step is `.opened`.
- `aRejectedSignatureOpensNothing`: rejected → `["count:failure"]`, `.rejected`. With `count` returning false → still `["count:failure"]`, `.countNotSaved`.
- `anAcceptedSignatureWhoseCountCannotBeSavedOpensNothing`: accepted, `count` returns false → `["count:success"]`, `.countNotSaved`.
- `aSignatureFromAnUnknownDeviceIsNotCountedAndOpensNothing`: `.deviceUnknown` → `[]`, `.notCounted`.
- `aRecoveryCodeIsCountedAfterItsFilesFromWhatItOpened`: `openFiles` returns an outcome with 1 restored and 1 wrong key → `["open", "count:failure"]`, `.counted`; with 2 restored → `["open", "count:success"]`; with nothing judged → `["open", "count:none"]`; with `count` returning false → `.countNotSaved`.

- [ ] **Step 2: See them fail.**

Run: `cd airsign && swift test --filter AttemptRules 2>&1 | tail -5`
Expected: FAIL to compile: the types do not exist.

- [ ] **Step 3: Write the types**, then run the tests: PASS.

- [ ] **Step 4: Make `AppModel` use them.** `toggleCapture` and `submitRecoveryCode` ask `AttemptGate` where they now check the cooldown and `saveBlocked` (same two messages, same order; in `toggleCapture` only when `countsTowardLockout`). `verifyAndUnlock` goes through `UnlockAttempt.signature`, `submitRecoveryCode`'s file branch through `UnlockAttempt.recoveryCode`; the malformed-code branch, the identity branch and `confirmIdentity` take their effect from `AttemptResult`. The identity branch asks `IdentityCheck`; the pairing condition asks `PairingRule`. Everything shown to the user is built exactly as before.

- [ ] **Step 5: Update the count and verify.**

Run: `airsign/scripts/check.sh && grep -n 'recoveryEffect\|needsRecoveryCode' airsign/Sources/AirSign/AppModel.swift`
Expected: `All checks passed.`; `recoveryEffect` no longer appears in `AppModel.swift`; `needsRecoveryCode` appears only where the purpose's action is asked.

- [ ] **Step 6: Commit.**

```bash
git add airsign/Sources/AirSignCore/AttemptRules.swift airsign/Sources/AirSignCore/UnlockAttempt.swift airsign/Tests/AirSignCoreTests/AttemptRulesTests.swift airsign/Sources/AirSign/AppModel.swift README.md
git commit -m "refactor: move the attempt rules into AirSignCore"
```

---

### Task 3: The enrollment rules

**Files:**
- Create: `airsign/Sources/AirSignCore/EnrollmentSession.swift`
- Create: `airsign/Tests/AirSignCoreTests/EnrollmentSessionTests.swift`
- Modify: `airsign/Sources/AirSign/AppModel.swift` (`addEnrollment`, `finishEnrollment`, `checkEnrollment`, `finalizeEnrollment`, `restartEnrollment`, `clearEnrollment`, and the published `enrolledSoFar`, `pendingEnrollment`, `confirmations`, `enrollStrength`)
- Modify: `README.md` (the count)

**Interfaces:**
- Produces:

```swift
public struct EnrollmentSession {
    public private(set) var signatures: [Signature]
    public private(set) var pending: Enrollment?       // set once enough steady signatures are in
    public private(set) var confirmations: Int
    public private(set) var strength: SignatureStrength?
    public init()

    public enum AddResult: Equatable {
        case wrongSide(expected: BudSide)              // not added
        case needMore(have: Int)
        case noOutputDevice                            // the last signature is taken back
        case tooWeak(SignatureStrength)                // everything is cleared; `strength` keeps the rating
        case cannotBuild(String)                       // everything is cleared
        case readyToConfirm
    }
    /// `deviceUID` is the sound output's AirPods, or nil when the output is something else.
    public mutating func add(_ signature: Signature, deviceUID: String?) -> AddResult

    public enum CheckResult: Equatable {
        case notCounted(Verdict)                       // `.deviceUnknown`: nothing changes
        case mismatch(check: Int)                      // which check failed; everything is cleared
        case passed(Int)                               // checks passed so far
        case complete(Enrollment)                      // all passed; `pending` and the count are cleared
    }
    public mutating func check(_ signature: Signature, deviceUID: String?) -> CheckResult

    /// Start over: `keepingStrength` is true for the internal clear after a failure, false for "Start over".
    public mutating func clear(keepingStrength: Bool)
}

public enum EnrollmentCompletion {
    case signatureChanged(Profile)                     // to save now
    case awaitingCodeConfirmation(profile: Profile, code: String)   // nothing is saved yet
    /// `current` is the profile whose signature is being changed, or nil for a first enrollment or a reset.
    public static func complete(_ enrollment: Enrollment, changingSignatureOf current: Profile?) throws -> EnrollmentCompletion
}
```

- Behaviour, read from `AppModel` at de4d58c and to be kept exactly:
  - `add`: a signature from the other AirPod than the first is refused and not added. When the list is empty the old rating is forgotten. With fewer than `MatcherConfig.enrollCount` signatures: `needMore`. With enough: no output device → the last one is removed; otherwise the rating is stored; a `.weak` rating clears the signatures but keeps the rating; `enroll(_:deviceUID:)` throwing clears and gives `cannotBuild` with the error's description; success sets `pending` and `confirmations = 0`.
  - `check`: verified against `pending` with the enrolled threshold. `.deviceUnknown` changes nothing. A miss reports the number of the check that failed (`confirmations + 1`) and clears. A pass adds one; at `MatcherConfig.confirmCount` it gives `complete` and clears `pending` and the count (the signatures stay until the app clears them).
  - `complete(_:changingSignatureOf:)`: with a current profile, the same profile with the new enrollment and `lockout.recordSuccess()` applied; its recovery public key and demo mode are untouched. Without one, a new recovery code, a profile with that code's public key, a fresh `Lockout()` and demo mode off.
- `AppModel` keeps one `EnrollmentSession` and publishes what the views read (`enrolledSoFar`, `pendingEnrollment`, `confirmations`, `enrollStrength`) from it, with the same names, so no view changes. The lab's raw rows (`enrolledRows`, lab builds only) stay in the app and follow the session: appended when a signature is added, the last removed on `noOutputDevice`, cleared with the session. `isReenrolling`, `isResetting`, `pendingProfile`, `recoveryCodeToShow` and all messages stay in the app.

- [ ] **Step 1: Write the failing tests** in `EnrollmentSessionTests.swift`, using `strokes`, `ownerShape` from `AirSignTestSupport` and `forgeryShape` from the test target's support file. Names fixed, bodies yours; each asserts the state after the call as well as the result:
  - `threeSteadySignaturesFromOneAirPodAreReadyToConfirm`: results `needMore(have: 1)`, `needMore(have: 2)`, `readyToConfirm`; `pending` set, `confirmations == 0`, `strength` set.
  - `aSignatureFromTheOtherAirPodIsRefusedAndNotAdded`: `wrongSide(expected: .right)`, count unchanged.
  - `withoutTheAirPodsAsOutputTheLastSignatureIsTakenBack`: third add with `deviceUID: nil` → `noOutputDevice`, two signatures left, `pending` nil; adding again with a device → `readyToConfirm`.
  - `aWeakSignatureIsRefusedAndTheRatingIsKept`: three very short, small signatures → `tooWeak`, signatures empty, `strength?.level == .weak`.
  - `threePassingChecksCompleteTheEnrollment`: `passed(1)`, `passed(2)`, `complete(enrollment)`; afterwards `pending == nil`, `confirmations == 0`.
  - `oneMissedCheckClearsTheEnrollment`: one pass, then a forgery → `mismatch(check: 2)`; signatures empty, `pending` nil, `confirmations == 0`.
  - `aCheckFromAnUnknownDeviceChangesNothing`: a check with `deviceUID: nil` against an enrollment that has a device → `notCounted`, state identical before and after.
  - `startingOverForgetsTheRating`: `clear(keepingStrength: false)` → everything empty and `strength == nil`.
  - `changingASignatureKeepsItsRecoveryCodeAndClearsTheLockout`: a profile with demo mode on and a locked lockout → `.signatureChanged`: same `recoveryPublicKey`, demo mode still on, new enrollment, `lockout.remaining(...) == nil` and `failures == 0`.
  - `aFirstEnrollmentWaitsForTheCodeToBeConfirmed`: `.awaitingCodeConfirmation`: the code normalizes, `profile.recoveryPublicKey` is that code's public key, `lockout == Lockout()`, demo mode off.

- [ ] **Step 2: See them fail.**

Run: `cd airsign && swift test --filter EnrollmentSession 2>&1 | tail -5`
Expected: FAIL to compile: the types do not exist.

- [ ] **Step 3: Write `EnrollmentSession` and `EnrollmentCompletion`**, then run the tests: PASS.

- [ ] **Step 4: Make `AppModel` use them.** `addEnrollment` and `finishEnrollment` become one call to `add` and a `switch` that says the same lines; `checkEnrollment` one call to `check`; `finalizeEnrollment` one call to `complete` (the `isReenrolling, var updated = profile` condition decides what is passed as `current`). Saving, logging to the lab, screens and messages stay where they are.

- [ ] **Step 5: Update the count and verify.**

Run: `airsign/scripts/check.sh`
Expected: `All checks passed.`

- [ ] **Step 6: Commit.**

```bash
git add airsign/Sources/AirSignCore/EnrollmentSession.swift airsign/Tests/AirSignCoreTests/EnrollmentSessionTests.swift airsign/Sources/AirSign/AppModel.swift README.md
git commit -m "refactor: move the enrollment rules into AirSignCore"
```

---

### Task 4: `AppModel` split by feature

**Files:**
- Modify: `airsign/Sources/AirSign/AppModel.swift` (state, `init`, launch, `block`, `persist`, `adjustLockout`, `say`)
- Create: `airsign/Sources/AirSign/AppModel+Files.swift`, `AppModel+Capture.swift`, `AppModel+Enrollment.swift`, `AppModel+Unlock.swift`, `AppModel+Identity.swift`, `AppModel+Settings.swift`, `AppModel+Messages.swift` (every `describe`, `format`), and `AppModel+Lab.swift` (everything that is lab-only, the whole file inside `#if AIRSIGN_LAB`)

This task moves code and changes none, with two exceptions that change no behaviour: a member that an extension in another file needs loses `private` (it becomes internal), and a `private(set)` property that such an extension assigns gets an internal setter, because Swift does not let an extension in another file use a private setter (a property assigned only inside `AppModel.swift` keeps `private(set)`), and a function still longer than 50 lines has consecutive statements lifted into a named helper that is called at the same place. Nothing is renamed, reordered or rewritten.

- Lab-only code sits in `AppModel+Lab.swift` wherever a whole member is lab-only. Where a default-build function has a lab-only line in the middle, move that line into a small function that exists in both builds (empty in the default build) only if that removes the `#if` from the function without changing what runs; otherwise leave the `#if` where it is and say so in the report.

- [ ] **Step 1: Move the code.**

- [ ] **Step 2: Verify.**

Run: `airsign/scripts/check.sh && wc -l airsign/Sources/AirSign/*.swift airsign/Sources/AirSign/Views/*.swift airsign/Sources/AirSignCore/*.swift airsign/Sources/AirSignLab/*.swift | sort -n | tail -4`
Expected: `All checks passed.` with the same test count as after Task 3; no file over 400 lines.

Also: `git diff --stat` shows only files under `airsign/Sources/AirSign`; and for the reviewer, `git diff -M --color-moved=dimmed-zebra` shows moved blocks and nothing new except access levels and the split points.

- [ ] **Step 3: Commit.**

```bash
git add -A airsign/Sources/AirSign
git commit -m "refactor: split AppModel by feature"
```

---

### Task 5: File work off the main thread, one operation at a time

**Files:**
- Create: `airsign/Sources/AirSignCore/FileWorkRules.swift`
- Create: `airsign/Tests/AirSignCoreTests/FileWorkRulesTests.swift`
- Create: `airsign/Sources/AirSign/FileWorker.swift`
- Modify: `airsign/Sources/AirSignCore/UnlockAttempt.swift` and `airsign/Tests/AirSignCoreTests/AttemptRulesTests.swift` (async), `airsign/Sources/AirSign/AppModel.swift` and its extensions, `airsign/Sources/AirSign/AirSignApp.swift` (the launch sweep), `airsign/Sources/AirSign/Views/*.swift` (the indicator; disabled controls)
- Modify: `README.md` (the count; one sentence where the README says how locking behaves, if it says anything that is no longer true)

**Interfaces:**
- Produces, in `AirSignCore`:

```swift
/// What can be asked of the app. While a file operation runs, only an open request (it waits) and quitting are accepted.
public enum AppAction: CaseIterable {
    case openRequest, quit
    case signatureTry, recoveryCodeTry, enrollmentStep, changeSignature, reset, forgetPairedMacs,
         setDemoMode, addSample, removeSamples, cancel, retryLaunch, labAction
}

public enum BusyPolicy {
    public static func allows(_ action: AppAction, whileBusy: Bool) -> Bool
}

/// Open requests in arrival order. Nothing is dropped; nothing is handed out while an operation runs.
public struct OpenQueue {
    public private(set) var isBusy: Bool
    public var waitingCount: Int { get }
    public init()
    /// Returns the request when it can be handled now; nil when it was put behind the running operation.
    public mutating func receive(_ urls: [URL]) -> [URL]?
    public mutating func operationBegan()
    public mutating func operationEnded()
    /// The oldest waiting request, or nil while an operation runs or when nothing waits.
    public mutating func next() -> [URL]?
}
```

- Changes, in `AirSignCore`: the two functions of `UnlockAttempt` (Task 2) become `async`, and their `openFiles` closures are `async` (`signature` stays `rethrows`). Their tests gain `await` and keep every assertion.
- Produces, in the app: `actor FileWorker` with `func lock(...) -> LockOutcome`, `func unlock(_ urls: [URL], keys: UnlockKeys) -> UnlockOutcome`, `func unlock(_ urls: [URL], recoveryCode: String) -> UnlockOutcome` and `func sweepTemporaryFolders()`. Each creates its own `FileLocker` and calls the library's `LockRun` / `UnlockRun` / `Scratch`. `AppModel` publishes `fileWork: String?` (the progress line; nil when idle) and `isBusy` derived from it.
- Behaviour:
  - **Start.** `AppModel` asks `OpenQueue.receive` for every `handleOpen`. A request it gets back is routed as now. Starting a lock, or the file part of an unlock, calls `operationBegan()`, sets the progress line ("Locking 3 items…", "Unlocking 2 items…"; "1 item" in the singular) and awaits the worker.
  - **Meanwhile.** Every entry point of `AppModel` other than `handleOpen` asks `BusyPolicy` first; a refused action shows one plain line saying that AirSign is still working on the files (wording yours, in the tone of the other messages) and does nothing else. Controls for those actions are also disabled while busy. Samples keep arriving but no capture can be running: a capture is stopped before file work begins, as `beginUnlock` and the end of a signature already do.
  - **End.** The result is applied and reported exactly as now (same lines, same tone, same Finder reveal, `pendingUnlock = outcome.wrongKey`), the progress line clears, `operationEnded()` is called, and then `next()` is taken and handled until it gives nil. Handling one may start a new operation, after which `next()` gives nil until that one ends.
  - **A try and its files.** The list a try opens is the waiting list as it was when the try's file work began. Items that arrive later wait in the queue and, when their turn comes, replace the waiting list and show the unlock screen, as an arrival does now.
  - **Counting.** `UnlockAttempt.signature` and `UnlockAttempt.recoveryCode` from Task 2 are used as they are, with `openFiles` now awaiting the worker. Because every other try is refused while busy, no second try can start before the first is counted.
  - **Launch.** `Scratch.sweepTemporaryFolders()` runs through the worker, not on the main thread; the app does not wait for it.
  - **Quit** during an operation is allowed, as now.
- Keys cross to the worker inside `UnlockKeys` and as `SymmetricKey` / `Curve25519` values. If the compiler says one of these is not `Sendable` in this SDK, pass its raw bytes (`Data`) and rebuild it inside the worker; do not reach for `@unchecked Sendable`.

- [ ] **Step 1: Write the failing tests** in `FileWorkRulesTests.swift`.

```swift
@Test func whileFilesAreProcessedOnlyOpeningAndQuittingAreAccepted() {
    for action in AppAction.allCases {
        #expect(BusyPolicy.allows(action, whileBusy: false))
        #expect(BusyPolicy.allows(action, whileBusy: true) == (action == .openRequest || action == .quit))
    }
}

@Test func openRequestsWaitInOrderBehindARunningOperation() {
    let a = [URL(fileURLWithPath: "/tmp/a.airsign")], b = [URL(fileURLWithPath: "/tmp/b.txt")], c = [URL(fileURLWithPath: "/tmp/c.airsign")]
    var queue = OpenQueue()
    #expect(queue.receive(a) == a && queue.waitingCount == 0)        // idle: handled now
    queue.operationBegan()
    #expect(queue.receive(b) == nil && queue.receive(c) == nil)      // busy: they wait
    #expect(queue.waitingCount == 2 && queue.next() == nil)          // nothing is handed out while busy
    queue.operationEnded()
    #expect(queue.next() == b)
    queue.operationBegan()                                           // handling b started a lock
    #expect(queue.next() == nil && queue.waitingCount == 1)
    queue.operationEnded()
    #expect(queue.next() == c && queue.next() == nil && queue.waitingCount == 0)
}

@Test func aRequestThatArrivesWhileOthersWaitGoesBehindThem() {
    let a = [URL(fileURLWithPath: "/tmp/a.txt")], b = [URL(fileURLWithPath: "/tmp/b.txt")]
    var queue = OpenQueue()
    queue.operationBegan(); _ = queue.receive(a); queue.operationEnded()
    #expect(queue.receive(b) == nil)          // a is still waiting, so b may not jump ahead
    #expect(queue.next() == a && queue.next() == b)
}
```

- [ ] **Step 2: See them fail.**

Run: `cd airsign && swift test --filter FileWorkRules 2>&1 | tail -5`
Expected: FAIL to compile: the types do not exist.

- [ ] **Step 3: Write `BusyPolicy` and `OpenQueue`**, then run the tests: PASS.

- [ ] **Step 4: Write `FileWorker` and move the file work behind it**, following "Behaviour" above. The indicator is a small `ProgressView` beside the message, shown while `fileWork` is set; it follows the style of the screens it sits in.

- [ ] **Step 5: Disable what is refused.** While busy: the capture button, "Use recovery code…", "Cancel", "Done", "Start over", "I wrote it down", "Add this signature to my enrollment", every control in Settings, "Try again", "Reset AirSign…" and the lab's controls are disabled. "Lock a file…", "Unlock a file…", "Unlock with the recovery code…" and "Quit" stay enabled.

- [ ] **Step 6: Update the count and verify.**

Run: `airsign/scripts/check.sh && grep -rn 'FileLocker()' airsign/Sources/AirSign | grep -v FileWorker.swift; grep -rn 'sweepTemporaryFolders' airsign/Sources/AirSign`
Expected: `All checks passed.`; the first `grep` prints nothing (file work happens only in the worker); the second shows the call only inside `FileWorker.swift` and its one caller at launch.

- [ ] **Step 7: Commit.**

```bash
git add -A airsign/Sources airsign/Tests README.md
git commit -m "refactor: run file work off the main thread, one operation at a time"
```

---

### Task 6: Documents

**Files:**
- Modify: `CONTRIBUTING.md` (the table of folders: what `AirSignCore` and `AirSign` now hold), `README.md` ("Under the hood", if a sentence there is no longer true)

- [ ] **Step 1: Update the two descriptions.** `AirSignCore`: the matcher, crypto, file format, lockout, and the rules for attempts, enrollment and file work, all tested. `AirSign`: the SwiftUI app, which asks those rules and holds the screens, the AirPods input, the Keychain and the background file worker. Say nothing that the code does not do.

- [ ] **Step 2: Verify.**

Run: `airsign/scripts/check.sh`
Expected: `All checks passed.`

- [ ] **Step 3: Commit.**

```bash
git add CONTRIBUTING.md README.md
git commit -m "docs: say where the rules live and that file work runs in the background"
```

---

## After the tasks (the controller)

1. Whole-branch review against the spec, the table of rules and this plan's Review Focus; one fix pass; scoped re-review.
2. `airsign/scripts/check.sh --with-test-volume` on the final tree; the private whole-word scan for testers' names.
3. Push `refactor/rules-into-core` and open the pull request. Its description has the table of rules with, for each, the test that pins it.
4. CI green on the pull request.
5. The maintainer's three hand checks from the spec, on their Mac with AirPods, before the merge.

## Amendments made during execution

- **Task 4, setters.** Swift does not let an extension in another file assign a `private(set)` property, so the published state that the new files assign has internal setters. The plan first said `private(set)` would stay; the text of Task 4 above is the corrected one.
- **Tasks 2 and 5, `UnlockAttempt`.** The interface in Task 2 (two functions taking an `openFiles` closure, made `async` in Task 5) was replaced after Task 5, because an `async` function forced the app to start file work, show the progress line and defer the count for every signature try, accepted or not. `UnlockAttempt` is now two synchronous decisions: `signature(_ verdict:, count:) -> SignatureDecision` (`.notCounted`, `.rejected`, `.countNotSaved`, `.openFiles`) and `recoveryCode(_ outcome:, count:) -> RecoveryDecision` (`.counted`, `.countNotSaved`). `.openFiles` exists only after an accepted try whose count was saved, so no file can be opened before the try is counted, and the count happens in the same main-actor turn as the verification, as before this branch. A try that opens nothing never starts file work.
