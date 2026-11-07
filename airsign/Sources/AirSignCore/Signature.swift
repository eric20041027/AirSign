import Foundation

/// Scales that bring gyro and acceleration into roughly the same range as the gravity unit vector.
public enum FeatureScale {
    public static let rotation = 3.0       // rad/s
    public static let acceleration = 0.5   // g
}

/// A recorded air signature, reduced to what the matcher compares.
public struct Signature: Codable, Equatable {
    /// One row per sample: rot x/y/z, acc x/y/z, grav x/y/z (scaled).
    public var features: [[Double]]
    public var duration: Double
    public var side: BudSide
    /// Gyro integrated over time, used to draw the signature's shape.
    public var path: [SIMD3<Double>]

    public init(samples: [MotionSample]) {
        features = samples.map { s in
            let r = s.rot / FeatureScale.rotation, a = s.acc / FeatureScale.acceleration
            return [r.x, r.y, r.z, a.x, a.y, a.z, s.grav.x, s.grav.y, s.grav.z]
        }
        duration = (samples.last?.t ?? 0) - (samples.first?.t ?? 0)
        side = samples.first?.side ?? .unknown
        path = Self.integrate(samples)
    }

    private static func integrate(_ samples: [MotionSample]) -> [SIMD3<Double>] {
        guard let first = samples.first else { return [] }
        var path: [SIMD3<Double>] = [.zero]
        var previous = first
        for s in samples.dropFirst() {
            path.append(path[path.count - 1] + s.rot * (s.t - previous.t))
            previous = s
        }
        return path
    }
}
