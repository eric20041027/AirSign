import AirSignCore
import AppKit
import Foundation

extension AppModel {
    // MARK: - Unlock

    func verifyAndUnlock(_ signature: Signature) {
        guard allows(.signatureTry) else { return }
        guard let current = profile else {
            say("This Mac has no AirSign signature. Use the recovery code.", .warn)
            return
        }
        let verdict = verify(signature, deviceUID: AudioDeviceIdentity.headphoneUID(), against: current.enrollment,
                             threshold: thresholdOverride)
        lastVerdict = verdict.rejection == .deviceUnknown ? nil : verdict
        if verdict.rejection != .deviceUnknown {
            sampleCandidate = verdict.canBecomeSample ? signature : nil
        }
        let urls = pendingUnlock
        beginFileWork("Unlocking", count: urls.count)
        Task { await unlockWithSignature(verdict, urls: urls, demoMode: current.demoMode) }
    }

    private func unlockWithSignature(_ verdict: Verdict, urls: [URL], demoMode: Bool) async {
        defer { endFileWork() }
        do {
            let step = try await UnlockAttempt.signature(verdict, count: adjustLockout) {
                let master = try store.masterKey()
                let paired = try store.pairedRecoveryKeys()
                let keys = UnlockKeys(master: master, paired: paired)
                let outcome = await fileWorker.unlock(urls, keys: keys)
                pendingUnlock = outcome.wrongKey
                return outcome
            }
            switch step {
            case .notCounted:
                say(Self.describe(verdict), .warn)
            case .rejected:
                say(demoMode ? Self.describe(verdict) : "Not recognized.", .bad)
            case .countNotSaved:
                return
            case .opened(let outcome):
                reportSignatureUnlock(outcome, verdict: verdict, demoMode: demoMode)
            }
        } catch ProfileStoreError.keyMissing {
            block(.keyMissing)
        } catch {
            say("Could not read AirSign's keys: \(error.localizedDescription)", .bad)
        }
    }

    private func reportSignatureUnlock(_ outcome: UnlockOutcome, verdict: Verdict, demoMode: Bool) {
        if outcome.restored.isEmpty, outcome.failures.isEmpty, !outcome.wrongKey.isEmpty {
            say("Your signature matched, but this file was locked on a Mac that isn't paired with this one. "
                + "Use that Mac's recovery code once and tick “Remember on this Mac”: after that, your AirPods "
                + "and signature open its files here too.", .warn)
            return
        }
        // Outside demo mode the similarity shows only after a pass, so it can't guide an imitator.
        let heading = demoMode
            ? Self.describe(verdict)
            : "Recognized" + (verdict.similarity.map { " (similarity \($0)%)" } ?? "") + "."
        let foreign = outcome.wrongKey.map { "\($0.lastPathComponent): locked on a Mac that isn't paired with this one. Use its recovery code." }
        report(heading: heading, outcome: outcome, extra: foreign, stayOnScreen: true)
    }

    /// `rememberOnThisMac` pairs this Mac with the one that locked the file, once the code has opened it.
    func submitRecoveryCode(_ code: String, rememberOnThisMac: Bool = false) {
        guard allows(.recoveryCodeTry) else { return }
        if let refusal = AttemptGate.refusal(lockout: profile?.lockout, saveBlocked: saveBlocked, now: Date(), boot: BootClock.current()) {
            switch refusal {
            case .coolingDown(let remaining):
                say("Too many tries. Wait \(Int(remaining.rounded(.up))) s.", .bad)
            case .cannotSave:
                say("AirSign can't save its settings, so unlocking is paused.", .bad)
            }
            return
        }
        guard (try? RecoveryCode.normalize(code)) != nil else {
            guard adjustLockout(AttemptResult.malformedCode.lockoutEffect) else { return }
            say("That is not a valid recovery code (32 characters).", .bad)
            return
        }
        if screen == .confirmIdentity {
            let matches = IdentityCheck.codeMatches(code, recoveryPublicKey: profile?.recoveryPublicKey)
            guard adjustLockout(AttemptResult.identityCode(matches: matches).lockoutEffect) else { return }
            guard matches else {
                say("Wrong recovery code.", .bad)
                return
            }
            identityConfirmed()
            return
        }
        let urls = pendingUnlock
        beginFileWork("Unlocking", count: urls.count)
        Task { await unlockWithRecoveryCode(code, urls: urls, rememberOnThisMac: rememberOnThisMac) }
    }

    private func unlockWithRecoveryCode(_ code: String, urls: [URL], rememberOnThisMac: Bool) async {
        defer { endFileWork() }
        let step = await UnlockAttempt.recoveryCode(openFiles: {
            let outcome = await fileWorker.unlock(urls, recoveryCode: code)
            pendingUnlock = outcome.wrongKey
            return outcome
        }, count: adjustLockout)
        guard case .counted(let outcome) = step else { return }
        var extra = outcome.wrongKey.map { "\($0.lastPathComponent): wrong recovery code." }
        if PairingRule.shouldPair(requested: rememberOnThisMac, hasProfile: profile != nil, restored: outcome.restored.count) {
            extra.append(pairThisMac(withCode: code))
        }
        report(heading: "Recovery code", outcome: outcome, extra: extra)
    }

    /// Only a Mac with its own enrolled signature can be paired; a public Mac just uses the code once.
    private func pairThisMac(withCode code: String) -> String {
        defer { pairedMacs = store.pairedMacs() }
        do {
            let added = try store.addPairedRecoveryKey(RecoveryCode.privateKey(for: code))
            // A failed read after adding must still report a pairing error.
            _ = try store.pairedRecoveryKeys()
            return added
                ? "Paired: files from that Mac now open here with your AirPods and signature."
                : "This Mac was already paired with that one."
        } catch {
            return "Could not pair this Mac: \(error.localizedDescription)"
        }
    }

    /// `stayOnScreen` keeps a signature unlock on its result, so the signature can still be turned and shown.
    private func report(heading: String, outcome: UnlockOutcome, extra: [String], stayOnScreen: Bool = false) {
        let errors = outcome.failures.map { "\($0.url.lastPathComponent): \(Self.describe($0.error))" }
        let lines = [heading] + outcome.restored.map { "Unlocked \($0.lastPathComponent)" } + extra + errors
        say(lines.joined(separator: "\n"), outcome.allDone ? .good : .bad)
        // In demo mode Finder would cover the signature the audience is looking at.
        if !outcome.restored.isEmpty, !demoMode { NSWorkspace.shared.activateFileViewerSelecting(outcome.restored) }
        if outcome.allDone, !stayOnScreen { screen = restingScreen }
    }

    /// A signature unlock that opened everything: the unlock screen now only shows the result.
    var unlockFinished: Bool {
        screen == .unlock && pendingUnlock.isEmpty && lastVerdict?.accepted == true
    }

}
