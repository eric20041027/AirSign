import Foundation

public enum BudSide: String, Codable, Sendable {
    case left, right, unknown
}

/// One headphone-motion reading (CoreMotion delivers about 50 per second).
public struct MotionSample: Equatable, Codable, Sendable {
    public var t: Double
    public var quat: SIMD4<Double>
    public var rot: SIMD3<Double>
    public var acc: SIMD3<Double>
    public var grav: SIMD3<Double>
    public var side: BudSide

    public init(t: Double, quat: SIMD4<Double>, rot: SIMD3<Double>, acc: SIMD3<Double>, grav: SIMD3<Double>, side: BudSide) {
        self.t = t
        self.quat = quat
        self.rot = rot
        self.acc = acc
        self.grav = grav
        self.side = side
    }

    /// Gyro speed in rad/s.
    public var speed: Double { (rot * rot).sum().squareRoot() }
}
