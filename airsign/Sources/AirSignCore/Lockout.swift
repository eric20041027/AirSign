import Foundation

/// Five wrong signatures or recovery codes in a row lock unlocking. Each lockout in a row lasts
/// longer (5 min, 15 min, 1 h, then 4 h) until the owner gets in again.
/// Discarded attempts (finger slipped, bud switched, too short) never reach this type.
public struct Lockout: Codable, Equatable {
    public static let maxFailures = 5
    public static let cooldowns: [TimeInterval] = [300, 900, 3600, 14400]

    public private(set) var failures = 0
    public private(set) var lockedUntil: Date?
    /// Lockouts since the last success; picks the next cooldown.
    public private(set) var lockCount = 0

    public init() {}

    /// Profiles saved before escalation existed have no `lockCount`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        failures = try container.decodeIfPresent(Int.self, forKey: .failures) ?? 0
        lockedUntil = try container.decodeIfPresent(Date.self, forKey: .lockedUntil)
        lockCount = try container.decodeIfPresent(Int.self, forKey: .lockCount) ?? 0
    }

    public mutating func recordFailure(now: Date) {
        if let until = lockedUntil, now >= until {
            lockedUntil = nil
        }
        failures += 1
        if failures >= Self.maxFailures {
            let step = min(lockCount, Self.cooldowns.count - 1)
            lockedUntil = now.addingTimeInterval(Self.cooldowns[step])
            lockCount += 1
            failures = 0
        }
    }

    public mutating func recordSuccess() {
        failures = 0
        lockedUntil = nil
        lockCount = 0
    }

    /// Seconds left in the cooldown, or nil when unlocking is allowed.
    public func remaining(now: Date) -> TimeInterval? {
        guard let until = lockedUntil, until > now else { return nil }
        return until.timeIntervalSince(now)
    }

    /// The stricter of two copies, so putting an older copy back never loosens anything.
    public static func mostRestrictive(_ a: Lockout, _ b: Lockout) -> Lockout {
        var merged = Lockout()
        merged.failures = max(a.failures, b.failures)
        merged.lockCount = max(a.lockCount, b.lockCount)
        merged.lockedUntil = [a.lockedUntil, b.lockedUntil].compactMap { $0 }.max()
        return merged
    }

    public enum Effect: Equatable {
        case success, failure, none
    }

    /// A recovery code only counts when at least one file judged it: junk or unreadable
    /// `.airsign` files must not reset the count.
    public static func recoveryEffect(restored: Int, wrongKey: Int) -> Effect {
        if wrongKey > 0 { return .failure }
        return restored > 0 ? .success : .none
    }

    public mutating func apply(_ effect: Effect, now: Date) {
        switch effect {
        case .success: recordSuccess()
        case .failure: recordFailure(now: now)
        case .none: break
        }
    }
}
