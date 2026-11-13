import Foundation

/// Five wrong signatures or recovery codes in a row lock unlocking. Each lockout in a row lasts
/// longer (5 min, 15 min, 1 h, then 4 h) until the owner gets in again.
/// Discarded attempts (finger slipped, bud switched, too short) never reach this type.
public struct Lockout: Codable, Equatable {
    public static let maxFailures = 5
    public static let cooldowns: [TimeInterval] = [300, 900, 3600, 14400]

    public private(set) var failures = 0
    public private(set) var lockedUntil: Date?
    public private(set) var lockedFor: TimeInterval?
    public private(set) var lockedBootSession: String?
    public private(set) var lockedUptime: TimeInterval?
    /// Lockouts since the last success; picks the next cooldown.
    public private(set) var lockCount = 0

    public init() {}

    /// Profiles saved before escalation existed have no `lockCount`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        failures = try container.decodeIfPresent(Int.self, forKey: .failures) ?? 0
        lockedUntil = try container.decodeIfPresent(Date.self, forKey: .lockedUntil)
        lockedFor = try container.decodeIfPresent(TimeInterval.self, forKey: .lockedFor)
        lockedBootSession = try container.decodeIfPresent(String.self, forKey: .lockedBootSession)
        lockedUptime = try container.decodeIfPresent(TimeInterval.self, forKey: .lockedUptime)
        lockCount = try container.decodeIfPresent(Int.self, forKey: .lockCount) ?? 0
    }

    public mutating func recordFailure(now: Date, boot: BootClock? = nil) {
        if lockedUntil != nil, remaining(now: now, boot: boot) == nil {
            lockedUntil = nil
            lockedFor = nil
            lockedBootSession = nil
            lockedUptime = nil
        }
        failures += 1
        if failures >= Self.maxFailures {
            let step = min(lockCount, Self.cooldowns.count - 1)
            lockedUntil = now.addingTimeInterval(Self.cooldowns[step])
            lockedFor = Self.cooldowns[step]
            lockedBootSession = boot?.session
            lockedUptime = boot?.uptime
            lockCount += 1
            failures = 0
        }
    }

    public mutating func recordSuccess() {
        failures = 0
        lockedUntil = nil
        lockedFor = nil
        lockedBootSession = nil
        lockedUptime = nil
        lockCount = 0
    }

    /// Seconds left in the cooldown, or nil when unlocking is allowed.
    public func remaining(now: Date, boot: BootClock? = nil) -> TimeInterval? {
        guard let until = lockedUntil else { return nil }
        let seconds: TimeInterval
        if let lockedFor, let lockedBootSession, let lockedUptime,
           let boot, boot.session == lockedBootSession {
            seconds = lockedFor - (boot.uptime - lockedUptime)
        } else {
            let wallRemaining = until.timeIntervalSince(now)
            seconds = min(wallRemaining, lockedFor ?? Self.cooldowns[Self.cooldowns.count - 1])
        }
        return seconds > 0 ? seconds : nil
    }

    /// After a restart, carry the capped time left onto the new boot so uptime counts it down.
    public func reanchored(now: Date, boot: BootClock?) -> Lockout {
        guard lockedUntil != nil, let boot, lockedBootSession != boot.session else { return self }
        var anchored = self
        if let r = remaining(now: now, boot: boot) {
            anchored.lockedFor = r
            anchored.lockedUntil = now.addingTimeInterval(r)
            anchored.lockedBootSession = boot.session
            anchored.lockedUptime = boot.uptime
        } else {
            anchored.lockedUntil = nil
            anchored.lockedFor = nil
            anchored.lockedBootSession = nil
            anchored.lockedUptime = nil
        }
        return anchored
    }

    /// The longest cooldown, started now, when a saved lockout is missing.
    public static func tampered(now: Date, boot: BootClock?) -> Lockout {
        var lockout = Lockout()
        let duration = cooldowns[cooldowns.count - 1]
        lockout.lockedUntil = now.addingTimeInterval(duration)
        lockout.lockedFor = duration
        lockout.lockedBootSession = boot?.session
        lockout.lockedUptime = boot?.uptime
        lockout.lockCount = cooldowns.count
        return lockout
    }

    /// The stricter of two copies, so putting an older copy back never loosens anything.
    public static func mostRestrictive(_ a: Lockout, _ b: Lockout, now: Date, boot: BootClock?) -> Lockout {
        var aRemaining = a.remaining(now: now, boot: boot) ?? 0
        var bRemaining = b.remaining(now: now, boot: boot) ?? 0
        // A current-boot anchor supersedes a copy saved before this boot.
        if let session = boot?.session, let aBoot = a.lockedBootSession, let bBoot = b.lockedBootSession {
            if a.lockedUntil != nil, aBoot == session, bBoot != session {
                bRemaining = 0
            } else if b.lockedUntil != nil, bBoot == session, aBoot != session {
                aRemaining = 0
            }
        }
        var merged = Lockout()
        if aRemaining > 0 || bRemaining > 0 {
            merged = aRemaining >= bRemaining ? a : b
        }
        merged.failures = max(a.failures, b.failures)
        merged.lockCount = max(a.lockCount, b.lockCount)
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

    public mutating func apply(_ effect: Effect, now: Date, boot: BootClock? = nil) {
        switch effect {
        case .success: recordSuccess()
        case .failure: recordFailure(now: now, boot: boot)
        case .none: break
        }
    }
}
