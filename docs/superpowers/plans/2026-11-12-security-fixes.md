# Security Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the six weaknesses from the 2026-11-09 review before the first release: plaintext leftovers, key loss after an unreadable profile, a lockout that a clock change ends, research features in the installed app, and pairing missing from the security model.

**Architecture:** The rules live in `AirSignCore`, each with a test written first: a `Scratch` helper for hidden partials and scratch folders, boot-relative lockout timing, and a `ProfileStore` that never creates a key by reading it and reports a launch state. The app then shows a blocking screen for the blocked state, and compiles the test lab, probe and Keychain self-test only when `AIRSIGN_LAB` is defined. Documentation comes last, when the behaviour it describes exists.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, Swift Package Manager, Swift Testing (`@Test`, `#expect`), CryptoKit, SwiftUI/AppKit, bash.

**Spec:** `docs/superpowers/specs/2026-11-12-security-fixes-design.md`

## Global Constraints

- Branch `fix/security-fixes`. All Swift commands run from `airsign/`.
- Do not change: the `.airsign` magic `AIRSIGN1`, the HPKE info string `airsign-file-v1`, the HKDF salt in `RecoveryCode.swift`, the Keychain service `com.makeuc.airsign` or its account names (`profile-key`, `master-key`, `paired-recovery-keys`, `lockout`, `selftest`), the bundle id, or how the profile is encrypted.
- A profile written by this branch must load at 5ca039a and the reverse: new JSON fields are optional.
- TDD: every behaviour change in `AirSignCore` has a test that fails first. Run it and read the failure before implementing.
- `swift build` and `swift build -c release` print no `warning:` line. `swift test` passes (62 tests at the start; three in `LockoutAndProfileTests.swift` are rewritten in Task 3).
- No test, check or script touches the real Keychain items under `com.makeuc.airsign` or the real `~/Library/Application Support/AirSign`. Tests use `InMemorySecretStore` and folders under the temporary directory. Nobody launches the built app from a script.
- Never open or print `.local/recovery-code.txt`. No real tester names in tracked files.
- English for all new text. Commit prefixes `fix:`, `test:`, `docs:`, `chore:`; no attribution lines.
- Pushing, opening the PR and merging each need the maintainer's OK at that moment.
- `AppModel.swift` is already 804 lines; this plan adds to it. Splitting it is sub-project C.
- Inside a sandbox that already confines the process, SwiftPM needs `--disable-sandbox` (`swift build --disable-sandbox`, `swift test --disable-sandbox`).

## Plan decisions beyond the spec

- **Lab sandbox (new, Task 5).** A lab build started with `AIRSIGN_SANDBOX=<folder>` keeps `profile.bin` in that folder and uses the Keychain service `com.makeuc.airsign.sandbox`. Without it nobody can try the blocking screen or Reset by hand without risking a real profile.
- **Binary check (changed, Task 5).** The spec checks the three flag names with `strings`. Swift stores literals of 15 bytes or fewer inline, so `--probe` and `--test-mode` never show up. The check uses three longer literals that exist only in lab code.

## Review Focus

1. **Restoring into a folder that can't be written.** The hidden partial can't be created; the user expects a clear error, the locked file untouched, nothing left behind. Pinned in Task 1 (`unlockIntoAReadOnlyFolderFailsCleanly`).
2. **A reset that fails half-way.** Keys are replaced before `profile.bin`; a failure in between must leave the app blocked (never "first run") and a second reset must work. Pinned in Task 3 (`aResetThatFailsHalfWayCanBeRunAgain`).
3. **A real install with no `lockout` Keychain item.** A profile last saved before the Keychain copy existed gets a 4-hour lockout on first launch. No test can see a real install; the reviewer weighs it and the maintainer checks their own Mac first (Task 7).
4. **Sleep.** A Mac that sleeps through a cooldown must wake unlocked: `BootClock.current()` must use a clock that counts sleep. Not unit-testable; the reviewer checks the clock id in Task 2.
5. **Two AirSign processes in one folder** (an installed app and a lab build): one's unlock sweeps the other's in-flight partial. Not tested; the reviewer checks the failure is an error, never a truncated file under the real name.

---

### Task 1: All-or-nothing restore and leftover sweep

**Files:**
- Create: `airsign/Sources/AirSignCore/Scratch.swift`
- Modify: `airsign/Sources/AirSignCore/FileLocker.swift` (`init`, `unlock`), `airsign/Sources/AirSignCore/FolderArchive.swift` (`zip`, `unzip`, `scratchDirectory`), `airsign/Sources/AirSign/AirSignApp.swift` (`applicationDidFinishLaunching`)
- Test: create `airsign/Tests/AirSignCoreTests/ScratchTests.swift`; modify `airsign/Tests/AirSignCoreTests/FileLockerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:

```swift
public enum Scratch {
    static let temporaryPrefix = "airsign-scratch-"
    static let partialPrefix = ".airsign-partial-"
    /// Creates `<base>/airsign-scratch-<UUID>` with permissions 0700.
    static func makeTemporaryFolder(in base: URL = FileManager.default.temporaryDirectory) throws -> URL
    /// `<folder>/.airsign-partial-<UUID>`. Creates nothing.
    static func partialURL(in folder: URL) -> URL
    /// Removes items in `base` named exactly `airsign-scratch-<UUID>`; returns how many.
    @discardableResult public static func sweepTemporaryFolders(in base: URL = FileManager.default.temporaryDirectory) -> Int
    /// Removes items in `folder` named exactly `.airsign-partial-<UUID>`; returns how many.
    @discardableResult static func sweepPartials(in folder: URL) -> Int
}

// FileLocker: the existing public init stays; this internal one adds a test hook.
init(trash: @escaping (URL) throws -> Void, willPublish: @escaping (_ source: URL, _ target: URL) throws -> Void)
```

A name matches a sweep only when what follows the prefix parses with `UUID(uuidString:)`.

- [ ] **Step 1: Write the failing tests**

`ScratchTests.swift`:

```swift
import Foundation
import Testing
@testable import AirSignCore

@Test func sweepRemovesOnlyAirSignScratchFolders() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    let mine = try Scratch.makeTemporaryFolder(in: base)
    try Data("zip".utf8).write(to: mine.appendingPathComponent("folder.zip"))
    let others = ["airsign-venv", "airsign-scratch-not-a-uuid", "airsign-\(UUID().uuidString)", "other"]
    for name in others { try fm.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: false) }
    #expect(mine.lastPathComponent.hasPrefix("airsign-scratch-"))
    #expect((try fm.attributesOfItem(atPath: mine.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    #expect(Scratch.sweepTemporaryFolders(in: base) == 1)
    #expect(try fm.contentsOfDirectory(atPath: base.path).sorted() == others.sorted())
}
```

In `FileLockerTests.swift`, give `Fixture` a `trash` property holding the closure `locker` now builds inline (so tests can build their own `FileLocker`), then add:

```swift
private func partials(in dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(".airsign-partial-") }
}
private struct Stop: Error {}

@Test func restoredFileAppearsUnderItsNameOnlyWhenComplete() throws {
    let f = Fixture(), fm = FileManager.default
    let locked = try f.locker.lock(f.file("a.txt", "alpha"), masterKey: f.master, recoveryPublicKey: f.pub)
    var seen = 0
    let locker = FileLocker(trash: f.trash, willPublish: { source, target in
        seen += 1
        #expect(source.path.contains("/.airsign-partial-"))
        #expect(source.deletingLastPathComponent().path == target.deletingLastPathComponent().path)
        #expect((try? String(contentsOf: source, encoding: .utf8)) == "alpha")
        #expect(!fm.fileExists(atPath: target.path))
    })
    let restored = try locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) }
    #expect(seen == 1 && restored.lastPathComponent == "a.txt")
    #expect(try String(contentsOf: restored, encoding: .utf8) == "alpha")
    #expect(partials(in: f.dir).isEmpty)
}

@Test func aRestoreThatFailsBeforePublishingLeavesNothingBehind() throws {
    let f = Fixture(), fm = FileManager.default
    let lockedFile = try f.locker.lock(f.file("a.txt", "alpha"), masterKey: f.master, recoveryPublicKey: f.pub)
    let folder = f.dir.appendingPathComponent("Docs")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("beta".utf8).write(to: folder.appendingPathComponent("b.txt"))
    let lockedFolder = try f.locker.lock(folder, masterKey: f.master, recoveryPublicKey: f.pub)
    let locker = FileLocker(trash: f.trash, willPublish: { _, _ in throw Stop() })
    for locked in [lockedFile, lockedFolder] {
        #expect(throws: (any Error).self) { try locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) } }
        #expect(fm.fileExists(atPath: locked.path))
    }
    #expect(partials(in: f.dir).isEmpty)
    #expect(!fm.fileExists(atPath: f.dir.appendingPathComponent("a.txt").path))
    #expect(!fm.fileExists(atPath: folder.path))
}

@Test func unlockRemovesLeftoverPartialsFromAnEarlierCrash() throws {
    let f = Fixture(), fm = FileManager.default
    let staleFile = f.dir.appendingPathComponent(".airsign-partial-\(UUID().uuidString)")
    let staleDir = f.dir.appendingPathComponent(".airsign-partial-\(UUID().uuidString)")
    try Data("half".utf8).write(to: staleFile)
    try fm.createDirectory(at: staleDir.appendingPathComponent("out"), withIntermediateDirectories: true)
    let keep = [".airsign-partial-notes", ".hidden"]
    for name in keep { try Data().write(to: f.dir.appendingPathComponent(name)) }
    let locked = try f.locker.lock(f.file("a.txt", "alpha"), masterKey: f.master, recoveryPublicKey: f.pub)
    _ = try f.locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) }
    #expect(!fm.fileExists(atPath: staleFile.path) && !fm.fileExists(atPath: staleDir.path))
    for name in keep { #expect(fm.fileExists(atPath: f.dir.appendingPathComponent(name).path)) }
}

@Test func unlockIntoAReadOnlyFolderFailsCleanly() throws {
    let f = Fixture(), fm = FileManager.default
    let locked = try f.locker.lock(f.file("a.txt", "alpha"), masterKey: f.master, recoveryPublicKey: f.pub)
    let before = try fm.contentsOfDirectory(atPath: f.dir.path).sorted()
    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: f.dir.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.dir.path) }
    #expect(throws: FileLockerError.self) { try f.locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) } }
    #expect(try fm.contentsOfDirectory(atPath: f.dir.path).sorted() == before)
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `swift test 2>&1 | tail -15`
Expected: the build fails: `cannot find 'Scratch' in scope` and `extra argument 'willPublish' in call`.

- [ ] **Step 3: Implement**

- `Scratch.swift` as in Interfaces.
- `FileLocker.unlock`: first `Scratch.sweepPartials(in:)` for the locked file's folder. A file's plaintext is written to `Scratch.partialURL(in:)`, then `willPublish(partial, target)` runs, then `FileManager.moveItem` moves it to `target` (it throws when `target` exists, so nothing is overwritten). Any failure after the partial exists removes the partial. The public `init(trash:)` passes a `willPublish` that does nothing.
- `FolderArchive.unzip(_:to:willPublish:)`: its work folder is `Scratch.partialURL(in:)` next to `target`, created 0700; the zip and the unpacked tree go inside it; `willPublish(unpackedFolder, target)` runs before the move; the work folder is removed on every path. The item-replacement folder is no longer used.
- `FolderArchive.zip`: its work folder comes from `Scratch.makeTemporaryFolder()`. Delete `scratchDirectory`.
- `AppDelegate.applicationDidFinishLaunching`: first statement `Scratch.sweepTemporaryFolders()`.

- [ ] **Step 4: Run the tests and the builds**

Run: `swift test 2>&1 | tail -3 && swift build 2>&1 | grep -c "warning:"; swift build -c release 2>&1 | grep -c "warning:"`
Expected: `Test run with 67 tests in 0 suites passed`, then `0` and `0`.

- [ ] **Step 5: Commit**

```bash
git add airsign/Sources/AirSignCore/Scratch.swift airsign/Sources/AirSignCore/FileLocker.swift airsign/Sources/AirSignCore/FolderArchive.swift airsign/Sources/AirSign/AirSignApp.swift airsign/Tests/AirSignCoreTests/ScratchTests.swift airsign/Tests/AirSignCoreTests/FileLockerTests.swift
git commit -m "fix: restore files all-or-nothing and sweep leftover scratch folders"
```

---

### Task 2: Lockout cooldown follows uptime within a boot

**Files:**
- Create: `airsign/Sources/AirSignCore/BootClock.swift`
- Modify: `airsign/Sources/AirSignCore/Lockout.swift`, `airsign/Sources/AirSign/AppModel.swift` (every `lockout.remaining(now:` and the `apply` in `adjustLockout`)
- Test: `airsign/Tests/AirSignCoreTests/LockoutAndProfileTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:

```swift
public struct BootClock: Equatable, Sendable {
    public var session: String        // sysctl kern.bootsessionuuid
    public var uptime: TimeInterval   // seconds since boot, counting sleep
    public init(session: String, uptime: TimeInterval)
    /// nil when the system reports no boot session.
    public static func current() -> BootClock?
}

// Lockout: the three existing methods gain `boot`, and one factory is new.
public mutating func recordFailure(now: Date, boot: BootClock? = nil)
public func remaining(now: Date, boot: BootClock? = nil) -> TimeInterval?
public mutating func apply(_ effect: Effect, now: Date, boot: BootClock? = nil)
/// The longest cooldown (14400 s), started now; `lockCount == cooldowns.count`, `failures == 0`.
public static func tampered(now: Date, boot: BootClock?) -> Lockout
```

New stored fields, `public private(set)`, optional in JSON (`decodeIfPresent`): `lockedFor: TimeInterval?` (the cooldown's length), `lockedBootSession: String?`, `lockedUptime: TimeInterval?`.

The rule for `remaining`:
1. `lockedUntil == nil` gives nil.
2. When `lockedFor`, `lockedBootSession` and `lockedUptime` are all set and `boot?.session == lockedBootSession`: `lockedFor - (boot.uptime - lockedUptime)`. The wall clock is ignored.
3. Otherwise `lockedUntil - now`, and no more than `lockedFor` when it is set.
4. A result of 0 or less is nil.

`recordFailure` clears an ended lockout by that same rule, sets all four lock fields when it locks (the boot fields only when `boot` is given) and `recordSuccess` clears all four. `mostRestrictive` takes all four lock fields from the copy with the later `lockedUntil`.

- [ ] **Step 1: Write the failing tests** (append to `LockoutAndProfileTests.swift`)

```swift
private let bootA = BootClock(session: "A", uptime: 1000)
private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func locked(at time: Date, boot: BootClock?) -> Lockout {
    var l = Lockout()
    for _ in 0..<5 { l.recordFailure(now: time, boot: boot) }
    return l
}

@Test func changingTheClockWithinOneBootDoesNotMoveTheCooldown() {
    let l = locked(at: t0, boot: bootA)
    let tenSecondsOn = BootClock(session: "A", uptime: 1010)
    #expect(l.remaining(now: t0.addingTimeInterval(10), boot: tenSecondsOn) == 290)
    #expect(l.remaining(now: t0.addingTimeInterval(86_400), boot: tenSecondsOn) == 290)    // clock set forward
    #expect(l.remaining(now: t0.addingTimeInterval(-86_400), boot: tenSecondsOn) == 290)   // clock set back
    #expect(l.remaining(now: t0.addingTimeInterval(-86_400), boot: BootClock(session: "A", uptime: 1300)) == nil)
}

@Test func afterARestartTheWallClockDecidesCappedAtTheCooldown() {
    let l = locked(at: t0, boot: bootA)
    let restarted = BootClock(session: "B", uptime: 5)
    #expect(l.remaining(now: t0.addingTimeInterval(100), boot: restarted) == 200)
    #expect(l.remaining(now: t0.addingTimeInterval(-86_400), boot: restarted) == 300)
    #expect(l.remaining(now: t0.addingTimeInterval(300), boot: restarted) == nil)
    #expect(l.remaining(now: t0.addingTimeInterval(100)) == 200)
}

@Test func aFailureAfterTheCooldownCountsFromOneWhateverTheClockSays() {
    var l = locked(at: t0, boot: bootA)
    l.recordFailure(now: t0.addingTimeInterval(-86_400), boot: BootClock(session: "A", uptime: 1301))
    #expect(l.failures == 1 && l.lockedUntil == nil && l.lockedFor == nil && l.lockedBootSession == nil && l.lockedUptime == nil)
}

@Test func lockoutsSavedBeforeBootTrackingUseTheWallClock() throws {
    let l = try JSONDecoder().decode(Lockout.self, from: Data(#"{"failures":0,"lockCount":1,"lockedUntil":1000}"#.utf8))
    #expect(l.remaining(now: Date(timeIntervalSinceReferenceDate: 900), boot: bootA) == 100)
}

@Test func lockoutRoundTripsThroughJSONWithItsBootFields() throws {
    let l = locked(at: t0, boot: bootA)
    #expect(try JSONDecoder().decode(Lockout.self, from: JSONEncoder().encode(l)) == l)
    #expect(l.lockedFor == 300 && l.lockedBootSession == "A" && l.lockedUptime == 1000)
}

@Test func mergingKeepsTheWholeLaterLockout() {
    let earlier = locked(at: t0, boot: bootA)
    let later = locked(at: t0.addingTimeInterval(60), boot: BootClock(session: "A", uptime: 1060))
    let now = BootClock(session: "A", uptime: 1070)
    for merged in [Lockout.mostRestrictive(earlier, later), .mostRestrictive(later, earlier), .mostRestrictive(later, Lockout())] {
        #expect(merged.remaining(now: t0, boot: now) == 290)
    }
}

@Test func aTamperedLockoutIsTheLongestCooldown() {
    let l = Lockout.tampered(now: t0, boot: bootA)
    #expect(l.remaining(now: t0, boot: bootA) == 14_400)
    #expect(l.lockCount == Lockout.cooldowns.count && l.failures == 0)
}

@Test func theBootClockReadsTheSameSessionAndNeverGoesBack() throws {
    let first = try #require(BootClock.current()), second = try #require(BootClock.current())
    #expect(!first.session.isEmpty && first.session == second.session && second.uptime >= first.uptime)
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `swift test 2>&1 | tail -15`
Expected: the build fails: `cannot find 'BootClock' in scope`.

- [ ] **Step 3: Implement** `BootClock` and the `Lockout` changes as in Interfaces. `BootClock.current()` reads `kern.bootsessionuuid` with `sysctlbyname` and the uptime from `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` (it keeps counting during sleep; `CLOCK_UPTIME_RAW` does not).

- [ ] **Step 4: Use it in the app.** In `AppModel.swift` every `lockout.remaining(now: Date())` becomes `lockout.remaining(now: Date(), boot: BootClock.current())` and `adjustLockout` calls `apply(effect, now: Date(), boot: BootClock.current())`.

Run: `grep -n -E "remaining\(now: Date\(\)\)|apply\(effect, now: Date\(\)\)" Sources/AirSign/AppModel.swift`
Expected: no output.

- [ ] **Step 5: Run the tests and the builds**

Run: `swift test 2>&1 | tail -3 && swift build 2>&1 | grep -c "warning:"; swift build -c release 2>&1 | grep -c "warning:"`
Expected: `Test run with 75 tests in 0 suites passed`, then `0` and `0`.

- [ ] **Step 6: Commit**

```bash
git add airsign/Sources/AirSignCore/BootClock.swift airsign/Sources/AirSignCore/Lockout.swift airsign/Sources/AirSign/AppModel.swift airsign/Tests/AirSignCoreTests/LockoutAndProfileTests.swift
git commit -m "fix: lockout cooldown follows uptime within a boot, not the wall clock"
```

---

### Task 3: Reading never creates a key; launch state; missing lockout copy fails closed

**Files:**
- Modify: `airsign/Sources/AirSignCore/ProfileStore.swift`
- Test: `airsign/Tests/AirSignCoreTests/LockoutAndProfileTests.swift`, `airsign/Tests/AirSignCoreTests/Support.swift`

**Interfaces:**
- Consumes: `BootClock`, `Lockout.tampered(now:boot:)`, `Lockout.mostRestrictive` from Task 2.
- Produces:

```swift
public enum ProfileStoreError: Error, Equatable {
    case keyMissing(String)   // the secret's name: "profile-key" or "master-key"
    case profileExists
}
public enum BlockReason: Equatable { case keyMissing, profileUnreadable, storeError }
public enum LaunchState: Equatable {
    case noProfile, ready(Profile), blocked(BlockReason)
    public var allowsEnrollment: Bool   // .noProfile only
    public var allowsLocking: Bool      // .ready only
}

// ProfileStore
public func load(now: Date = Date(), boot: BootClock? = BootClock.current()) throws -> Profile?
public func launchState(now: Date = Date(), boot: BootClock? = BootClock.current()) -> LaunchState
public func createProfile(_ profile: Profile, replacingExisting: Bool = false) throws
public func masterKey() throws -> SymmetricKey   // ProfileStoreError.keyMissing("master-key") when absent
```

Rules:
- The private `key(_:)` throws `keyMissing(name)` when the store has no such item and never saves. So `save` throws `keyMissing("profile-key")` before any profile was created.
- `createProfile`: when `profile.bin` exists and `replacingExisting` is false, throw `profileExists` before touching anything. Otherwise delete and then save fresh random 256-bit `master-key` and `profile-key`, delete `paired-recovery-keys` and `lockout`, then `save(profile)`.
- `load`: when `profile.bin` decrypts and the store has no `lockout` item, set `profile.lockout = Lockout.mostRestrictive(profile.lockout, .tampered(now: now, boot: boot))`, `save` it, and return it.
- `launchState`: no `profile.bin` gives `.noProfile`. Otherwise: the secret store throws gives `.blocked(.storeError)`; either key absent gives `.blocked(.keyMissing)`; `profile.bin` can't be read, decrypted or decoded gives `.blocked(.profileUnreadable)`; else `.ready(profile)`. It never throws and never creates a key.

- [ ] **Step 1: Add test support** (`Support.swift`)

```swift
/// Reads of the listed names fail until that name is deleted; saves of the listed names always fail.
final class FailingSecretStore: SecretStore {
    struct Denied: Error {}
    let inner = InMemorySecretStore()
    var failingLoads: Set<String> = []
    var failingSaves: Set<String> = []
    func load(_ name: String) throws -> Data? {
        if failingLoads.contains(name) { throw Denied() }
        return try inner.load(name)
    }
    func save(_ data: Data, as name: String) throws {
        if failingSaves.contains(name) { throw Denied() }
        try inner.save(data, as: name)
    }
    func delete(_ name: String) throws {
        failingLoads.remove(name)
        try inner.delete(name)
    }
}

func tempDir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

func testProfile(_ deviceUID: String = "UID-A") throws -> Profile {
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.2)) }, deviceUID: deviceUID)
    return Profile(enrollment: e, recoveryPublicKey: Data(repeating: 7, count: 32), lockout: Lockout(), demoMode: false)
}
```

- [ ] **Step 2: Write the failing tests** (append to `LockoutAndProfileTests.swift`)

```swift
@Test func readingAMissingKeyThrowsAndCreatesNothing() throws {
    let secrets = InMemorySecretStore()
    let store = ProfileStore(directory: tempDir(), secrets: secrets)
    #expect(throws: ProfileStoreError.keyMissing("master-key")) { try store.masterKey() }
    #expect(throws: ProfileStoreError.keyMissing("profile-key")) { try store.save(testProfile()) }
    #expect(try secrets.load("master-key") == nil && secrets.load("profile-key") == nil)
}

@Test func launchStateTellsFirstRunReadyAndBlockedApart() throws {
    let dir = tempDir(), secrets = FailingSecretStore()
    let store = ProfileStore(directory: dir, secrets: secrets)
    #expect(store.launchState() == .noProfile)
    let p = try testProfile()
    try store.createProfile(p)
    #expect(store.launchState() == .ready(p))

    secrets.failingLoads = ["profile-key"]   // for example the Keychain prompt was denied
    #expect(store.launchState() == .blocked(.storeError))
    secrets.failingLoads = []

    let master = try #require(try secrets.load("master-key"))
    try secrets.inner.delete("master-key")
    #expect(store.launchState() == .blocked(.keyMissing))
    #expect(try secrets.load("master-key") == nil)   // looking never creates it
    try secrets.save(master, as: "master-key")

    let file = dir.appendingPathComponent("profile.bin")
    let good = try Data(contentsOf: file)
    try Data("garbage".utf8).write(to: file)
    #expect(store.launchState() == .blocked(.profileUnreadable))
    try good.write(to: file)
    #expect(store.launchState() == .ready(p))
}

@Test func onlyAFirstRunAllowsEnrollingAndOnlyReadyAllowsLocking() throws {
    let p = try testProfile()
    #expect(LaunchState.noProfile.allowsEnrollment && !LaunchState.noProfile.allowsLocking)
    #expect(!LaunchState.ready(p).allowsEnrollment && LaunchState.ready(p).allowsLocking)
    for reason in [BlockReason.keyMissing, .profileUnreadable, .storeError] {
        #expect(!LaunchState.blocked(reason).allowsEnrollment && !LaunchState.blocked(reason).allowsLocking)
    }
}

@Test func enrollingNeverReplacesAnExistingProfileUnlessResetting() throws {
    let secrets = InMemorySecretStore()
    let store = ProfileStore(directory: tempDir(), secrets: secrets)
    let first = try testProfile("UID-A"), second = try testProfile("UID-B")
    try store.createProfile(first)
    let master = try secrets.load("master-key")
    #expect(throws: ProfileStoreError.profileExists) { try store.createProfile(second) }
    #expect(try secrets.load("master-key") == master)
    #expect(store.launchState() == .ready(first))
    try store.createProfile(second, replacingExisting: true)
    #expect(try secrets.load("master-key") != master)
    #expect(store.launchState() == .ready(second))
}

@Test func resetWorksWhenTheOldKeysCannotBeRead() throws {
    let secrets = FailingSecretStore()
    let store = ProfileStore(directory: tempDir(), secrets: secrets)
    try store.createProfile(try testProfile("UID-A"))
    secrets.failingLoads = ["profile-key", "master-key", "paired-recovery-keys", "lockout"]
    let fresh = try testProfile("UID-B")
    try store.createProfile(fresh, replacingExisting: true)
    #expect(store.launchState() == .ready(fresh))
}

@Test func aResetThatFailsHalfWayCanBeRunAgain() throws {
    let secrets = FailingSecretStore()
    let store = ProfileStore(directory: tempDir(), secrets: secrets)
    try store.createProfile(try testProfile("UID-A"))
    secrets.failingSaves = ["profile-key"]
    let fresh = try testProfile("UID-B")
    #expect(throws: (any Error).self) { try store.createProfile(fresh, replacingExisting: true) }
    if case .blocked = store.launchState() {} else { Issue.record("a half-finished reset must leave the app blocked") }
    secrets.failingSaves = []
    try store.createProfile(fresh, replacingExisting: true)
    #expect(store.launchState() == .ready(fresh))
}

@Test func aMissingKeychainLockoutCopyStartsTheLongestCooldownOnce() throws {
    let secrets = InMemorySecretStore()
    let store = ProfileStore(directory: tempDir(), secrets: secrets)
    try store.createProfile(try testProfile())
    try secrets.delete("lockout")
    let start = Date(timeIntervalSince1970: 1_000_000), boot = BootClock(session: "A", uptime: 50)
    #expect(try store.load(now: start, boot: boot)?.lockout.remaining(now: start, boot: boot) == 14_400)
    #expect(try secrets.load("lockout") != nil)
    let later = BootClock(session: "A", uptime: 150)
    #expect(try store.load(now: start.addingTimeInterval(100), boot: later)?.lockout
        .remaining(now: start.addingTimeInterval(100), boot: later) == 14_300)
}
```

- [ ] **Step 3: Run the tests and see them fail**

Run: `swift test 2>&1 | tail -15`
Expected: the build fails: `cannot find type 'ProfileStoreError'` and `value of type 'ProfileStore' has no member 'launchState'`.

- [ ] **Step 4: Implement** the `ProfileStore` changes as in Interfaces.

- [ ] **Step 5: Rewrite the three tests that relied on a key appearing by itself**

- `restoringAnOlderProfileFileKeepsTheFailureCount`: the first `try store.save(p)` becomes `try store.createProfile(p)`.
- `creatingAProfileRotatesTheMasterKey`: start with `try store.createProfile(try testProfile("UID-A"))`, read `before = try store.masterKey()`, seal as now, remove `profile.bin` (the comment already says "after someone deleted profile.bin"), then `createProfile` the second profile. The three final expectations stay.
- `profileRoundTripsAndIsNotPlaintextOnDisk`: `try store.save(p)` becomes `try store.createProfile(p)`.

- [ ] **Step 6: Run the tests and the builds**

Run: `swift test 2>&1 | tail -3 && swift build 2>&1 | grep -c "warning:"; swift build -c release 2>&1 | grep -c "warning:"`
Expected: `Test run with 82 tests in 0 suites passed`, then `0` and `0`.

- [ ] **Step 7: Commit**

```bash
git add airsign/Sources/AirSignCore/ProfileStore.swift airsign/Tests/AirSignCoreTests/LockoutAndProfileTests.swift airsign/Tests/AirSignCoreTests/Support.swift
git commit -m "fix: never create a key by reading it; tell a blocked profile from a first run"
```

---

### Task 4: Blocking screen and Reset in the app

**Files:**
- Create: `airsign/Sources/AirSign/Views/BlockedView.swift`
- Modify: `airsign/Sources/AirSign/AppModel.swift`, `airsign/Sources/AirSign/Views/ContentView.swift`, `airsign/Sources/AirSign/Views/EnrollView.swift`

**Interfaces:**
- Consumes: `ProfileStore.launchState()`, `LaunchState`, `BlockReason`, `ProfileStoreError`, `createProfile(_:replacingExisting:)` from Task 3.
- Produces (on `AppModel`): `Screen.blocked`; `@Published private(set) var blockReason: BlockReason?`; `@Published private(set) var isResetting: Bool`; `func retryLaunch()`; `func beginReset()`.

The app target has no tests; the rules it relies on are tested in Task 3. This task is checked by the builds, the greps below and review.

- [ ] **Step 1: Launch state in `AppModel`**

- `init` switches on `store.launchState()`: `.noProfile` shows `.enroll`; `.ready(p)` sets `profile = p` and shows `.home`; `.blocked(r)` sets `blockReason = r`, shows `.blocked` and says the reason's message with tone `.bad`. The "Enroll again" message goes.
- Messages, exact copy:
  - `.storeError`: `AirSign couldn't read its keys from the Keychain. If macOS asked for permission and it was denied, choose Try again and allow it. Your locked files still open with the recovery code.`
  - `.keyMissing`: `AirSign's key is missing from the Keychain. Your locked files still open with the recovery code.`
  - `.profileUnreadable`: `AirSign's profile on this Mac can't be read. Your locked files still open with the recovery code.`
- A private computed `restingScreen`: `.blocked` when `blockReason != nil`, else `.enroll` when `profile == nil`, else `.home`. It replaces every `profile == nil ? .enroll : .home`.
- `retryLaunch()` applies `store.launchState()` again exactly as `init` does.

- [ ] **Step 2: What blocked allows**

- `lock(_:)`: when `blockReason != nil`, show `.blocked` and say `AirSign can't lock files until its profile can be read again.` (`.bad`); lock nothing.
- In `lock(_:)` and `verifyAndUnlock`, a `ProfileStoreError.keyMissing` from `store.masterKey()` sets `blockReason = .keyMissing`, shows `.blocked` and says the `.keyMissing` message.
- `beginUnlock` while blocked says `AirSign's profile can't be read. Use the recovery code.`; unlocking with the recovery code works as it does on a Mac with no profile.

- [ ] **Step 3: Reset**

- `beginReset()`: `isResetting = true`, clear any enrollment in progress, show `.enroll`, say `Sign 3 times the same way to enroll a new signature. Nothing is replaced until you confirm the new recovery code.` Nothing is deleted here.
- `confirmRecoveryCodeWritten` calls `store.createProfile(pending, replacingExisting: isResetting)`. On success `blockReason = nil` and `isResetting = false`. On failure `isResetting = false` and the screen is `restingScreen`.
- `cancelToHome` sets `isResetting = false` and shows `restingScreen`.
- `EnrollView`: the Cancel button that shows for `isReenrolling` also shows for `isResetting`; the title for a reset is `Enroll a new air signature`.

- [ ] **Step 4: `BlockedView`** in the style of `HomeView`, and `case .blocked: BlockedView()` in `ContentView`

- Title `AirSign can't read its profile`; the reason is the message `ContentView` already shows.
- Buttons, in this order: **Try again** (prominent, `retryLaunch()`); **Unlock with the recovery code…** (an `NSOpenPanel` limited to `.airsign` files, then `model.handleOpen(urls)`, as `HomeView.pick(lockedFiles: true)` does); **Reset AirSign…**; **Quit** (`NSApp.terminate(nil)`).
- **Reset AirSign…** opens a confirmation dialog: title `Reset AirSign?`, message `Files you have locked so far will open only with their recovery code, and paired Macs are forgotten. Nothing is replaced until you finish enrolling and confirm the new recovery code.`, a destructive button `Reset and enroll again` (`beginReset()`) and `Cancel`.

- [ ] **Step 5: Verify**

Run: `swift test 2>&1 | tail -1 && swift build 2>&1 | grep -c "warning:"; swift build -c release 2>&1 | grep -c "warning:"; grep -c -E "Enroll again; locked files|profile == nil \? \.enroll : \.home" Sources/AirSign/AppModel.swift`
Expected: `Test run with 82 tests in 0 suites passed`, then `0`, `0`, `0`.

- [ ] **Step 6: Commit**

```bash
git add airsign/Sources/AirSign/AppModel.swift airsign/Sources/AirSign/Views/BlockedView.swift airsign/Sources/AirSign/Views/ContentView.swift airsign/Sources/AirSign/Views/EnrollView.swift
git commit -m "fix: show a blocking screen instead of enrolling over an unreadable profile"
```

---

### Task 5: Lab build

**Files:**
- Modify: `airsign/Package.swift`, `airsign/scripts/build-app.sh`, `airsign/Sources/AirSign/AirSignApp.swift`, `airsign/Sources/AirSign/AppModel.swift`, `airsign/Sources/AirSign/ProbeMode.swift`, `airsign/Sources/AirSign/KeychainSecretStore.swift`, `airsign/Sources/AirSign/Views/TestLabView.swift`, `airsign/Sources/AirSign/Views/ContentView.swift`, `airsign/Sources/AirSign/Views/HomeView.swift`, `CONTRIBUTING.md`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the compilation condition `AIRSIGN_LAB`; `KeychainSecretStore.init(service: String = "com.makeuc.airsign")`.

- [ ] **Step 1: Define the condition**

- `Package.swift`, the `AirSign` target: `swiftSettings: [.define("AIRSIGN_LAB", .when(configuration: .debug))]`.
- `build-app.sh`: when `AIRSIGN_LAB=1`, both `swift build` calls get `-Xswiftc -DAIRSIGN_LAB`, and the last line reads `Built … (lab build, signed with: …)`. The script runs under macOS's bash 3.2 with `set -u`: expand the optional arguments as `${EXTRA[@]+"${EXTRA[@]}"}`.

- [ ] **Step 2: Compile the research features only with the condition**

- `ProbeMode.swift` and `TestLabView.swift`: the whole file inside `#if AIRSIGN_LAB`.
- `AirSignApp.swift`: the `--selftest-keychain` and `--probe` handling and `runKeychainSelfTest` inside `#if AIRSIGN_LAB`. New, also lab only: `--selftest-keychain-clean` deletes the `selftest` item, prints `CLEANED` and exits 0. The window title is `AirSign (lab build)` in a lab build and `AirSign` otherwise.
- `AppModel.swift`: `testMode` is `CommandLine.arguments.contains("--test-mode")` in a lab build and the constant `false` otherwise. Every member that exists only for the test lab (the `test…` properties, `labCounts`, `attemptLog`, `beginLab`, the methods under `// MARK: - Test lab`, `logEnrollment`) and every use of them is inside `#if AIRSIGN_LAB`. `Screen.lab` stays so the `switch` statements keep one shape; without the condition nothing sets it and `ContentView` shows `HomeView` for it.
- `ContentView.swift`, `HomeView.swift`: the banner and the "Open test lab" button inside `#if AIRSIGN_LAB`.
- `demoMode` with no profile is `false`: `profile?.demoMode ?? false`.

- [ ] **Step 3: Lab sandbox** (lab build only)

When the environment has `AIRSIGN_SANDBOX` set to a folder path, `AppModel` builds its store as `ProfileStore(directory: URL(fileURLWithPath: path), secrets: KeychainSecretStore(service: "com.makeuc.airsign.sandbox"))`, the Keychain self-test uses the same service, and the test-mode banner area shows `Sandbox data: <path>` even without `--test-mode`. Without the variable, or in a default build, the store is exactly as before.

- [ ] **Step 4: Verify both builds**

Run:

```bash
swift test 2>&1 | tail -1
swift build 2>&1 | grep -c "warning:"
BIN=build/AirSign.app/Contents/MacOS/AirSign
AIRSIGN_ADHOC=1 AIRSIGN_LAB=1 scripts/build-app.sh 2>&1 | tail -1
for p in 'selftest-keychain' 'lab build' 'Test lab open'; do strings -a "$BIN" | grep -q -- "$p" && echo "lab has: $p"; done
AIRSIGN_ADHOC=1 scripts/build-app.sh 2>&1 | tail -1
strings -a "$BIN" | grep -c -E 'selftest-keychain|lab build|Test lab open|airsign\.sandbox|AIRSIGN_SANDBOX'
swift build -c release 2>&1 | grep -c "warning:"
grep -rn -E '"--(test-mode|probe|selftest-keychain)' Sources/AirSign
```

Expected: `Test run with 82 tests in 0 suites passed`; `0`; a `Built … (lab build, …)` line; three `lab has:` lines; a `Built …` line without "lab build"; `0`; `0`; and every line the last `grep` prints sits inside an `#if AIRSIGN_LAB` block (read each one).

- [ ] **Step 5: `CONTRIBUTING.md`**, a new section `## Lab build` after "Build and test"

It says: what a lab build adds (the test lab behind `--test-mode`, `--probe`, `--selftest-keychain` and `--selftest-keychain-clean`); how to make one (`AIRSIGN_LAB=1 scripts/build-app.sh`, or `swift run`); that its window title says "lab build"; that the test lab shows scores and writes raw signature motion in plaintext to the logs folder, so it is for evaluation only, never for a Mac whose files matter, and its logs are never committed or sent with a report; how to use `AIRSIGN_SANDBOX=<folder>` to try enrollment, the blocking screen and Reset without touching a real profile; and how to remove the sandbox's Keychain items (the uninstall loop from the README with the service `com.makeuc.airsign.sandbox`).

- [ ] **Step 6: Commit**

```bash
git add airsign/Package.swift airsign/scripts/build-app.sh airsign/Sources/AirSign CONTRIBUTING.md
git commit -m "fix: compile the test lab, probe and Keychain self-test only into lab builds"
```

---

### Task 6: Security model documents

**Files:**
- Modify: `README.md`, `SECURITY.md`

**Interfaces:** consumes the behaviour of Tasks 1 to 5; produces nothing.

- [ ] **Step 1: See the gaps**

Run (from the repository root): `grep -c -i -E "pairing a second mac|roll.* back|airsign-partial" README.md SECURITY.md; grep -c "62 unit tests" README.md`
Expected: `README.md:0`, `SECURITY.md:0`, then `1`.

- [ ] **Step 2: `README.md`**

- A new section `## Pairing a second Mac` between "Quick start" and "Uninstall", with the facts: the second Mac needs its own enrolled signature; unlock one file from the first Mac there with the first Mac's recovery code and tick "Remember on this Mac"; from then on the first Mac's files open on the second Mac with that Mac's AirPods and signature; pairing is one-way; it stores the first Mac's recovery key in the second Mac's login Keychain (item `paired-recovery-keys`), so the second Mac can open everything the first Mac ever locked; Settings → "Forget paired Macs" removes it; enrolling from scratch or resetting forgets pairings too.
- Security model table: the "Uses your unlocked Mac while you're away" row's reason becomes: they must use your AirPods and match your signature; the lockout (up to 4 hours) slows them, but someone using your Mac as you can put AirSign's saved state back and try again, so it is a delay, not a wall. A new row: `Reads the Keychain of a Mac you paired | ❌ | A paired Mac keeps the other Mac's recovery key, which is as good as its recovery code`.
- "Encryption in short": add that a restart followed by a clock change also ends a cooldown, and that if AirSign is force-quit while restoring, a hidden `.airsign-partial-…` item can stay next to the locked file until AirSign next unlocks something in that folder.
- "Under the hood": the test count becomes the number `swift test` prints (82 when this plan is followed exactly).
- Add the table of contents link if the top navigation lists sections.

- [ ] **Step 3: `SECURITY.md`**, three more bullets under "Known limitations"

The lockout can be rolled back by someone who can use the Mac as the owner (copy and restore AirSign's folder and the Keychain file), and a restart plus a clock change ends a cooldown; a force-quit during a restore can leave a hidden plaintext partial next to the locked file until the next unlock in that folder; a paired Mac stores the other Mac's recovery key, so reading its Keychain equals having that recovery code.

- [ ] **Step 4: Verify**

Run: `grep -c -i -E "pairing a second mac|roll.* back|put .* back|airsign-partial" README.md SECURITY.md; grep -c "62 unit tests" README.md; git grep -n -i -w -f .local/pseudonym-names.txt -- . ':!docs/superpowers' | wc -l`
Expected: both files at 2 or more; `0`; `0`. Every relative link added resolves (open each target).

- [ ] **Step 5: Commit**

```bash
git add README.md SECURITY.md
git commit -m "docs: pairing, lockout rollback and restore leftovers in the security model"
```

---

### Task 7: Whole-branch check and hand-over

**Files:** none.

- [ ] **Step 1: Full verification from a clean build**

Run (from `airsign/`): `rm -rf .build && swift test 2>&1 | tail -1 && swift build 2>&1 | grep -c "warning:"; swift build -c release 2>&1 | grep -c "warning:"; cd .. && git grep -n -E '/Users/|C:/airsign-data' -- ':!docs/superpowers' | wc -l && git status --short | wc -l`
Expected: `Test run with 82 tests in 0 suites passed`, `0`, `0`, `0`, `0`.

- [ ] **Step 2: Whole-branch review** by a fresh reviewer against the spec, this plan and its Review Focus; fix Critical and Important findings test-first.

- [ ] **Step 3: Give the maintainer the hand checks** (their Mac, their AirPods)

1. Before installing: `security find-generic-password -s com.makeuc.airsign -a lockout` finds an item. If it does not, the first launch starts a 4-hour lockout by design: unlock once with the current build first.
2. Default build (`scripts/install.sh`): lock and unlock a file and a folder; sign wrong once; the lockout message counts down; `open -a AirSign --args --test-mode` shows no banner and no test-lab button.
3. Lab build with a sandbox (`AIRSIGN_LAB=1 scripts/build-app.sh`, then `AIRSIGN_SANDBOX=/tmp/airsign-sandbox build/AirSign.app/Contents/MacOS/AirSign`): enroll; quit; overwrite `/tmp/airsign-sandbox/profile.bin` with junk; start again and see the blocking screen; Try again stays blocked; Reset, cancel half-way and see the blocking screen again; Reset fully and reach the home screen. Then remove the sandbox Keychain items as CONTRIBUTING.md says.

- [ ] **Step 4: Ask the maintainer** whether to push and open the PR.
