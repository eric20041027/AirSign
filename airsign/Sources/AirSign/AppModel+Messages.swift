import AirSignCore
import Foundation

extension AppModel {
    static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    static func describe(_ reason: BlockReason) -> String {
        switch reason {
        case .storeError:
            return "AirSign couldn't read its keys from the Keychain. If macOS asked for permission and it was denied, choose Try again and allow it. Your locked files still open with the recovery code."
        case .keyMissing:
            return "AirSign's key is missing from the Keychain. Your locked files still open with the recovery code."
        case .profileUnreadable:
            return "AirSign's profile on this Mac can't be read. Your locked files still open with the recovery code."
        }
    }

    static func describe(_ issue: StrengthIssue, _ m: SignatureMetrics) -> String {
        let c = StrengthConfig.self
        switch issue {
        case .tooShort:
            return String(format: "too short (%.1f s; sign for at least %.1f s)", m.duration, c.minDuration)
        case .tooLittleMovement:
            return String(format: "too little movement (%.1f rad of turning; aim for %.0f+)", m.turning, c.minTurning)
        case .tooFewTurns:
            return "too few changes of direction (\(m.reversals); aim for \(c.minReversals)+)"
        case .oneDirection:
            return "moves mostly one way (use more directions)"
        }
    }

    static func describe(_ reason: AbortReason) -> String {
        switch reason {
        case .sensorSwitched: return "Discarded: use the same AirPod and keep the other one in the case."
        case .samplesStopped: return "Discarded: keep your finger over the AirPod's sensor."
        case .tooShort: return "Discarded: sign a little longer."
        }
    }

    static func describe(_ verdict: Verdict) -> String {
        let numbers = "score \(format(verdict.score)) vs threshold \(format(verdict.threshold))"
        let similarity = verdict.similarity.map { "\($0)%" } ?? "–"
        switch verdict.rejection {
        case .wrongBud: return "Not recognized: wrong AirPod side."
        case .wrongDevice: return "Not recognized: different AirPods."
        case .scoreTooHigh:
            return "Not recognized: similarity \(similarity), unlocks at \(SimilarityConfig.passMark)% (\(numbers))."
        case .deviceUnknown: return "Set the sound output to your AirPods (Control Center → Sound), then sign again. This try was not counted."
        case nil: return "Recognized: similarity \(similarity) (\(numbers))."
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case FileLockerError.alreadyLocked: return "already locked"
        case FileLockerError.tooLarge: return "larger than 500 MB"
        case FileLockerError.unreadable: return "can't be read"
        case FileLockerError.notLocked: return "not an .airsign file"
        case FileLockerError.writeFailed(let reason): return "could not write: \(reason)"
        case LockedFileError.notAirSignFile: return "not a valid .airsign file"
        case LockedFileError.unsupportedVersion(let v): return "made by a newer AirSign (version \(v))"
        case LockedFileError.badRecoveryCode: return "not a valid recovery code"
        default: return error.localizedDescription
        }
    }
}
