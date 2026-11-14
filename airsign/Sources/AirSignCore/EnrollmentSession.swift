import CryptoKit
import Foundation

/// Keeps enrollment and its checks together so a failed step cannot leave a partial enrollment.
public struct EnrollmentSession {
    public private(set) var signatures: [Signature] = []
    public private(set) var pending: Enrollment?
    public private(set) var confirmations = 0
    public private(set) var strength: SignatureStrength?

    public init() {}

    public enum AddResult: Equatable {
        case wrongSide(expected: BudSide)
        case needMore(have: Int)
        case noOutputDevice
        case tooWeak(SignatureStrength)
        case cannotBuild(String)
        case readyToConfirm
    }

    /// `deviceUID` is the sound output's AirPods, or nil when the output is something else.
    public mutating func add(_ signature: Signature, deviceUID: String?) -> AddResult {
        if let first = signatures.first, first.side != signature.side {
            return .wrongSide(expected: first.side)
        }
        if signatures.isEmpty { strength = nil }
        signatures.append(signature)
        guard signatures.count >= MatcherConfig.enrollCount else { return .needMore(have: signatures.count) }
        guard let deviceUID else {
            signatures.removeLast()
            return .noOutputDevice
        }
        let rating = SignatureStrength.of(signatures)
        strength = rating
        guard rating.level != .weak else {
            clear(keepingStrength: true)
            return .tooWeak(rating)
        }
        do {
            pending = try enroll(signatures, deviceUID: deviceUID)
            confirmations = 0
            return .readyToConfirm
        } catch {
            clear(keepingStrength: true)
            return .cannotBuild(error.localizedDescription)
        }
    }

    public enum CheckResult: Equatable {
        case notCounted(Verdict)
        case mismatch(check: Int)
        case passed(Int)
        case complete(Enrollment)
    }

    /// Every check must pass at the enrolled threshold, including when demo mode is on.
    public mutating func check(_ signature: Signature, deviceUID: String?) -> CheckResult {
        guard let candidate = pending else { return .passed(confirmations) }
        let verdict = verify(signature, deviceUID: deviceUID, against: candidate)
        if verdict.rejection == .deviceUnknown { return .notCounted(verdict) }
        guard verdict.accepted else {
            let check = confirmations + 1
            clear(keepingStrength: true)
            return .mismatch(check: check)
        }
        confirmations += 1
        guard confirmations >= MatcherConfig.confirmCount else { return .passed(confirmations) }
        pending = nil
        confirmations = 0
        return .complete(candidate)
    }

    /// Start over: failures keep the rating to explain why; an explicit restart forgets it.
    public mutating func clear(keepingStrength: Bool) {
        signatures = []
        pending = nil
        confirmations = 0
        if !keepingStrength { strength = nil }
    }
}

public enum EnrollmentCompletion {
    case signatureChanged(Profile)
    case awaitingCodeConfirmation(profile: Profile, code: String)

    /// `current` is the profile whose signature is being changed, or nil for a first enrollment or a reset.
    public static func complete(_ enrollment: Enrollment, changingSignatureOf current: Profile?) throws -> EnrollmentCompletion {
        if var updated = current {
            updated.enrollment = enrollment
            updated.lockout.recordSuccess()
            return .signatureChanged(updated)
        }
        let code = RecoveryCode.generate()
        let recoveryKey = try RecoveryCode.privateKey(for: code).publicKey.rawRepresentation
        // Demo mode shows scores, so it starts off and turning it on needs the owner.
        let profile = Profile(enrollment: enrollment, recoveryPublicKey: recoveryKey, lockout: Lockout(), demoMode: false)
        return .awaitingCodeConfirmation(profile: profile, code: code)
    }
}
