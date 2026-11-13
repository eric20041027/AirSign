import AirSignCore
import Foundation

/// A synthetic signature: `shape(u)` is the gyro reading at progress u in [0, 1).
public func strokes(_ shape: (Double) -> SIMD3<Double>, n: Int = 110, noise: Double = 0, side: BudSide = .right) -> [MotionSample] {
    var g = SystemRandomNumberGenerator()
    return (0..<n).map { i in
        let u = Double(i) / Double(n)
        let j = { Double.random(in: -noise...noise, using: &g) }
        let r = shape(u) + SIMD3(j(), j(), j())
        return MotionSample(t: Double(i) * 0.02, quat: SIMD4(0, 0, 0, 1), rot: r, acc: r * 0.05,
                            grav: SIMD3(0, 0.7, -0.7), side: side)
    }
}

public let ownerShape: @Sendable (Double) -> SIMD3<Double> = { u in
    SIMD3(3 * sin(4 * .pi * u), 2 * cos(6 * .pi * u) + 0.8, 1.5 * sin(2 * .pi * u) + 1)
}

public extension MotionSample {
    /// Parses a spike recording row: t,qx,qy,qz,qw,rot_x,rot_y,rot_z,acc_x,acc_y,acc_z,grav_x,grav_y,grav_z.
    static func fromSpikeRow(_ row: [Double], loc: String) -> MotionSample {
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
