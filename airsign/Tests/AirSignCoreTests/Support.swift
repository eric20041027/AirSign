import Foundation
@testable import AirSignCore

/// One 50 Hz sample spinning about x at `speed` rad/s.
func sample(_ i: Int, speed: Double, side: BudSide = .right) -> MotionSample {
    MotionSample(t: Double(i) * 0.02, quat: SIMD4(0, 0, 0, 1), rot: SIMD3(speed, 0, 0),
                 acc: .zero, grav: SIMD3(0, 0.7, -0.7), side: side)
}

func run(_ r: inout SignatureRecorder, _ samples: [MotionSample]) -> [RecorderEvent] {
    samples.map { r.feed($0) }
}
