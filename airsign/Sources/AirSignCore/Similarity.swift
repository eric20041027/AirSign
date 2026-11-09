import Foundation

/// A closeness score for people to read, fixed before S2 (2026-11-07). Not a probability: 100 is identical to an
/// enrolled signature, 80 is as far as your own enrollment signatures are from each other (the threshold is 1.25×
/// that spread), and 75 is the threshold itself. The decision stays the threshold check; this only displays it.
public enum SimilarityConfig {
    public static let passMark = 75
    public static let slope = 25.0
}

extension Verdict {
    /// `nil` when the attempt was turned away before scoring (wrong bud, other AirPods, unknown device).
    public var similarity: Int? {
        switch rejection {
        case .wrongBud, .wrongDevice, .deviceUnknown: return nil
        case .scoreTooHigh, nil: break
        }
        let ratio = score / threshold
        guard threshold > 0, ratio.isFinite else { return nil }
        let value = Int(min(max(100 - SimilarityConfig.slope * ratio, 0), 100).rounded(.down))
        return accepted ? max(value, SimilarityConfig.passMark) : min(value, SimilarityConfig.passMark - 1)
    }
}
