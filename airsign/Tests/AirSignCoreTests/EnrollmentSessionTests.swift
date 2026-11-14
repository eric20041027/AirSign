import Foundation
import Testing
import AirSignCore
import AirSignTestSupport

struct EnrollmentSessionTests {
    @Test func threeSteadySignaturesFromOneAirPodAreReadyToConfirm() throws {
        var session = EnrollmentSession()
        let signatures = steadySignatures()
        #expect(session.signatures.isEmpty && session.pending == nil)
        #expect(session.confirmations == 0 && session.strength == nil)

        #expect(session.add(signatures[0], deviceUID: "UID-A") == .needMore(have: 1))
        #expect(session.signatures == Array(signatures.prefix(1)))
        #expect(session.pending == nil && session.confirmations == 0 && session.strength == nil)
        #expect(session.add(signatures[1], deviceUID: "UID-A") == .needMore(have: 2))
        #expect(session.signatures == Array(signatures.prefix(2)))
        #expect(session.pending == nil && session.confirmations == 0 && session.strength == nil)
        #expect(session.add(signatures[2], deviceUID: "UID-A") == .readyToConfirm)
        #expect(session.signatures == signatures)
        #expect(session.pending == (try enroll(signatures, deviceUID: "UID-A")))
        #expect(session.confirmations == 0)
        #expect(session.strength == SignatureStrength.of(signatures))
        #expect(session.strength?.level != .weak)
    }

    @Test func aSignatureFromTheOtherAirPodIsRefusedAndNotAdded() {
        var session = EnrollmentSession()
        let first = steadySignatures()[0]
        #expect(session.add(first, deviceUID: "UID-A") == .needMore(have: 1))
        let before = session
        let other = Signature(samples: strokes(ownerShape, n: 200, side: .left))

        #expect(session.add(other, deviceUID: nil) == .wrongSide(expected: .right))
        #expect(session.signatures == before.signatures)
        #expect(session.pending == before.pending && session.confirmations == before.confirmations)
        #expect(session.strength == before.strength)
    }

    @Test func withoutTheAirPodsAsOutputTheLastSignatureIsTakenBack() throws {
        var session = EnrollmentSession()
        let signatures = steadySignatures()
        #expect(session.add(signatures[0], deviceUID: nil) == .needMore(have: 1))
        #expect(session.signatures == Array(signatures.prefix(1)))
        #expect(session.pending == nil && session.confirmations == 0 && session.strength == nil)
        #expect(session.add(signatures[1], deviceUID: nil) == .needMore(have: 2))
        #expect(session.signatures == Array(signatures.prefix(2)))
        #expect(session.pending == nil && session.confirmations == 0 && session.strength == nil)

        #expect(session.add(signatures[2], deviceUID: nil) == .noOutputDevice)
        #expect(session.signatures == Array(signatures.prefix(2)))
        #expect(session.pending == nil && session.confirmations == 0 && session.strength == nil)
        #expect(session.add(signatures[2], deviceUID: "UID-A") == .readyToConfirm)
        #expect(session.signatures == signatures)
        #expect(session.pending == (try enroll(signatures, deviceUID: "UID-A")))
        #expect(session.confirmations == 0 && session.strength == SignatureStrength.of(signatures))
    }

    @Test func aWeakSignatureIsRefusedAndTheRatingIsKept() {
        var session = EnrollmentSession()
        let weak = Signature(samples: strokes({ ownerShape($0) * 0.1 }, n: 20))
        let rating = SignatureStrength.of([weak, weak, weak])
        #expect(session.add(weak, deviceUID: "UID-A") == .needMore(have: 1))
        #expect(session.signatures == [weak])
        #expect(session.pending == nil && session.confirmations == 0 && session.strength == nil)
        #expect(session.add(weak, deviceUID: "UID-A") == .needMore(have: 2))
        #expect(session.signatures == [weak, weak])
        #expect(session.pending == nil && session.confirmations == 0 && session.strength == nil)

        #expect(session.add(weak, deviceUID: "UID-A") == .tooWeak(rating))
        #expect(session.signatures.isEmpty && session.pending == nil && session.confirmations == 0)
        #expect(session.strength == rating && session.strength?.level == .weak)
        let first = steadySignatures()[0]
        #expect(session.add(first, deviceUID: "UID-A") == .needMore(have: 1))
        #expect(session.signatures == [first])
        #expect(session.pending == nil && session.confirmations == 0 && session.strength == nil)
    }

    @Test func threePassingChecksCompleteTheEnrollment() throws {
        var session = readySession()
        let enrollment = try #require(session.pending)
        let signatures = session.signatures
        let strength = session.strength

        #expect(session.check(signatures[1], deviceUID: "UID-A") == .passed(1))
        #expect(session.pending == enrollment && session.confirmations == 1)
        #expect(session.signatures == signatures && session.strength == strength)
        #expect(session.check(signatures[1], deviceUID: "UID-A") == .passed(2))
        #expect(session.pending == enrollment && session.confirmations == 2)
        #expect(session.signatures == signatures && session.strength == strength)
        #expect(session.check(signatures[1], deviceUID: "UID-A") == .complete(enrollment))
        #expect(session.pending == nil && session.confirmations == 0)
        #expect(session.signatures == signatures && session.strength == strength)
    }

    @Test func oneMissedCheckClearsTheEnrollment() throws {
        var session = readySession()
        let before = session
        #expect(session.check(steadySignatures()[1], deviceUID: "UID-A") == .passed(1))
        #expect(session.pending == before.pending && session.confirmations == 1)
        #expect(session.signatures == before.signatures && session.strength == before.strength)
        let forgery = Signature(samples: strokes(forgeryShape, n: 200))

        #expect(session.check(forgery, deviceUID: "UID-A") == .mismatch(check: 2))
        #expect(session.signatures.isEmpty && session.pending == nil && session.confirmations == 0)
        #expect(session.strength == before.strength)
    }

    @Test func aCheckFromAnUnknownDeviceChangesNothing() throws {
        var session = readySession()
        let signature = steadySignatures()[1]
        #expect(session.check(signature, deviceUID: "UID-A") == .passed(1))
        let before = session
        let enrollment = try #require(before.pending)
        let verdict = verify(signature, deviceUID: nil, against: enrollment)
        #expect(verdict.rejection == .deviceUnknown)

        #expect(session.check(signature, deviceUID: nil) == .notCounted(verdict))
        #expect(session.signatures == before.signatures && session.pending == before.pending)
        #expect(session.confirmations == before.confirmations && session.strength == before.strength)
    }

    @Test func startingOverForgetsTheRating() {
        var session = readySession()
        #expect(session.check(steadySignatures()[1], deviceUID: "UID-A") == .passed(1))
        #expect(!session.signatures.isEmpty && session.pending != nil)
        #expect(session.confirmations == 1 && session.strength != nil)

        session.clear(keepingStrength: false)
        #expect(session.signatures.isEmpty && session.pending == nil)
        #expect(session.confirmations == 0 && session.strength == nil)
    }

    @Test func changingASignatureKeepsItsRecoveryCodeAndClearsTheLockout() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var lockout = Lockout()
        for _ in 0...Lockout.maxFailures { lockout.recordFailure(now: now) }
        #expect(lockout.remaining(now: now) != nil && lockout.failures == 1)
        let recoveryKey = try RecoveryCode.privateKey(for: RecoveryCode.generate()).publicKey.rawRepresentation
        let signatures = steadySignatures()
        let current = Profile(enrollment: try enroll(signatures, deviceUID: "UID-OLD"),
                              recoveryPublicKey: recoveryKey, lockout: lockout, demoMode: true)
        let enrollment = try enroll(signatures, deviceUID: "UID-NEW")

        let result = try EnrollmentCompletion.complete(enrollment, changingSignatureOf: current)
        guard case .signatureChanged(let updated) = result else {
            Issue.record("Changing a signature must keep the existing recovery code.")
            return
        }
        #expect(updated.enrollment == enrollment)
        #expect(updated.recoveryPublicKey == current.recoveryPublicKey && updated.demoMode)
        #expect(updated.lockout.remaining(now: now) == nil && updated.lockout.failures == 0)
        #expect(updated.lockout == Lockout())
    }

    @Test func aFirstEnrollmentWaitsForTheCodeToBeConfirmed() throws {
        let enrollment = try #require(readySession().pending)

        let result = try EnrollmentCompletion.complete(enrollment, changingSignatureOf: nil)
        guard case .awaitingCodeConfirmation(let profile, let code) = result else {
            Issue.record("A first enrollment must wait for recovery code confirmation.")
            return
        }
        let normalized = try RecoveryCode.normalize(code)
        #expect(normalized.count == 32 && normalized == code.replacingOccurrences(of: "-", with: ""))
        #expect(profile.enrollment == enrollment)
        #expect(profile.recoveryPublicKey == (try RecoveryCode.privateKey(for: code).publicKey.rawRepresentation))
        #expect(profile.lockout == Lockout() && !profile.demoMode)
    }

    private func steadySignatures() -> [Signature] {
        [190, 200, 210].map { Signature(samples: strokes(ownerShape, n: $0)) }
    }

    private func readySession() -> EnrollmentSession {
        var session = EnrollmentSession()
        for signature in steadySignatures() { _ = session.add(signature, deviceUID: "UID-A") }
        return session
    }
}
