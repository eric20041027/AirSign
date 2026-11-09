import Foundation

/// Following natural drift: a signature that unlocked with a high similarity can be added to the enrollment, so later
/// signatures are compared with a recent one too. The pass mark never moves, the enrolled signatures always stay, and
/// at most `maxAdded` added ones are kept (the oldest added one goes first).
public enum SampleUpdate {
    public static let maxAdded = 2
    /// Well above the closest imitation in our tests (72%).
    public static let minSimilarity = 80
}

extension Verdict {
    public var canBecomeSample: Bool { accepted && (similarity ?? 0) >= SampleUpdate.minSimilarity }
}

public func adding(_ sig: Signature, to e: Enrollment) throws -> Enrollment {
    guard sig.side == e.side else { throw MatcherError.mixedSides }
    var updated = e
    if updated.addedCount >= SampleUpdate.maxAdded {
        updated.templates.remove(at: updated.templates.count - updated.addedCount)
        updated.addedSamples = updated.addedCount - 1
    }
    updated.templates.append(sig)
    updated.addedSamples = updated.addedCount + 1
    return updated
}

public func removingAddedSamples(from e: Enrollment) -> Enrollment {
    var original = e
    original.templates.removeLast(e.addedCount)
    original.addedSamples = nil
    return original
}
