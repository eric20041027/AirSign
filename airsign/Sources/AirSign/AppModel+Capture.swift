import AirSignCore
import Foundation

extension AppModel {
    // MARK: - Capture

    func toggleCapture() {
        let action: AppAction = screen == .enroll ? .enrollmentStep : (screen == .lab ? .labAction : .signatureTry)
        guard allows(action) else { return }
        if isCapturing {
            stopCapture()
            say("Cancelled.", .neutral)
            return
        }
        let countsTowardLockout = screen == .unlock || screen == .confirmIdentity
        if countsTowardLockout,
           let refusal = AttemptGate.refusal(lockout: profile?.lockout, saveBlocked: saveBlocked, now: Date(), boot: BootClock.current()) {
            switch refusal {
            case .coolingDown(let remaining):
                say("Too many tries. Wait \(Int(remaining.rounded(.up))) s.", .bad)
            case .cannotSave:
                say("AirSign can't save its settings, so unlocking is paused. Check the AirSign folder in Application Support.", .bad)
            }
            return
        }
        guard canStartCapture() else { return }
        recorder.reset()
        signingSamples = []
        livePath = []
        lastVerdict = nil
        isCapturing = true
        say("Ready. Start signing, then hold still.", .neutral)
    }

    private func canStartCapture() -> Bool {
        if screen == .enroll, AudioDeviceIdentity.headphoneUID() == nil {
            say("Set the sound output to your AirPods (Control Center → Sound), then enroll.", .bad)
            return false
        }
        // No signing at all without the enrolled AirPods as output, so no score can leak from an uncounted try.
        if screen != .enroll, profile?.enrollment.deviceUID != nil, AudioDeviceIdentity.headphoneUID() == nil {
            say("Set the sound output to your AirPods (Control Center → Sound), then sign.", .bad)
            return false
        }
        if screen == .confirmIdentity, identityNeedsCode {
            say("Changing the signature needs the recovery code: use “Use recovery code…”.", .warn)
            return false
        }
        #if AIRSIGN_LAB
        if screen == .lab, testTester.trimmingCharacters(in: .whitespaces).isEmpty {
            say("Type the tester's name first.", .warn)
            return false
        }
        if screen == .lab, testOwner.trimmingCharacters(in: .whitespaces).isEmpty {
            say("Type the owner's name first.", .warn)
            return false
        }
        #endif
        guard case .streaming = motionStatus else {
            say("No AirPod data. Pinch the AirPod so a finger covers its sensor, and keep the other one in the case.", .bad)
            return false
        }
        return true
    }

    func stopCapture() {
        isCapturing = false
        recorder.reset()
        signingSamples = []
    }

    func handle(_ sample: MotionSample) {
        guard isCapturing else { return }
        switch recorder.feed(sample) {
        case .waiting:
            break
        case .recording:
            if signingSamples.isEmpty { say("Signing…", .neutral) }
            signingSamples.append(sample)
            livePath = Signature(samples: signingSamples).path
        case .finished(let rows):
            stopCapture()
            let signature = Signature(samples: rows)
            livePath = signature.path
            complete(signature, rows: rows)
        case .aborted(let reason):
            stopCapture()
            say(Self.describe(reason), .warn)
        }
    }

    func tick() {
        motion.refreshStaleness()
        let remaining = profile?.lockout.remaining(now: Date(), boot: BootClock.current())
        if remaining != lockoutRemaining { lockoutRemaining = remaining }
        guard isCapturing else { return }
        let age = motion.lastSampleDate.map { Date().timeIntervalSince($0) } ?? .infinity
        if case .aborted(let reason)? = recorder.checkStall(lastSampleAge: age) {
            stopCapture()
            say(Self.describe(reason), .warn)
        } else if signingSamples.isEmpty, age > 1 {
            stopCapture()
            say("No AirPod data. Keep a finger over the AirPod's sensor.", .bad)
        }
    }

    private func complete(_ signature: Signature, rows: [MotionSample]) {
        switch screen {
        case .enroll:
            if pendingEnrollment != nil {
                checkEnrollment(signature)
            } else {
                addEnrollment(signature, rows: rows)
            }
        case .unlock: verifyAndUnlock(signature)
        case .confirmIdentity: confirmIdentity(signature)
        case .lab: labVerify(signature, rows: rows)
        case .home, .blocked: break
        }
    }

    func cancelToHome() {
        guard allows(.cancel) else { return }
        stopCapture()
        sampleCandidate = nil
        identityNeedsCode = false
        isReenrolling = false
        isResetting = false
        resetLabReturn()
        clearEnrollment(keepingStrength: false)
        pendingProfile = nil
        recoveryCodeToShow = nil
        pendingUnlock = []
        lastVerdict = nil
        livePath = []
        screen = restingScreen
        if let blockReason {
            say(Self.describe(blockReason), .bad)
        } else {
            say("", .neutral)
        }
    }

    #if !AIRSIGN_LAB
    func labVerify(_ signature: Signature, rows: [MotionSample]) {}
    #endif
}
