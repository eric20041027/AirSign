import Foundation

/// Five wrong signatures or recovery codes in a row lock unlocking for five minutes.
/// Discarded attempts (finger slipped, bud switched, too short) never reach this type.
public struct Lockout: Codable, Equatable {
    public static let maxFailures = 5
    public static let cooldown: TimeInterval = 300

    public private(set) var failures = 0
    public private(set) var lockedUntil: Date?

    public init() {}

    public mutating func recordFailure(now: Date) {
        if let until = lockedUntil, now >= until {
            lockedUntil = nil
        }
        failures += 1
        if failures >= Self.maxFailures {
            lockedUntil = now.addingTimeInterval(Self.cooldown)
            failures = 0
        }
    }

    public mutating func recordSuccess() {
        failures = 0
        lockedUntil = nil
    }

    /// Seconds left in the cooldown, or nil when unlocking is allowed.
    public func remaining(now: Date) -> TimeInterval? {
        guard let until = lockedUntil, until > now else { return nil }
        return until.timeIntervalSince(now)
    }
}
