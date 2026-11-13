import Foundation
import Testing
@testable import AirSignCore

private let now = Date(timeIntervalSince1970: 1_000_000)
private let boot = BootClock(session: "A", uptime: 1000)
private func locked() -> Lockout { var l = Lockout(); for _ in 0..<5 { l.recordFailure(now: now, boot: boot) }; return l }
private func verdict(accepted: Bool, _ rejection: Rejection? = nil) -> Verdict {
    Verdict(accepted: accepted, score: 1, threshold: 2, rejection: rejection, lights: [])
}

private final class CallRecorder {
    var calls: [Lockout.Effect] = []
    var saves = true

    func count(_ effect: Lockout.Effect) -> Bool {
        calls.append(effect)
        return saves
    }
}

struct AttemptRulesTests {
    @Test func aTryIsRefusedUncountedDuringACooldownOrWhenNothingCanBeSaved() {
        #expect(AttemptGate.refusal(lockout: Lockout(), saveBlocked: false, now: now, boot: boot) == nil)
        #expect(AttemptGate.refusal(lockout: nil, saveBlocked: false, now: now, boot: boot) == nil)
        #expect(AttemptGate.refusal(lockout: locked(), saveBlocked: false, now: now, boot: boot) == .coolingDown(300))
        #expect(AttemptGate.refusal(lockout: locked(), saveBlocked: true, now: now, boot: boot) == .coolingDown(300))   // the cooldown is named first
        #expect(AttemptGate.refusal(lockout: Lockout(), saveBlocked: true, now: now, boot: boot) == .cannotSave)
        #expect(AttemptGate.refusal(lockout: nil, saveBlocked: true, now: now, boot: boot) == .cannotSave)
    }

    @Test func eachResultHasItsEffectOnTheLockout() {
        #expect(AttemptResult.signature(verdict(accepted: true)).lockoutEffect == .success)
        #expect(AttemptResult.signature(verdict(accepted: false, .scoreTooHigh)).lockoutEffect == .failure)
        #expect(AttemptResult.signature(verdict(accepted: false, .wrongBud)).lockoutEffect == .failure)
        #expect(AttemptResult.signature(verdict(accepted: false, .wrongDevice)).lockoutEffect == .failure)
        #expect(AttemptResult.signature(verdict(accepted: false, .deviceUnknown)).lockoutEffect == .none)
        #expect(AttemptResult.malformedCode.lockoutEffect == .failure)
        #expect(AttemptResult.identityCode(matches: true).lockoutEffect == .success)
        #expect(AttemptResult.identityCode(matches: false).lockoutEffect == .failure)
        #expect(AttemptResult.recoveryUnlock(restored: 2, wrongKey: 0).lockoutEffect == .success)
        #expect(AttemptResult.recoveryUnlock(restored: 2, wrongKey: 1).lockoutEffect == .failure)
        #expect(AttemptResult.recoveryUnlock(restored: 0, wrongKey: 0).lockoutEffect == .none)
    }

    @Test func onlyChangingTheSignatureNeedsTheRecoveryCode() {
        #expect(SensitiveAction.allCases.filter(\.needsRecoveryCode) == [.changeSignature])
    }

    @Test func theRecoveryCodeProvesIdentityOnlyWhenItGivesTheProfilesKey() throws {
        let code = RecoveryCode.generate(), other = RecoveryCode.generate()
        let key = try RecoveryCode.privateKey(for: code).publicKey.rawRepresentation
        #expect(IdentityCheck.codeMatches(code, recoveryPublicKey: key))
        #expect(IdentityCheck.codeMatches(code.lowercased(), recoveryPublicKey: key))     // as `RecoveryCode.normalize` accepts it
        #expect(!IdentityCheck.codeMatches(other, recoveryPublicKey: key))
        #expect(!IdentityCheck.codeMatches(code, recoveryPublicKey: nil))
        #expect(!IdentityCheck.codeMatches("not a code", recoveryPublicKey: key))
    }

    @Test func pairingNeedsARequestAnEnrolledMacAndAFileTheCodeOpened() {
        #expect(PairingRule.shouldPair(requested: true, hasProfile: true, restored: 1))
        #expect(!PairingRule.shouldPair(requested: false, hasProfile: true, restored: 1))
        #expect(!PairingRule.shouldPair(requested: true, hasProfile: false, restored: 1))
        #expect(!PairingRule.shouldPair(requested: true, hasProfile: true, restored: 0))
    }

    @Test func aSignatureIsCountedBeforeAnyFileIsOpened() {
        let recorder = CallRecorder()
        let decision = UnlockAttempt.signature(verdict(accepted: true), count: recorder.count)
        #expect(decision == .openFiles)
        #expect(recorder.calls == [.success])
    }

    @Test func aRejectedSignatureOpensNothing() {
        let saved = CallRecorder()
        let savedDecision = UnlockAttempt.signature(verdict(accepted: false, .scoreTooHigh), count: saved.count)
        #expect(savedDecision == .rejected)
        #expect(saved.calls == [.failure])

        let unsaved = CallRecorder()
        unsaved.saves = false
        let unsavedDecision = UnlockAttempt.signature(verdict(accepted: false, .scoreTooHigh), count: unsaved.count)
        #expect(unsavedDecision == .countNotSaved)
        #expect(unsaved.calls == [.failure])
    }

    @Test func anAcceptedSignatureWhoseCountCannotBeSavedOpensNothing() {
        let recorder = CallRecorder()
        recorder.saves = false
        let decision = UnlockAttempt.signature(verdict(accepted: true), count: recorder.count)
        #expect(decision == .countNotSaved)
        #expect(recorder.calls == [.success])
    }

    @Test func aSignatureFromAnUnknownDeviceIsNotCountedAndOpensNothing() {
        let recorder = CallRecorder()
        let decision = UnlockAttempt.signature(verdict(accepted: false, .deviceUnknown), count: recorder.count)
        #expect(decision == .notCounted)
        #expect(recorder.calls == [])
    }

    @Test func aRecoveryCodeIsCountedAfterItsFilesFromWhatItOpened() {
        let first = URL(fileURLWithPath: "/tmp/first.txt")
        let second = URL(fileURLWithPath: "/tmp/second.txt")
        let cases: [(restored: [URL], wrongKey: [URL], effect: Lockout.Effect)] = [
            ([first], [second], .failure),
            ([first, second], [], .success),
            ([], [], .none),
        ]
        for item in cases {
            for saves in [true, false] {
                let recorder = CallRecorder()
                recorder.saves = saves
                var outcome = UnlockOutcome()
                outcome.restored = item.restored
                outcome.wrongKey = item.wrongKey
                outcome.failures = [.init(url: first, error: LockedFileError.notAirSignFile)]
                let decision = UnlockAttempt.recoveryCode(outcome, count: recorder.count)
                #expect(decision == (saves ? .counted : .countNotSaved))
                #expect(recorder.calls == [item.effect])
            }
        }
    }
}
