import Foundation

/// Like a password policy: floors an enrolled signature must clear, and the levels that count as strong.
/// Set from the 2026-11-07 test-lab data (the owner signed ~5 s with ~9.8 rad of turning; teammates signing
/// their own names were often under 1.5 s and 3 rad). A heuristic backed by the literature's finding that
/// simple, short gestures are the easiest to forge, not a statistically validated cut-off.
public enum StrengthConfig {
    public static let minDuration = 1.5, strongDuration = 3.0          // seconds
    public static let minTurning = 3.0, strongTurning = 6.0            // radians of wrist turning
    public static let minReversals = 8, strongReversals = 30           // direction changes, all axes
    public static let maxDominantShare = 0.85, strongDominantShare = 0.7
    /// Gyro wobble inside ± this many rad/s doesn't count as a change of direction.
    public static let reversalDeadband = 0.5
}

/// What one signature contains, measured from its gyro.
public struct SignatureMetrics: Equatable {
    public var duration: Double
    /// Gyro speed integrated over time, in radians.
    public var turning: Double
    /// Times an axis swings from one direction to the other, summed over the three axes.
    public var reversals: Int
    /// Share of gyro energy on the busiest axis: near 1 means a one-direction wiggle.
    public var dominantShare: Double

    public init(duration: Double, turning: Double, reversals: Int, dominantShare: Double) {
        self.duration = duration
        self.turning = turning
        self.reversals = reversals
        self.dominantShare = dominantShare
    }

    public init(signature: Signature) {
        let rot = signature.features.map { SIMD3($0[0], $0[1], $0[2]) * FeatureScale.rotation }
        let dt = rot.count > 1 ? signature.duration / Double(rot.count - 1) : 0
        duration = signature.duration
        turning = rot.reduce(0) { $0 + ($1 * $1).sum().squareRoot() } * dt
        reversals = (0..<3).reduce(0) { total, axis in total + Self.reversals(rot.map { $0[axis] }) }
        let energy = (0..<3).map { axis in rot.reduce(0) { $0 + $1[axis] * $1[axis] } }
        let total = energy.reduce(0, +)
        dominantShare = total > 0 ? (energy.max() ?? 0) / total : 1
    }

    static func reversals(_ values: [Double]) -> Int {
        let band = StrengthConfig.reversalDeadband
        var state = 0, count = 0
        for v in values {
            let side = v > band ? 1 : (v < -band ? -1 : state)
            if side != state {
                if state != 0 { count += 1 }
                state = side
            }
        }
        return count
    }
}

public enum StrengthLevel: Int, Comparable {
    case weak, fair, strong

    public static func < (a: StrengthLevel, b: StrengthLevel) -> Bool { a.rawValue < b.rawValue }
}

public enum StrengthIssue: Hashable {
    case tooShort, tooLittleMovement, tooFewTurns, oneDirection
}

public struct SignatureStrength: Equatable {
    public var level: StrengthLevel
    /// Floors not met. Any issue makes the level `.weak`, and the enrollment is refused.
    public var issues: [StrengthIssue]
    /// Median over the enrolled signatures, so one rushed signature doesn't decide the rating.
    public var metrics: SignatureMetrics

    public static func of(_ signatures: [Signature]) -> SignatureStrength {
        let all = signatures.map(SignatureMetrics.init(signature:))
        let m = SignatureMetrics(
            duration: median(all.map(\.duration)),
            turning: median(all.map(\.turning)),
            reversals: Int(median(all.map { Double($0.reversals) }).rounded()),
            dominantShare: all.isEmpty ? 1 : median(all.map(\.dominantShare))
        )
        let c = StrengthConfig.self
        var issues: [StrengthIssue] = []
        if m.duration < c.minDuration { issues.append(.tooShort) }
        if m.turning < c.minTurning { issues.append(.tooLittleMovement) }
        if m.reversals < c.minReversals { issues.append(.tooFewTurns) }
        if m.dominantShare > c.maxDominantShare { issues.append(.oneDirection) }
        let strongCount = [
            m.duration >= c.strongDuration,
            m.turning >= c.strongTurning,
            m.reversals >= c.strongReversals,
            m.dominantShare <= c.strongDominantShare,
        ].filter { $0 }.count
        let level: StrengthLevel = !issues.isEmpty ? .weak : (strongCount >= 3 ? .strong : .fair)
        return SignatureStrength(level: level, issues: issues, metrics: m)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted(), mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
