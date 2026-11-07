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
