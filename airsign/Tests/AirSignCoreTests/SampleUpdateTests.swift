import Foundation
import Testing
@testable import AirSignCore

private func enrolled() throws -> Enrollment {
    try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.25)) }, deviceUID: "UID-A")
}

/// The owner's signature a few hours later: bigger and a little shifted.
private let driftedShape: (Double) -> SIMD3<Double> = { u in ownerShape(u) * 1.3 + SIMD3(0.4, 0, 0) }

@Test func addingASampleNeverLoosensThePassMark() throws {
    let e = try enrolled()
    let updated = try adding(Signature(samples: strokes(ownerShape, noise: 0.25)), to: e)
    #expect(updated.threshold == e.threshold)
    #expect(updated.gateThresholds == e.gateThresholds)
    #expect(updated.templates.count == 4 && updated.addedCount == 1)
}

@Test func anAddedSampleBringsADriftedSignatureBackIn() throws {
    let e = try enrolled()
    let later = Signature(samples: strokes(driftedShape, noise: 0.1))
    #expect(!verify(later, deviceUID: "UID-A", against: e).accepted)
    let updated = try adding(Signature(samples: strokes(driftedShape, noise: 0.1)), to: e)
    #expect(verify(later, deviceUID: "UID-A", against: updated).accepted)
    #expect(!verify(Signature(samples: strokes(forgeryShape, noise: 0.25)), deviceUID: "UID-A", against: updated).accepted)
}

@Test func keepsTheEnrolledSignaturesAndAtMostTwoAddedOnes() throws {
    let e = try enrolled()
    let a = Signature(samples: strokes(ownerShape, noise: 0.2))
    let b = Signature(samples: strokes(ownerShape, noise: 0.2))
    let c = Signature(samples: strokes(ownerShape, noise: 0.2))
    let updated = try adding(c, to: adding(b, to: adding(a, to: e)))
    #expect(updated.templates.count == 5 && updated.addedCount == SampleUpdate.maxAdded)
    #expect(Array(updated.templates.prefix(3)) == e.templates)
    #expect(Array(updated.templates.suffix(2)) == [b, c])
}

@Test func refusesASampleFromTheOtherBud() throws {
    let e = try enrolled()
    #expect(throws: MatcherError.mixedSides) {
        try adding(Signature(samples: strokes(ownerShape, noise: 0.2, side: .left)), to: e)
    }
}

@Test func removingAddedSamplesRestoresTheEnrollment() throws {
    let e = try enrolled()
    let updated = try adding(Signature(samples: strokes(ownerShape, noise: 0.2)), to: e)
    #expect(removingAddedSamples(from: updated) == e)
}

@Test func onlyAStrongPassCanBecomeASample() {
    let strong = Verdict(accepted: true, score: 0.7, threshold: 1, rejection: nil, lights: [])   // 82%
    let weak = Verdict(accepted: true, score: 0.95, threshold: 1, rejection: nil, lights: [])    // 76%
    let failed = Verdict(accepted: false, score: 0.5, threshold: 1, rejection: .wrongBud, lights: [])
    #expect(strong.canBecomeSample)
    #expect(!weak.canBecomeSample)
    #expect(!failed.canBecomeSample)
}
