import Foundation
import Testing
@testable import AirSignCore

@Test func turningIsGyroSpeedIntegratedOverTime() {
    let s = Signature(samples: strokes({ _ in SIMD3(2, 0, 0) }, n: 101))
    #expect(abs(SignatureMetrics(signature: s).turning - 4.0) < 0.1)   // 2 rad/s for 2 s
}

@Test func reversalsIgnoreWobbleBelowTheDeadband() {
    let wobble = Signature(samples: strokes({ u in SIMD3(0.3 * sin(6 * .pi * u), 0, 0) }, n: 150))
    let swings = Signature(samples: strokes({ u in SIMD3(2 * sin(6 * .pi * u), 0, 0) }, n: 150))
    #expect(SignatureMetrics(signature: wobble).reversals == 0)
    #expect(SignatureMetrics(signature: swings).reversals == 5)       // + - + - + - over 3 cycles
}

@Test func shortSignatureIsWeakBecauseItIsTooShort() {
    let sigs = (0..<3).map { _ in Signature(samples: strokes(ownerShape, n: 40, noise: 0.1)) }
    let strength = SignatureStrength.of(sigs)
    #expect(strength.level == .weak && strength.issues.contains(.tooShort))
}

@Test func oneAxisWiggleIsWeakBecauseItUsesOneDirection() {
    let sigs = (0..<3).map { _ in Signature(samples: strokes({ u in SIMD3(3 * sin(8 * .pi * u), 0, 0) }, n: 150)) }
    let strength = SignatureStrength.of(sigs)
    #expect(strength.level == .weak && strength.issues.contains(.oneDirection))
}

@Test func longVariedSignatureIsStrongWithNoIssues() {
    let sigs = (0..<3).map { _ in Signature(samples: strokes(ownerShape, n: 200, noise: 0.1)) }
    let strength = SignatureStrength.of(sigs)
    #expect(strength.level == .strong && strength.issues.isEmpty)
}

@Test func strengthUsesTheMedianSignature() {
    let good = Signature(samples: strokes(ownerShape, n: 200, noise: 0.1))
    let short = Signature(samples: strokes(ownerShape, n: 40, noise: 0.1))
    // One rushed signature among three good ones doesn't decide the rating.
    #expect(SignatureStrength.of([good, short, good]).level != .weak)
}
