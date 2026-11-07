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
    let before = try store.masterKey()
    let code = RecoveryCode.generate()
    let pub = try RecoveryCode.privateKey(for: code).publicKey
    let sealed = try LockedFile.seal(Data("owner".utf8), originalName: "a.txt", masterKey: before, recoveryPublicKey: pub)
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
    try store.save(p)
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
