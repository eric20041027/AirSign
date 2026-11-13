import Foundation
@testable import AirSignCore
import AirSignTestSupport

/// One 50 Hz sample spinning about x at `speed` rad/s.
func sample(_ i: Int, speed: Double, side: BudSide = .right) -> MotionSample {
    MotionSample(t: Double(i) * 0.02, quat: SIMD4(0, 0, 0, 1), rot: SIMD3(speed, 0, 0),
                 acc: .zero, grav: SIMD3(0, 0.7, -0.7), side: side)
}

func run(_ r: inout SignatureRecorder, _ samples: [MotionSample]) -> [RecorderEvent] {
    samples.map { r.feed($0) }
}

let forgeryShape: (Double) -> SIMD3<Double> = { u in
    SIMD3(3 * sin(4 * .pi * u + 0.9), 2 * cos(4 * .pi * u) + 0.8, 1.5 * sin(3 * .pi * u) + 1)
}

/// Reads of the listed names fail until deleted; listed saves and deletes always fail.
final class FailingSecretStore: SecretStore {
    struct Denied: Error {}
    let inner = InMemorySecretStore()
    var failingLoads: Set<String> = []
    var failingSaves: Set<String> = []
    var failingDeletes: Set<String> = []
    func load(_ name: String) throws -> Data? {
        if failingLoads.contains(name) { throw Denied() }
        return try inner.load(name)
    }
    func save(_ data: Data, as name: String) throws {
        if failingSaves.contains(name) { throw Denied() }
        try inner.save(data, as: name)
    }
    func delete(_ name: String) throws {
        if failingDeletes.contains(name) { throw Denied() }
        failingLoads.remove(name)
        try inner.delete(name)
    }
}

func tempDir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

func testProfile(_ deviceUID: String = "UID-A") throws -> Profile {
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.2)) }, deviceUID: deviceUID)
    return Profile(enrollment: e, recoveryPublicKey: Data(repeating: 7, count: 32), lockout: Lockout(), demoMode: false)
}
