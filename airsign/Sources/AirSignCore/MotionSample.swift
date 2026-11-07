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

    /// Parses a spike recording row: t,qx,qy,qz,qw,rot_x,rot_y,rot_z,acc_x,acc_y,acc_z,grav_x,grav_y,grav_z.
    public static func fromSpikeRow(_ row: [Double], loc: String) -> MotionSample {
        precondition(row.count >= 14, "spike rows have 14 columns")
        return MotionSample(
            t: row[0],
            quat: SIMD4(row[1], row[2], row[3], row[4]),
            rot: SIMD3(row[5], row[6], row[7]),
            acc: SIMD3(row[8], row[9], row[10]),
            grav: SIMD3(row[11], row[12], row[13]),
            side: BudSide(rawValue: loc) ?? .unknown
        )
    }
}
