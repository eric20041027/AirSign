import Foundation
import Testing
@testable import AirSignCore

@Test func dtwOfIdenticalIsZeroAndStretchIsSmall() {
    let a = Signature(samples: strokes(ownerShape)).features
    let stretched = Signature(samples: strokes(ownerShape, n: 140)).features
    let other = Signature(samples: strokes(forgeryShape)).features
    #expect(dtwDistance(a, a) == 0)
    #expect(dtwDistance(a, stretched) < dtwDistance(a, other) / 4)
}

@Test func durationFactorScalesDistance() {
    let a = Signature(samples: strokes(ownerShape, n: 100))
    let b = Signature(samples: strokes(ownerShape, n: 200))
    let plain = distance(a, b, useDuration: false)
    #expect(abs(distance(a, b) - plain * (1 + 0.5 * abs(log(a.duration / b.duration)))) < 1e-9)
}

@Test func enrollNeedsThreeSameSideSignatures() {
    let s = (0..<2).map { _ in Signature(samples: strokes(ownerShape, noise: 0.2)) }
    #expect(throws: MatcherError.needAtLeast(3)) { try enroll(s, deviceUID: "X") }
    let mixed = s + [Signature(samples: strokes(ownerShape, side: .left))]
    #expect(throws: MatcherError.mixedSides) { try enroll(mixed, deviceUID: "X") }
}

@Test func ownerAcceptedForgeryRejectedWithLights() throws {
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.25)) }, deviceUID: "UID-A")
    let owner = verify(Signature(samples: strokes(ownerShape, n: 112, noise: 0.1)), deviceUID: "UID-A", against: e)
    let fake = verify(Signature(samples: strokes(forgeryShape, noise: 0.25)), deviceUID: "UID-A", against: e)
    #expect(owner.accepted && owner.rejection == nil)
    #expect(!fake.accepted && fake.rejection == .scoreTooHigh)
    #expect(fake.lights.map(\.gate) == [.grip, .sizeTempo, .rhythm])
}

@Test func gateOneIsHard() throws {
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.25)) }, deviceUID: "UID-A")
    let wrongBud = verify(Signature(samples: strokes(ownerShape, noise: 0.25, side: .left)), deviceUID: "UID-A", against: e)
    let wrongPair = verify(Signature(samples: strokes(ownerShape, noise: 0.25)), deviceUID: "UID-B", against: e)
    #expect(wrongBud.rejection == .wrongBud && !wrongBud.accepted)
    #expect(wrongPair.rejection == .wrongDevice && !wrongPair.accepted)
}

@Test func unknownOutputDeviceIsNotAcceptedWhenADeviceWasEnrolled() throws {
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.25)) }, deviceUID: "UID-A")
    let v = verify(Signature(samples: strokes(ownerShape, n: 112, noise: 0.1)), deviceUID: nil, against: e)
    #expect(!v.accepted && v.rejection == .deviceUnknown)
}

@Test func thresholdOverrideCanOnlyTighten() throws {
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.25)) }, deviceUID: "UID-A")
    let fake = Signature(samples: strokes(forgeryShape, noise: 0.25))
    let loosened = verify(fake, deviceUID: "UID-A", against: e, threshold: e.threshold * 100)
    #expect(!loosened.accepted && loosened.threshold == e.threshold)
    let tightened = verify(fake, deviceUID: "UID-A", against: e, threshold: e.threshold / 2)
    #expect(tightened.threshold == e.threshold / 2)
}

@Test func lightsStayFiniteWhenEnrolledGateIsIdentical() throws {
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape)) }, deviceUID: nil)
    let v = verify(Signature(samples: strokes(ownerShape)), deviceUID: nil, against: e)
    #expect(v.lights.allSatisfy { $0.ratio.isFinite })
}
