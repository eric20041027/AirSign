import Foundation
import Testing
@testable import AirSignCore

private func verdict(score: Double, threshold: Double = 1, rejection: Rejection? = nil) -> Verdict {
    Verdict(accepted: rejection == nil, score: score, threshold: threshold, rejection: rejection, lights: [])
}

@Test func similarityIsHundredMinusTwentyFiveTimesTheScoreOverThreshold() {
    #expect(verdict(score: 0).similarity == 100)
    #expect(verdict(score: 0.4).similarity == 90)
    #expect(verdict(score: 0.6, threshold: 0.75).similarity == 80)   // as far as the enrollment spread
}

@Test func passMarkIsSeventyFiveAtTheThreshold() {
    #expect(SimilarityConfig.passMark == 75)
    #expect(verdict(score: 1).similarity == 75)
    #expect(verdict(score: 1.0001, rejection: .scoreTooHigh).similarity == 74)
}

@Test func shownSimilarityNeverContradictsTheDecision() {
    #expect(verdict(score: 1, rejection: .scoreTooHigh).similarity == 74)
    #expect(Verdict(accepted: true, score: 1.2, threshold: 1, rejection: nil, lights: []).similarity == 75)
}

@Test func noSimilarityForDeviceRejectionsOrABrokenThreshold() {
    #expect(verdict(score: 0.2, rejection: .wrongBud).similarity == nil)
    #expect(verdict(score: 0.2, rejection: .wrongDevice).similarity == nil)
    #expect(verdict(score: 0.2, rejection: .deviceUnknown).similarity == nil)
    #expect(verdict(score: 0.2, threshold: 0).similarity == nil)
    #expect(verdict(score: .nan).similarity == nil)
}

@Test func farAwaySignatureBottomsOutAtZero() {
    #expect(verdict(score: 10, rejection: .scoreTooHigh).similarity == 0)
}

@Test func ownerScoresAtLeastThePassMarkAndForgeryBelow() throws {
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.25)) }, deviceUID: "UID-A")
    let owner = verify(Signature(samples: strokes(ownerShape, n: 112, noise: 0.1)), deviceUID: "UID-A", against: e)
    let fake = verify(Signature(samples: strokes(forgeryShape, noise: 0.25)), deviceUID: "UID-A", against: e)
    #expect((owner.similarity ?? 0) >= SimilarityConfig.passMark)
    #expect((fake.similarity ?? 100) < SimilarityConfig.passMark)
}
