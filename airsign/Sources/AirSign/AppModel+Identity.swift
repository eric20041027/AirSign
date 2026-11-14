import AirSignCore
import Foundation

extension AppModel {
    enum IdentityPurpose {
        case changeSignature, enableDemo
        #if AIRSIGN_LAB
        case changeSignatureFromLab, openLab
        #endif

        var action: SensitiveAction {
            switch self {
            case .changeSignature: return .changeSignature
            case .enableDemo: return .enableDemo
            #if AIRSIGN_LAB
            case .changeSignatureFromLab: return .changeSignature
            case .openLab: return .openLab
            #endif
            }
        }

        var appAction: AppAction {
            switch action {
            case .changeSignature: return .changeSignature
            case .enableDemo: return .setDemoMode
            case .openLab: return .labAction
            }
        }
    }

    // MARK: - Proving identity (change signature, open the test lab)

    func beginChangeSignature() {
        guard allows(.changeSignature) else { return }
        beginIdentityCheck(.changeSignature, prompt: "Changing your signature needs your recovery code: press “Use recovery code…”.")
    }

    func beginIdentityCheck(_ purpose: IdentityPurpose, prompt: String) {
        guard allows(purpose.appAction) else { return }
        stopCapture()
        identityPurpose = purpose
        identityNeedsCode = purpose.action.needsRecoveryCode
        lastVerdict = nil
        livePath = []
        screen = .confirmIdentity
        say(prompt, .neutral)
    }

    func confirmIdentity(_ signature: Signature) {
        guard allows(.signatureTry) else { return }
        guard let current = profile else { return }
        guard !identityNeedsCode else {
            say("Changing the signature needs the recovery code: use “Use recovery code…”.", .warn)
            return
        }
        // Never the demo slider here: proving identity always uses the enrolled threshold.
        let verdict = verify(signature, deviceUID: AudioDeviceIdentity.headphoneUID(), against: current.enrollment)
        lastVerdict = verdict.rejection == .deviceUnknown ? nil : verdict
        if verdict.rejection == .deviceUnknown {
            say(Self.describe(verdict), .warn)
            return
        }
        guard adjustLockout(AttemptResult.signature(verdict).lockoutEffect) else { return }
        if verdict.accepted {
            identityConfirmed()
        } else {
            say(current.demoMode ? Self.describe(verdict) : "Not recognized.", .bad)
        }
    }

    func identityConfirmed() {
        identityNeedsCode = false
        switch identityPurpose {
        case .changeSignature:
            resetLabReturn()
            startReenrollment()
        #if AIRSIGN_LAB
        case .changeSignatureFromLab:
            returnToLabAfterEnroll = true
            startReenrollment()
        case .openLab:
            lastVerdict = nil
            livePath = []
            screen = .lab
            say("Test lab open. Pick the tester and scenario, then press Space.", .good)
        #endif
        case .enableDemo:
            if var current = profile {
                current.demoMode = true
                guard persist(current) else { return }
            }
            lastVerdict = nil
            livePath = []
            screen = .home
            say("Demo mode on: scores, lights and reasons are shown.", .good)
        }
    }

    private func startReenrollment() {
        isReenrolling = true
        clearEnrollment()
        livePath = []
        lastVerdict = nil
        screen = .enroll
        say("Now sign your new signature 3 times.", .neutral)
    }

    #if !AIRSIGN_LAB
    func resetLabReturn() {}
    #endif
}
