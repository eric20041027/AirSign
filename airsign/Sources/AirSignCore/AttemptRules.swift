import Foundation

public enum AttemptRefusal: Equatable {
    case coolingDown(TimeInterval), cannotSave
}

public enum AttemptGate {
    /// A try that would count toward the lockout is refused, uncounted: first when a cooldown is running, then when the profile can't be saved.
    public static func refusal(lockout: Lockout?, saveBlocked: Bool, now: Date, boot: BootClock?) -> AttemptRefusal? {
        if let remaining = lockout?.remaining(now: now, boot: boot) { return .coolingDown(remaining) }
        return saveBlocked ? .cannotSave : nil
    }
}

public enum AttemptResult: Equatable {
    case signature(Verdict)
    case malformedCode
    case identityCode(matches: Bool)
    case recoveryUnlock(restored: Int, wrongKey: Int)

    public var lockoutEffect: Lockout.Effect {
        switch self {
        case .signature(let verdict):
            if verdict.rejection == .deviceUnknown { return .none }
            return verdict.accepted ? .success : .failure
        case .malformedCode:
            return .failure
        case .identityCode(let matches):
            return matches ? .success : .failure
        case .recoveryUnlock(let restored, let wrongKey):
            return Lockout.recoveryEffect(restored: restored, wrongKey: wrongKey)
        }
    }
}

public enum SensitiveAction: Equatable, CaseIterable {
    case changeSignature, enableDemo, openLab

    /// One lucky imitation must not be enough to replace the owner's signature.
    public var needsRecoveryCode: Bool { self == .changeSignature }
}

public enum IdentityCheck {
    /// The code proves identity when the key it gives is the profile's recovery public key. No profile, or a malformed code: false.
    public static func codeMatches(_ code: String, recoveryPublicKey: Data?) -> Bool {
        guard let recoveryPublicKey,
              let key = try? RecoveryCode.privateKey(for: code).publicKey.rawRepresentation else { return false }
        return key == recoveryPublicKey
    }
}

public enum PairingRule {
    /// Only a Mac with its own enrolled signature can be paired, and only after the code has opened a file.
    public static func shouldPair(requested: Bool, hasProfile: Bool, restored: Int) -> Bool {
        requested && hasProfile && restored > 0
    }
}
