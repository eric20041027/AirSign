import CryptoKit
import Foundation

/// Who signed what, attached to every test-mode attempt.
public struct AttemptLabels: Equatable {
    /// The owner signing their own signature; every other scenario is an imitation.
    public static let ownerScenario = "A1-owner"

    public var tester: String
    public var scenario: String
    public var session: String
    public var owner: String
    /// `Enrollment.fingerprint` of the templates this attempt was compared against.
    public var enrollment = ""

    public init(tester: String, scenario: String, session: String, owner: String) {
        self.tester = tester
        self.scenario = scenario
        self.session = session
        self.owner = owner
    }

    public var isGenuine: Bool { scenario == Self.ownerScenario }
}

public extension Enrollment {
    /// 12 hex characters identifying these templates, the same after save and reload.
    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(templates)) ?? Data()
        return SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

/// Test mode only: one JSON file per attempt, in the spike's format (`mode`, `who`, `dur`, `loc`, `rows`)
/// so the Python tuning tools can replay every attempt with other settings. Stays on this Mac.
public struct AttemptLog {
    public enum Mode: String {
        case enroll, verify
    }

    public static let columns = "t,qx,qy,qz,qw,rot_x,rot_y,rot_z,acc_x,acc_y,acc_z,grav_x,grav_y,grav_z"

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// ~/Library/Application Support/AirSign/test-logs
    public static var defaultDirectory: URL {
        ProfileStore.defaultDirectory.appendingPathComponent("test-logs", isDirectory: true)
    }

    @discardableResult
    public func write(mode: Mode, labels: AttemptLabels, samples: [MotionSample], verdict: Verdict?) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var object: [String: Any] = [
            "mode": mode.rawValue,
            "who": labels.isGenuine ? "genuine" : "forgery",
            "tester": labels.tester,
            "scenario": labels.scenario,
            "session": labels.session,
            "owner": labels.owner,
            "enrollment": labels.enrollment,
            "savedAt": ISO8601DateFormatter().string(from: Date()),
            "dur": (samples.last?.t ?? 0) - (samples.first?.t ?? 0),
            "loc": samples.first?.side.rawValue ?? BudSide.unknown.rawValue,
            "columns": Self.columns,
            "rows": samples.map { s in
                [s.t, s.quat.x, s.quat.y, s.quat.z, s.quat.w, s.rot.x, s.rot.y, s.rot.z,
                 s.acc.x, s.acc.y, s.acc.z, s.grav.x, s.grav.y, s.grav.z]
            },
        ]
        if let verdict {
            object["accepted"] = verdict.accepted
            object["score"] = Self.finite(verdict.score)
            object["threshold"] = Self.finite(verdict.threshold)
            object["rejection"] = verdict.rejection.map { "\($0)" } ?? NSNull()
            object["lights"] = Dictionary(uniqueKeysWithValues: verdict.lights.map { ($0.gate.rawValue, Self.finite($0.ratio)) })
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let url = uniqueURL()
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }

    /// JSON has no infinity; a disconnected DTW band is written as null.
    private static func finite(_ value: Double) -> Any {
        value.isFinite ? value : NSNull()
    }

    private func uniqueURL() -> URL {
        let base = "attempt-\(Self.stamp.string(from: Date()))"
        var candidate = directory.appendingPathComponent("\(base).json")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(n).json")
            n += 1
        }
        return candidate
    }
}
