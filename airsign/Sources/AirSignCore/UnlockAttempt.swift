public enum UnlockAttempt {
    public enum SignatureDecision: Equatable {
        case notCounted, rejected, countNotSaved, openFiles
    }

    /// Counts the try. The answer is `.openFiles` only when the signature was accepted and the count was saved,
    /// so no file can be opened before the try has been counted.
    public static func signature(_ verdict: Verdict, count: (Lockout.Effect) -> Bool) -> SignatureDecision {
        guard verdict.rejection != .deviceUnknown else { return .notCounted }
        let effect = AttemptResult.signature(verdict).lockoutEffect
        guard count(effect) else { return .countNotSaved }
        guard verdict.accepted else { return .rejected }
        return .openFiles
    }

    public enum RecoveryDecision: Equatable {
        case counted, countNotSaved
    }

    /// A recovery-code try is counted after its file work, from what the code opened.
    public static func recoveryCode(_ outcome: UnlockOutcome, count: (Lockout.Effect) -> Bool) -> RecoveryDecision {
        let effect = AttemptResult.recoveryUnlock(restored: outcome.restored.count, wrongKey: outcome.wrongKey.count).lockoutEffect
        guard count(effect) else { return .countNotSaved }
        return .counted
    }
}
