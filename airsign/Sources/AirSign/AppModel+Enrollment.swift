import AirSignCore
import Foundation

extension AppModel {
    // MARK: - Enrollment

    func beginReset() {
        cancelToHome()
        isResetting = true
        screen = .enroll
        say("Sign 3 times the same way to enroll a new signature. Nothing is replaced until you confirm the new recovery code.", .neutral)
    }

    func addEnrollment(_ signature: Signature, rows: [MotionSample]) {
        let result = enrollmentSession.add(signature, deviceUID: AudioDeviceIdentity.headphoneUID())
        recordEnrollmentRows(rows, result: result)
        finishEnrollment(result)
    }

    private func finishEnrollment(_ result: EnrollmentSession.AddResult) {
        switch result {
        case .wrongSide(let expected):
            say("Use the same AirPod as your first signature (\(expected.rawValue)).", .warn)
        case .needMore(let have):
            say("Got \(have) of \(MatcherConfig.enrollCount). Sign again the same way.", .good)
        case .noOutputDevice:
            removeLastEnrollmentRows()
            say("Set the sound output to your AirPods (Control Center → Sound), then sign once more.", .bad)
        case .tooWeak(let strength):
            clearEnrollment()
            let reasons = strength.issues.map { Self.describe($0, strength.metrics) }.joined(separator: "; ")
            say("This signature is too easy to copy: \(reasons). Enroll again with a longer, bigger signature that changes direction more.", .bad)
        case .cannotBuild(let description):
            clearEnrollment()
            say("Could not build the signature: \(description). Start again.", .bad)
        case .readyToConfirm:
            say("Now sign \(MatcherConfig.confirmCount) more times the same way, to check AirSign recognizes you.", .good)
        }
    }

    /// Every check must pass; one miss means the enrolled signatures weren't steady enough to rely on.
    func checkEnrollment(_ signature: Signature) {
        guard enrollmentSession.pending != nil else { return }
        switch enrollmentSession.check(signature, deviceUID: AudioDeviceIdentity.headphoneUID()) {
        case .notCounted(let verdict):
            say(Self.describe(verdict), .warn)
        case .mismatch(let check):
            clearEnrollment()
            say("Check \(check) of \(MatcherConfig.confirmCount) didn't match, so the enrolled signatures weren't steady enough. "
                + "Enroll again, signing the same way each time.", .bad)
        case .passed(let passed):
            say("Check \(passed) of \(MatcherConfig.confirmCount) passed. Sign again.", .good)
        case .complete(let enrollment):
            finalizeEnrollment(enrollment)
        }
    }

    private func finalizeEnrollment(_ enrollment: Enrollment) {
        do {
            switch try EnrollmentCompletion.complete(enrollment, changingSignatureOf: isReenrolling ? profile : nil) {
            case .signatureChanged(let updated):
                try save(updated)
                logEnrollment(enrollment)
                isReenrolling = false
                clearEnrollment()
                #if AIRSIGN_LAB
                screen = returnToLabAfterEnroll ? .lab : .home
                returnToLabAfterEnroll = false
                #else
                screen = .home
                #endif
                say("New signature saved. Your locked files open with it.", .good)
            case .awaitingCodeConfirmation(let pending, let code):
                pendingProfile = pending
                recoveryCodeToShow = code
                say("Write down your recovery code. Your signature is saved when you confirm.", .good)
            }
        } catch ProfileStoreError.keyMissing {
            block(.keyMissing)
        } catch {
            clearEnrollment()
            say("Could not save the signature: \(error.localizedDescription). Start again.", .bad)
        }
    }

    func confirmRecoveryCodeWritten() {
        guard let pending = pendingProfile else { return }
        recoveryCodeToShow = nil
        pendingProfile = nil
        do {
            try store.createProfile(pending, replacingExisting: isResetting)
            profile = pending
            pairedMacs = .readable(count: 0)
            blockReason = nil
            isResetting = false
        } catch {
            isResetting = false
            clearEnrollment()
            if case ProfileStoreError.keyMissing = error {
                block(.keyMissing)
                return
            }
            screen = restingScreen
            say("Could not save the signature: \(error.localizedDescription). Enroll again.", .bad)
            return
        }
        logEnrollment(pending.enrollment)
        clearEnrollment()
        screen = pendingUnlock.isEmpty ? .home : .unlock
        say(pendingUnlock.isEmpty ? "Right-click any file in Finder → Lock with AirSign." : "Now sign to unlock.", .neutral)
    }

    func restartEnrollment() {
        stopCapture()
        clearEnrollment(keepingStrength: false)
        livePath = []
        say("Start over: sign 3 times the same way.", .neutral)
    }

    func clearEnrollment(keepingStrength: Bool = true) {
        enrollmentSession.clear(keepingStrength: keepingStrength)
        clearEnrollmentRows()
    }

    #if !AIRSIGN_LAB
    func recordEnrollmentRows(_ rows: [MotionSample], result: EnrollmentSession.AddResult) {}

    func removeLastEnrollmentRows() {}

    func logEnrollment(_ enrollment: Enrollment) {}

    func clearEnrollmentRows() {}
    #endif
}
