import Darwin
import Foundation

public struct BootClock: Equatable, Sendable {
    public var session: String
    public var uptime: TimeInterval

    public init(session: String, uptime: TimeInterval) {
        self.session = session
        self.uptime = uptime
    }

    /// nil when the system reports no boot session.
    public static func current() -> BootClock? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        let status = buffer.withUnsafeMutableBufferPointer {
            sysctlbyname("kern.bootsessionuuid", $0.baseAddress, &size, nil, 0)
        }
        guard status == 0 else { return nil }
        let session = String(cString: buffer)
        guard !session.isEmpty else { return nil }
        // Monotonic raw time keeps counting during sleep, unlike uptime raw time.
        let uptime = TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
        return BootClock(session: session, uptime: uptime)
    }
}
