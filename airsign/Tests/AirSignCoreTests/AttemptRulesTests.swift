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
    var calls: [String] = []
    var saves = true
    var outcome = UnlockOutcome()

    func count(_ effect: Lockout.Effect) -> Bool {
        calls.append("count:\(effect)")
        return saves
    }

    func open() -> UnlockOutcome {
        calls.append("open")
        return outcome
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
        recorder.outcome.restored = [URL(fileURLWithPath: "/tmp/restored.txt")]
        let step = UnlockAttempt.signature(verdict(accepted: true), count: recorder.count, openFiles: recorder.open)
        #expect(recorder.calls == ["count:success", "open"])
        guard case .opened(let outcome) = step else {
            Issue.record("a saved accepted signature must open its files")
            return
        }
        #expect(outcome.restored == recorder.outcome.restored)
    }

    @Test func aRejectedSignatureOpensNothing() {
        let saved = CallRecorder()
        let savedStep = UnlockAttempt.signature(verdict(accepted: false, .scoreTooHigh), count: saved.count, openFiles: saved.open)
        #expect(saved.calls == ["count:failure"])
        guard case .rejected = savedStep else {
            Issue.record("a rejected signature must report its rejection after saving the count")
            return
        }

        let unsaved = CallRecorder()
        unsaved.saves = false
        let unsavedStep = UnlockAttempt.signature(verdict(accepted: false, .scoreTooHigh), count: unsaved.count, openFiles: unsaved.open)
        #expect(unsaved.calls == ["count:failure"])
        guard case .countNotSaved = unsavedStep else {
            Issue.record("a failed save must take precedence over reporting the rejection")
            return
        }
    }

    @Test func anAcceptedSignatureWhoseCountCannotBeSavedOpensNothing() {
        let recorder = CallRecorder()
        recorder.saves = false
        let step = UnlockAttempt.signature(verdict(accepted: true), count: recorder.count, openFiles: recorder.open)
        #expect(recorder.calls == ["count:success"])
        guard case .countNotSaved = step else {
            Issue.record("an accepted signature must wait for a saved count before opening files")
            return
        }
    }

    @Test func aSignatureFromAnUnknownDeviceIsNotCountedAndOpensNothing() {
        let recorder = CallRecorder()
        let step = UnlockAttempt.signature(verdict(accepted: false, .deviceUnknown), count: recorder.count, openFiles: recorder.open)
        #expect(recorder.calls.isEmpty)
        guard case .notCounted = step else {
            Issue.record("an unknown device must leave the count and files alone")
            return
        }
    }

    @Test func aRecoveryCodeIsCountedAfterItsFilesFromWhatItOpened() {
        let first = URL(fileURLWithPath: "/tmp/first.txt")
        let second = URL(fileURLWithPath: "/tmp/second.txt")
        let cases: [(restored: [URL], wrongKey: [URL], effect: String)] = [
            ([first], [second], "failure"),
            ([first, second], [], "success"),
            ([], [], "none"),
        ]
        for item in cases {
            for saves in [true, false] {
                let recorder = CallRecorder()
                recorder.saves = saves
                recorder.outcome.restored = item.restored
                recorder.outcome.wrongKey = item.wrongKey
                recorder.outcome.failures = [.init(url: first, error: LockedFileError.notAirSignFile)]
                let step = UnlockAttempt.recoveryCode(openFiles: recorder.open, count: recorder.count)
                #expect(recorder.calls == ["open", "count:\(item.effect)"])
                let outcome: UnlockOutcome
                switch step {
                case .counted(let opened):
                    #expect(saves)
                    outcome = opened
                case .countNotSaved(let opened):
                    #expect(!saves)
                    outcome = opened
                }
                #expect(outcome.restored == item.restored)
                #expect(outcome.wrongKey == item.wrongKey)
                #expect(outcome.failures.map(\.url) == [first])
                #expect(outcome.failures.first?.error as? LockedFileError == .notAirSignFile)
            }
        }
    }
}
