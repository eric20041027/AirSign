import AirSignCore
import Foundation

extension AppModel {
    /// Rating of the signature this Mac has enrolled, for Settings.
    var enrolledStrength: SignatureStrength? {
        profile.map { SignatureStrength.of($0.enrollment.templates) }
    }

    var demoMode: Bool { profile?.demoMode ?? false }

    /// Adds the signature that just unlocked strongly, so AirSign follows how the signature drifts over time.
    func addSampleFromLastUnlock() {
        guard var current = profile, let signature = sampleCandidate else { return }
        do {
            current.enrollment = try adding(signature, to: current.enrollment)
            guard persist(current) else { return }
            sampleCandidate = nil
            let e = current.enrollment
            say("Added. AirSign now compares with \(e.templates.count) signatures (\(e.addedCount) added after unlocking); "
                + "the pass mark didn't change.", .good)
        } catch {
            say("Could not add this signature: \(error.localizedDescription)", .bad)
        }
    }

    func removeAddedSamples() {
        guard var current = profile, current.enrollment.addedCount > 0 else { return }
        current.enrollment = removingAddedSamples(from: current.enrollment)
        guard persist(current) else { return }
        say("Removed the added signatures; AirSign compares with your enrolled ones only.", .good)
    }

    func forgetPairedMacs() {
        do {
            try store.forgetPairedMacs()
            pairedMacs = .readable(count: 0)
            say("Forgot all paired Macs. Their files open here only with their recovery codes.", .good)
        } catch {
            say("Could not forget paired Macs: \(error.localizedDescription)", .bad)
        }
    }

    // MARK: - Settings

    /// Turning demo mode off is free; turning it on needs the owner, since it shows scores.
    func setDemoMode(_ on: Bool) {
        guard var current = profile, on != current.demoMode else { return }
        if on {
            beginIdentityCheck(.enableDemo, prompt: "Turning demo mode on shows scores: sign once, or use the recovery code.")
            return
        }
        current.demoMode = false
        guard persist(current) else { return }
        thresholdOverride = nil
    }
}
