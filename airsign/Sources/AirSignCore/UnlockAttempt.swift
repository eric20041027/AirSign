public enum UnlockAttempt {
    public enum SignatureStep {
        case notCounted, rejected, countNotSaved, opened(UnlockOutcome)
    }

    /// Counts the try first. Files are opened only when the signature was accepted and the count was saved.
    public static func signature(_ verdict: Verdict, count: (Lockout.Effect) -> Bool,
                                 openFiles: () throws -> UnlockOutcome) rethrows -> SignatureStep {
        let effect = AttemptResult.signature(verdict).lockoutEffect
        guard effect != .none else { return .notCounted }
        guard count(effect) else { return .countNotSaved }
        guard verdict.accepted else { return .rejected }
        return .opened(try openFiles())
    }

    public enum RecoveryStep {
        case counted(UnlockOutcome), countNotSaved(UnlockOutcome)
    }

    /// Opens first, then counts from what the code opened.
    public static func recoveryCode(openFiles: () -> UnlockOutcome,
                                    count: (Lockout.Effect) -> Bool) -> RecoveryStep {
        let outcome = openFiles()
        let effect = AttemptResult.recoveryUnlock(restored: outcome.restored.count, wrongKey: outcome.wrongKey.count).lockoutEffect
        guard count(effect) else { return .countNotSaved(outcome) }
        return .counted(outcome)
    }
}
