#if AIRSIGN_LAB
import AirSignCore
import AirSignLab
import Foundation

extension AppModel {
    func recordEnrollmentRows(_ rows: [MotionSample], result: EnrollmentSession.AddResult) {
        switch result {
        case .wrongSide: break
        default: enrolledRows.append(rows)
        }
    }

    func removeLastEnrollmentRows() {
        enrolledRows.removeLast()
    }

    func clearEnrollmentRows() {
        enrolledRows = []
    }

    func resetLabReturn() {
        returnToLabAfterEnroll = false
    }

    func beginLab() {
        guard allows(.labAction) else { return }
        guard testMode else { return }
        beginIdentityCheck(.openLab, prompt: "The owner opens the test lab: sign once, or use the recovery code.")
    }

    // MARK: - Test lab (only with --test-mode)

    /// The owner re-enrolls from inside the lab so the templates' raw motion is logged too.
    func reenrollOwnerFromLab() {
        guard allows(.labAction) else { return }
        guard testMode, screen == .lab else { return }
        guard !testOwner.trimmingCharacters(in: .whitespaces).isEmpty else {
            say("Type the owner's name first, so the enrollment is logged under the right person.", .warn)
            return
        }
        beginIdentityCheck(.changeSignatureFromLab, prompt: "Re-enrolling the owner needs the recovery code: press “Use recovery code…”.")
    }

    func labCount(for scenario: TestScenario) -> Int {
        labCounts[labKey(scenario)] ?? 0
    }

    func leaveLab() {
        guard allows(.labAction) else { return }
        cancelToHome()
    }

    func labVerify(_ signature: Signature, rows: [MotionSample]) {
        guard allows(.labAction) else { return }
        guard let current = profile else {
            say("Enroll the owner first.", .warn)
            return
        }
        let verdict = verify(signature, deviceUID: AudioDeviceIdentity.headphoneUID(), against: current.enrollment)
        if verdict.rejection == .deviceUnknown {
            lastVerdict = nil
            say(Self.describe(verdict), .warn)
            return
        }
        lastVerdict = verdict
        var labels = currentLabels(scenario: testScenario)
        labels.enrollment = current.enrollment.fingerprint
        do {
            try attemptLog.write(mode: .verify, labels: labels, samples: rows, verdict: verdict)
            labCounts[labKey(testScenario), default: 0] += 1
            say("\(Self.describe(verdict)) Logged.", verdict.accepted ? .good : .bad)
        } catch {
            say("\(Self.describe(verdict)) Could not save the test record: \(error.localizedDescription)", .bad)
        }
    }

    func logEnrollment(_ enrollment: Enrollment) {
        guard testMode else { return }
        var labels = currentLabels(scenario: .owner)
        labels.tester = testOwner
        labels.enrollment = enrollment.fingerprint
        do {
            for rows in enrolledRows {
                try attemptLog.write(mode: .enroll, labels: labels, samples: rows, verdict: nil)
            }
        } catch {
            say("Saved the signature, but could not save its test record: \(error.localizedDescription)", .bad)
        }
    }

    private func currentLabels(scenario: TestScenario) -> AttemptLabels {
        AttemptLabels(tester: testTester.trimmingCharacters(in: .whitespaces), scenario: scenario.rawValue,
                      session: testSession.rawValue, owner: testOwner.trimmingCharacters(in: .whitespaces))
    }

    private func labKey(_ scenario: TestScenario) -> String {
        "\(testSession.rawValue)|\(testTester.trimmingCharacters(in: .whitespaces))|\(scenario.rawValue)"
    }
}
#endif
