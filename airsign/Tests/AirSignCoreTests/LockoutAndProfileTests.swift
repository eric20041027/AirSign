import CryptoKit
import Foundation
import Testing
@testable import AirSignCore

@Test func fiveFailuresLockForFiveMinutesThenExpire() {
    var l = Lockout()
    let t0 = Date(timeIntervalSince1970: 0)
    for i in 0..<4 { l.recordFailure(now: t0.addingTimeInterval(Double(i))) }
    #expect(l.remaining(now: t0.addingTimeInterval(4)) == nil)
    l.recordFailure(now: t0.addingTimeInterval(4))
    #expect(l.remaining(now: t0.addingTimeInterval(5)) == 299)
    #expect(l.remaining(now: t0.addingTimeInterval(305)) == nil)
}

@Test func repeatedLockoutsLastLongerUntilASuccess() {
    var l = Lockout()
    var t = Date(timeIntervalSince1970: 0)
    let lockOnce = { for _ in 0..<5 { l.recordFailure(now: t) } }
    lockOnce()
    #expect(l.remaining(now: t) == 300)
    t = t.addingTimeInterval(301)
    lockOnce()
    #expect(l.remaining(now: t) == 900)
    t = t.addingTimeInterval(901)
    lockOnce()
    #expect(l.remaining(now: t) == 3600)
    t = t.addingTimeInterval(3601)
    lockOnce()
    #expect(l.remaining(now: t) == 14400)
    t = t.addingTimeInterval(14401)
    lockOnce()
    #expect(l.remaining(now: t) == 14400)
    l.recordSuccess()
    lockOnce()
    #expect(l.remaining(now: t) == 300)
}

@Test func lockoutDecodesProfilesSavedBeforeEscalation() throws {
    let l = try JSONDecoder().decode(Lockout.self, from: Data(#"{"failures":3}"#.utf8))
    #expect(l.failures == 3 && l.lockedUntil == nil && l.lockCount == 0)
}

@Test func restoringAnOlderProfileFileKeepsTheFailureCount() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ProfileStore(directory: dir, secrets: InMemorySecretStore())
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.2)) }, deviceUID: "UID-A")
    var p = Profile(enrollment: e, recoveryPublicKey: Data(repeating: 3, count: 32), lockout: Lockout(), demoMode: false)
    try store.createProfile(p)
    let file = dir.appendingPathComponent("profile.bin")
    let snapshot = try Data(contentsOf: file)
    for _ in 0..<4 { p.lockout.recordFailure(now: Date()) }
    try store.save(p)
    try snapshot.write(to: file)   // someone puts the old copy back to reset the count
    #expect(try store.load()?.lockout.failures == 4)
}

@Test func successResetsFailures() {
    var l = Lockout()
    for _ in 0..<4 { l.recordFailure(now: Date()) }
    l.recordSuccess()
    l.recordFailure(now: Date())
    #expect(l.failures == 1 && l.lockedUntil == nil)
}

@Test func recoveryAttemptsOnlyCountWhenAFileWasJudged() {
    #expect(Lockout.recoveryEffect(restored: 0, wrongKey: 0) == .none)   // only junk or unreadable files
    #expect(Lockout.recoveryEffect(restored: 2, wrongKey: 0) == .success)
    #expect(Lockout.recoveryEffect(restored: 1, wrongKey: 1) == .failure)
    #expect(Lockout.recoveryEffect(restored: 0, wrongKey: 1) == .failure)
}

@Test func applyingNoneLeavesTheCountAlone() {
    var l = Lockout()
    l.recordFailure(now: Date())
    l.apply(.none, now: Date())
    #expect(l.failures == 1)
    l.apply(.failure, now: Date())
    #expect(l.failures == 2)
    l.apply(.success, now: Date())
    #expect(l.failures == 0)
}

@Test func creatingAProfileRotatesTheMasterKey() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ProfileStore(directory: dir, secrets: InMemorySecretStore())
    try store.createProfile(try testProfile("UID-A"))
    let before = try store.masterKey()
    let code = RecoveryCode.generate()
    let pub = try RecoveryCode.privateKey(for: code).publicKey
    let sealed = try LockedFile.seal(Data("owner".utf8), originalName: "a.txt", masterKey: before, recoveryPublicKey: pub)
    try FileManager.default.removeItem(at: dir.appendingPathComponent("profile.bin"))
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.2)) }, deviceUID: "UID-B")
    try store.createProfile(Profile(enrollment: e, recoveryPublicKey: Data(repeating: 1, count: 32), lockout: Lockout(), demoMode: false))
    // A fresh enrollment (for example after someone deleted profile.bin) must not inherit the old master key.
    #expect(throws: LockedFileError.authenticationFailed) { try LockedFile.open(sealed, masterKey: store.masterKey()) }
    #expect(try LockedFile.open(sealed, recoveryCode: code).plaintext == Data("owner".utf8))
    #expect(try store.load()?.enrollment == e)
}

@Test func pairedKeysPersistWithoutDuplicatesAndAFreshProfileForgetsThem() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ProfileStore(directory: dir, secrets: InMemorySecretStore())
    #expect(try store.pairedRecoveryKeys().isEmpty)
    let first = try RecoveryCode.privateKey(for: RecoveryCode.generate())
    let second = try RecoveryCode.privateKey(for: RecoveryCode.generate())
    #expect(try store.addPairedRecoveryKey(first) == true)
    #expect(try store.addPairedRecoveryKey(first) == false)
    #expect(try store.addPairedRecoveryKey(second) == true)
    #expect(try store.pairedRecoveryKeys().map(\.rawRepresentation) == [first.rawRepresentation, second.rawRepresentation])

    // Deleting profile.bin and enrolling someone else must not inherit access to the paired Macs' files.
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.2)) }, deviceUID: "UID-C")
    try store.createProfile(Profile(enrollment: e, recoveryPublicKey: Data(repeating: 2, count: 32), lockout: Lockout(), demoMode: false))
    #expect(try store.pairedRecoveryKeys().isEmpty)

    try store.addPairedRecoveryKey(first)
    try store.forgetPairedMacs()
    #expect(try store.pairedRecoveryKeys().isEmpty)
}

@Test func profileRoundTripsAndIsNotPlaintextOnDisk() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ProfileStore(directory: dir, secrets: InMemorySecretStore())
    #expect(try store.load() == nil)
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.2)) }, deviceUID: "UID-A")
    let p = Profile(enrollment: e, recoveryPublicKey: Data(repeating: 7, count: 32), lockout: Lockout(), demoMode: true)
    try store.createProfile(p)
    #expect(try store.load() == p)
    let raw = try Data(contentsOf: dir.appendingPathComponent("profile.bin"))
    #expect(raw.range(of: Data("UID-A".utf8)) == nil)
    let bytes = { (k: SymmetricKey) in k.withUnsafeBytes { Data($0) } }
    #expect(try bytes(store.masterKey()) == bytes(store.masterKey()))
}

@Test func inMemorySecretStoreRoundTrips() throws {
    let store = InMemorySecretStore()
    try store.save(Data([1, 2, 3]), as: "k")
    #expect(try store.load("k") == Data([1, 2, 3]))
    try store.delete("k")
    #expect(try store.load("k") == nil)
}

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
    for merged in [Lockout.mostRestrictive(earlier, later, now: t0, boot: now),
                   .mostRestrictive(later, earlier, now: t0, boot: now),
                   .mostRestrictive(later, Lockout(), now: t0, boot: now)] {
        #expect(merged.remaining(now: t0, boot: now) == 290)
    }
}

@Test func mergingPicksTheCooldownWithMoreTimeLeftNotTheLaterWallDate() {
    let stale = locked(at: t0, boot: bootA)                      // ends at t0 + 300, over by uptime 1300
    let back = t0.addingTimeInterval(-86_400)                    // the clock is then set back a day
    let active = locked(at: back, boot: BootClock(session: "A", uptime: 1400))
    let now = BootClock(session: "A", uptime: 1410)
    for merged in [Lockout.mostRestrictive(stale, active, now: back, boot: now),
                   .mostRestrictive(active, stale, now: back, boot: now)] {
        #expect(merged.remaining(now: back, boot: now) == 290)
    }
    let penalty = Lockout.tampered(now: back, boot: now)
    #expect(Lockout.mostRestrictive(stale, penalty, now: back, boot: now).remaining(now: back, boot: now) == 14_400)
    let neither = Lockout.mostRestrictive(stale, Lockout(), now: back, boot: now)
    #expect(neither.lockedUntil == nil && neither.lockedFor == nil && neither.lockCount == 1)
}

@Test func puttingBackAStaleProfileCannotCancelAnActiveCooldown() throws {
    let dir = tempDir()
    let store = ProfileStore(directory: dir, secrets: InMemorySecretStore())
    var p = try testProfile()
    try store.createProfile(p)
    p.lockout = locked(at: t0, boot: bootA)                      // ends at t0 + 300
    try store.save(p)
    let file = dir.appendingPathComponent("profile.bin")
    let stale = try Data(contentsOf: file)
    let back = t0.addingTimeInterval(-86_400)                    // the clock is set back a day, then a new lockout starts
    p.lockout = locked(at: back, boot: BootClock(session: "A", uptime: 1400))
    try store.save(p)
    try stale.write(to: file)                                    // someone puts the old copy back
    let now = BootClock(session: "A", uptime: 1410)
    #expect(try store.load(now: back, boot: now)?.lockout.remaining(now: back, boot: now) == 290)
}

@Test func afterARestartTheCooldownCountsDownWithTheNewBootEvenIfTheClockIsBehind() {
    let l = locked(at: t0, boot: bootA)
    let back = t0.addingTimeInterval(-86_400)
    let r = l.reanchored(now: back, boot: BootClock(session: "B", uptime: 5))
    #expect(r.lockCount == l.lockCount && r.failures == l.failures)
    #expect(r.remaining(now: back, boot: BootClock(session: "B", uptime: 5)) == 300)
    #expect(r.remaining(now: back, boot: BootClock(session: "B", uptime: 105)) == 200)
    #expect(r.remaining(now: back, boot: BootClock(session: "B", uptime: 306)) == nil)
    #expect(l.reanchored(now: t0, boot: bootA) == l)             // same boot: unchanged
    #expect(l.reanchored(now: t0, boot: nil) == l)               // no boot clock: unchanged
    #expect(l.reanchored(now: t0.addingTimeInterval(301), boot: BootClock(session: "B", uptime: 5)).lockedUntil == nil)
}

@Test func loadReanchorsALockoutOnceAfterARestart() throws {
    let store = ProfileStore(directory: tempDir(), secrets: InMemorySecretStore())
    var p = try testProfile()
    try store.createProfile(p)
    p.lockout = locked(at: t0, boot: bootA)
    try store.save(p)
    let back = t0.addingTimeInterval(-86_400)
    #expect(try store.load(now: back, boot: BootClock(session: "B", uptime: 5))?.lockout
        .remaining(now: back, boot: BootClock(session: "B", uptime: 5)) == 300)
    #expect(try store.load(now: back, boot: BootClock(session: "B", uptime: 105))?.lockout
        .remaining(now: back, boot: BootClock(session: "B", uptime: 105)) == 200)
}

@Test func launchStateReanchorsALockoutOnceAfterARestart() throws {
    let store = ProfileStore(directory: tempDir(), secrets: InMemorySecretStore())
    var p = try testProfile()
    try store.createProfile(p)
    p.lockout = locked(at: t0, boot: bootA)
    try store.save(p)
    let back = t0.addingTimeInterval(-86_400)
    guard case .ready(let first) = store.launchState(now: back, boot: BootClock(session: "B", uptime: 5)),
          case .ready(let later) = store.launchState(now: back, boot: BootClock(session: "B", uptime: 105)) else {
        Issue.record("a restart must leave the profile ready")
        return
    }
    #expect(first.lockout.remaining(now: back, boot: BootClock(session: "B", uptime: 5)) == 300)
    #expect(later.lockout.remaining(now: back, boot: BootClock(session: "B", uptime: 105)) == 200)
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

@Test func aFailedResetNeverLeavesTheOldProfileReadyWithANewMasterKey() throws {
    for name in ["profile-key", "master-key", "paired-recovery-keys", "lockout"] {
        for failDelete in [true, false] {
            let secrets = FailingSecretStore()
            let store = ProfileStore(directory: tempDir(), secrets: secrets)
            let old = try testProfile("UID-A"), fresh = try testProfile("UID-B")
            try store.createProfile(old)
            let master = try secrets.inner.load("master-key")
            if failDelete { secrets.failingDeletes = [name] } else { secrets.failingSaves = [name] }
            do { try store.createProfile(fresh, replacingExisting: true) } catch {}
            switch store.launchState() {
            case .ready(let p):
                if p.enrollment == old.enrollment {
                    #expect(try secrets.inner.load("master-key") == master, "old profile ready with a new master key (\(name), delete: \(failDelete))")
                } else {
                    #expect(p == fresh)
                }
            case .blocked:
                break
            case .noProfile:
                Issue.record("a reset must never look like a first run (\(name), delete: \(failDelete))")
            }
            secrets.failingDeletes = []
            secrets.failingSaves = []
            try store.createProfile(fresh, replacingExisting: true)
            #expect(store.launchState() == .ready(fresh))
        }
    }
}

@Test func anInaccessibleProfileFolderBlocksInsteadOfLookingLikeAFirstRun() throws {
    let fm = FileManager.default
    let dir = tempDir(), secrets = InMemorySecretStore()
    let store = ProfileStore(directory: dir, secrets: secrets)
    #expect(store.launchState() == .noProfile)   // the folder does not exist yet: confirmed absence
    try store.createProfile(try testProfile("UID-A"))
    let master = try secrets.load("master-key")
    try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
    #expect(store.launchState() == .blocked(.profileUnreadable))
    #expect(throws: (any Error).self) { try store.createProfile(try testProfile("UID-B")) }
    #expect(throws: (any Error).self) { try store.createProfile(try testProfile("UID-B"), replacingExisting: true) }
    #expect(try secrets.load("master-key") == master)
}
