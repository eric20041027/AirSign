import AirSignCore
import AppKit
import CryptoKit
import Foundation

enum Tone {
    case neutral, good, warn, bad
}

/// Drives every flow: enroll, lock, unlock by signature or recovery code, changing the signature,
/// and (only when launched with `--test-mode`) the test lab.
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case enroll, home, unlock, confirmIdentity, lab
    }

    @Published private(set) var profile: Profile?
    @Published private(set) var screen: Screen = .home
    @Published private(set) var motionStatus: MotionStatus = .waitingForAirPods
    @Published private(set) var isCapturing = false
    @Published private(set) var livePath: [SIMD3<Double>] = []
    @Published private(set) var message = ""
    @Published private(set) var tone: Tone = .neutral
    @Published private(set) var lastVerdict: Verdict?
    @Published private(set) var enrolledSoFar: [Signature] = []
    /// Built from the enrolled signatures; kept only after `MatcherConfig.confirmCount` checks all pass.
    @Published private(set) var pendingEnrollment: Enrollment?
    @Published private(set) var confirmations = 0
    @Published private(set) var isReenrolling = false
    @Published private(set) var recoveryCodeToShow: String?
    @Published private(set) var pendingUnlock: [URL] = []
    @Published private(set) var lockoutRemaining: TimeInterval?
    /// Set while the profile can't be written: attempts are refused so the lockout can't be dodged.
    @Published private(set) var saveBlocked = false
    @Published private(set) var pairedMacCount = 0
    @Published var thresholdOverride: Double?

    /// `open -a AirSign --args --test-mode` adds the test lab. Lab attempts open no files, so they
    /// never count toward the lockout; every other flow keeps it.
    let testMode = CommandLine.arguments.contains("--test-mode")
    @Published var testOwner = "Eric"
    @Published var testTester = ""
    @Published var testSession = TestSession.tonight
    @Published var testScenario = TestScenario.owner
    @Published private(set) var labCounts: [String: Int] = [:]

    private let store = ProfileStore(directory: ProfileStore.defaultDirectory, secrets: KeychainSecretStore())
    private let attemptLog = AttemptLog(directory: AttemptLog.defaultDirectory)
    private let motion = HeadphoneMotionSource()
    private var recorder = SignatureRecorder()
    private var signingSamples: [MotionSample] = []
    private var enrolledRows: [[MotionSample]] = []
    /// A first enrollment waits here until the user confirms the recovery code, so quitting early saves nothing.
    private var pendingProfile: Profile?
    private var identityPurpose = IdentityPurpose.changeSignature
    private var returnToLabAfterEnroll = false
    private var timer: Timer?

    private enum IdentityPurpose {
        case changeSignature, changeSignatureFromLab, openLab, enableDemo

        /// One lucky imitation must not be enough to replace the owner's signature.
        var needsRecoveryCode: Bool { self == .changeSignature || self == .changeSignatureFromLab }
    }

    /// True while the identity screen accepts only the recovery code.
    @Published private(set) var identityNeedsCode = false

    var demoMode: Bool { profile?.demoMode ?? true }

    init() {
        do {
            profile = try store.load()
        } catch {
            NSLog("AirSign: could not read profile: %@", error.localizedDescription)
            say("Your AirSign profile could not be read. Enroll again; locked files still open with the recovery code.", .bad)
        }
        screen = profile == nil ? .enroll : .home
        pairedMacCount = (try? store.pairedRecoveryKeys().count) ?? 0
        motion.onSample = { [weak self] sample in MainActor.assumeIsolated { self?.handle(sample) } }
        motion.onStatus = { [weak self] status in MainActor.assumeIsolated { self?.motionStatus = status } }
        motion.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: - Files

    /// Finder and `open -a AirSign` land here: `.airsign` files unlock, everything else locks.
    func handleOpen(_ urls: [URL]) {
        let locked = urls.filter { $0.pathExtension.lowercased() == FileLocker.lockedExtension }
        let plain = urls.filter { $0.pathExtension.lowercased() != FileLocker.lockedExtension }
        if !plain.isEmpty { lock(plain) }
        if !locked.isEmpty { beginUnlock(locked) }
        NSApp.activate()
    }

    func lock(_ urls: [URL]) {
        guard let profile else {
            screen = .enroll
            say("Enroll your signature first, then lock files.", .warn)
            return
        }
        do {
            let master = try store.masterKey()
            let recoveryKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: profile.recoveryPublicKey)
            var failed = false
            let lines = urls.map { url -> String in
                do {
                    let out = try FileLocker().lock(url, masterKey: master, recoveryPublicKey: recoveryKey)
                    return "Locked \(url.lastPathComponent) → \(out.lastPathComponent) (original moved to the Trash)"
                } catch {
                    failed = true
                    return "\(url.lastPathComponent): \(Self.describe(error))"
                }
            }
            say(lines.joined(separator: "\n"), failed ? .bad : .good)
        } catch {
            say("Could not read AirSign's keys: \(error.localizedDescription)", .bad)
        }
    }

    func beginUnlock(_ urls: [URL]) {
        stopCapture()
        pendingUnlock = urls
        lastVerdict = nil
        livePath = []
        screen = .unlock
        say(profile == nil ? "This Mac has no AirSign signature. Use the recovery code." : "Press Space, sign, then hold still.", .neutral)
    }

    // MARK: - Capture

    func toggleCapture() {
        if isCapturing {
            stopCapture()
            say("Cancelled.", .neutral)
            return
        }
        let countsTowardLockout = screen == .unlock || screen == .confirmIdentity
        if countsTowardLockout, let remaining = profile?.lockout.remaining(now: Date()) {
            say("Too many tries. Wait \(Int(remaining.rounded(.up))) s.", .bad)
            return
        }
        if countsTowardLockout, saveBlocked {
            say("AirSign can't save its settings, so unlocking is paused. Check the AirSign folder in Application Support.", .bad)
            return
        }
        if screen == .enroll, AudioDeviceIdentity.headphoneUID() == nil {
            say("Set the sound output to your AirPods (Control Center → Sound), then enroll.", .bad)
            return
        }
        // No signing at all without the enrolled AirPods as output, so no score can leak from an uncounted try.
        if screen != .enroll, profile?.enrollment.deviceUID != nil, AudioDeviceIdentity.headphoneUID() == nil {
            say("Set the sound output to your AirPods (Control Center → Sound), then sign.", .bad)
            return
        }
        if screen == .confirmIdentity, identityNeedsCode {
            say("Changing the signature needs the recovery code: use “Use recovery code…”.", .warn)
            return
        }
        if screen == .lab, testTester.trimmingCharacters(in: .whitespaces).isEmpty {
            say("Type the tester's name first.", .warn)
            return
        }
        guard case .streaming = motionStatus else {
            say("No AirPod data. Pinch the AirPod so a finger covers its sensor, and keep the other one in the case.", .bad)
            return
        }
        recorder.reset()
        signingSamples = []
        livePath = []
        lastVerdict = nil
        isCapturing = true
        say("Ready. Start signing, then hold still.", .neutral)
    }

    private func stopCapture() {
        isCapturing = false
        recorder.reset()
        signingSamples = []
    }

    private func handle(_ sample: MotionSample) {
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

    private func tick() {
        motion.refreshStaleness()
        let remaining = profile?.lockout.remaining(now: Date())
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
        case .home: break
        }
    }

    // MARK: - Enrollment

    private func addEnrollment(_ signature: Signature, rows: [MotionSample]) {
        if let first = enrolledSoFar.first, first.side != signature.side {
            say("Use the same AirPod as your first signature (\(first.side.rawValue)).", .warn)
            return
        }
        enrolledSoFar.append(signature)
        enrolledRows.append(rows)
        guard enrolledSoFar.count >= MatcherConfig.enrollCount else {
            say("Got \(enrolledSoFar.count) of \(MatcherConfig.enrollCount). Sign again the same way.", .good)
            return
        }
        finishEnrollment()
    }

    private func finishEnrollment() {
        guard let deviceUID = AudioDeviceIdentity.headphoneUID() else {
            enrolledSoFar.removeLast()
            enrolledRows.removeLast()
            say("Set the sound output to your AirPods (Control Center → Sound), then sign once more.", .bad)
            return
        }
        do {
            pendingEnrollment = try enroll(enrolledSoFar, deviceUID: deviceUID)
            confirmations = 0
            say("Now sign \(MatcherConfig.confirmCount) more times the same way, to check AirSign recognizes you.", .good)
        } catch {
            clearEnrollment()
            say("Could not build the signature: \(error.localizedDescription). Start again.", .bad)
        }
    }

    /// Every check must pass; one miss means the enrolled signatures weren't steady enough to rely on.
    private func checkEnrollment(_ signature: Signature) {
        guard let candidate = pendingEnrollment else { return }
        let verdict = verify(signature, deviceUID: AudioDeviceIdentity.headphoneUID(), against: candidate)
        if verdict.rejection == .deviceUnknown {
            say(Self.describe(verdict), .warn)
            return
        }
        guard verdict.accepted else {
            let check = confirmations + 1
            clearEnrollment()
            say("Check \(check) of \(MatcherConfig.confirmCount) didn't match, so the enrolled signatures weren't steady enough. "
                + "Enroll again, signing the same way each time.", .bad)
            return
        }
        confirmations += 1
        guard confirmations >= MatcherConfig.confirmCount else {
            say("Check \(confirmations) of \(MatcherConfig.confirmCount) passed. Sign again.", .good)
            return
        }
        finalizeEnrollment(candidate)
    }

    private func finalizeEnrollment(_ enrollment: Enrollment) {
        pendingEnrollment = nil
        confirmations = 0
        do {
            if isReenrolling, var updated = profile {
                updated.enrollment = enrollment
                updated.lockout.recordSuccess()
                try save(updated)
                logEnrollment(enrollment)
                isReenrolling = false
                clearEnrollment()
                screen = returnToLabAfterEnroll ? .lab : .home
                returnToLabAfterEnroll = false
                say("New signature saved. Your locked files open with it.", .good)
                return
            }
            let code = RecoveryCode.generate()
            let recoveryKey = try RecoveryCode.privateKey(for: code).publicKey.rawRepresentation
            // Demo mode shows scores, so it starts off and turning it on needs the owner.
            pendingProfile = Profile(enrollment: enrollment, recoveryPublicKey: recoveryKey, lockout: Lockout(), demoMode: false)
            recoveryCodeToShow = code
            say("Write down your recovery code. Your signature is saved when you confirm.", .good)
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
            try store.createProfile(pending)
            profile = pending
            pairedMacCount = 0
        } catch {
            clearEnrollment()
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
        clearEnrollment()
        livePath = []
        say("Start over: sign 3 times the same way.", .neutral)
    }

    private func clearEnrollment() {
        enrolledSoFar = []
        enrolledRows = []
        pendingEnrollment = nil
        confirmations = 0
    }

    // MARK: - Unlock

    private func verifyAndUnlock(_ signature: Signature) {
        guard let current = profile else {
            say("This Mac has no AirSign signature. Use the recovery code.", .warn)
            return
        }
        let verdict = verify(signature, deviceUID: AudioDeviceIdentity.headphoneUID(), against: current.enrollment,
                             threshold: thresholdOverride)
        if verdict.rejection == .deviceUnknown {
            lastVerdict = nil
            say(Self.describe(verdict), .warn)
            return
        }
        lastVerdict = verdict
        guard verdict.accepted else {
            adjustLockout(.failure)
            say(current.demoMode ? Self.describe(verdict) : "Not recognized.", .bad)
            return
        }
        adjustLockout(.success)
        do {
            let master = try store.masterKey()
            let paired = try store.pairedRecoveryKeys()
            let outcome = unlockPending { try Self.openWithThisMacsKeys($0, master: master, paired: paired) }
            if outcome.restored.isEmpty, outcome.errors.isEmpty, !outcome.wrongKey.isEmpty {
                say("Your signature matched, but this file was locked on a Mac that isn't paired with this one. "
                    + "Use that Mac's recovery code once and tick “Remember on this Mac”: after that, your AirPods "
                    + "and signature open its files here too.", .warn)
                return
            }
            let heading = current.demoMode ? Self.describe(verdict) : "Recognized."
            let foreign = outcome.wrongKey.map { "\($0.lastPathComponent): locked on a Mac that isn't paired with this one. Use its recovery code." }
            report(heading: heading, outcome: outcome, extra: foreign)
        } catch {
            say("Could not read AirSign's keys: \(error.localizedDescription)", .bad)
        }
    }

    /// `rememberOnThisMac` pairs this Mac with the one that locked the file, once the code has opened it.
    func submitRecoveryCode(_ code: String, rememberOnThisMac: Bool = false) {
        if let remaining = profile?.lockout.remaining(now: Date()) {
            say("Too many tries. Wait \(Int(remaining.rounded(.up))) s.", .bad)
            return
        }
        if saveBlocked {
            say("AirSign can't save its settings, so unlocking is paused.", .bad)
            return
        }
        guard (try? RecoveryCode.normalize(code)) != nil else {
            adjustLockout(.failure)
            say("That is not a valid recovery code (32 characters).", .bad)
            return
        }
        if screen == .confirmIdentity {
            let key = try? RecoveryCode.privateKey(for: code).publicKey.rawRepresentation
            guard let key, key == profile?.recoveryPublicKey else {
                adjustLockout(.failure)
                say("Wrong recovery code.", .bad)
                return
            }
            adjustLockout(.success)
            identityConfirmed()
            return
        }
        let outcome = unlockPending { try LockedFile.open($0, recoveryCode: code) }
        adjustLockout(Lockout.recoveryEffect(restored: outcome.restored.count, wrongKey: outcome.wrongKey.count))
        var extra = outcome.wrongKey.map { "\($0.lastPathComponent): wrong recovery code." }
        if rememberOnThisMac, profile != nil, !outcome.restored.isEmpty {
            extra.append(pairThisMac(withCode: code))
        }
        report(heading: "Recovery code", outcome: outcome, extra: extra)
    }

    /// Only a Mac with its own enrolled signature can be paired; a public Mac just uses the code once.
    private func pairThisMac(withCode code: String) -> String {
        do {
            let added = try store.addPairedRecoveryKey(RecoveryCode.privateKey(for: code))
            pairedMacCount = try store.pairedRecoveryKeys().count
            return added
                ? "Paired: files from that Mac now open here with your AirPods and signature."
                : "This Mac was already paired with that one."
        } catch {
            return "Could not pair this Mac: \(error.localizedDescription)"
        }
    }

    func forgetPairedMacs() {
        do {
            try store.forgetPairedMacs()
            pairedMacCount = 0
            say("Forgot all paired Macs. Their files open here only with their recovery codes.", .good)
        } catch {
            say("Could not forget paired Macs: \(error.localizedDescription)", .bad)
        }
    }

    /// This Mac's master key first, then the keys of Macs the owner paired with this one.
    private static func openWithThisMacsKeys(_ data: Data, master: SymmetricKey,
                                             paired: [Curve25519.KeyAgreement.PrivateKey]) throws -> (name: String, plaintext: Data) {
        do {
            return try LockedFile.open(data, masterKey: master)
        } catch LockedFileError.authenticationFailed {
            for key in paired {
                if let opened = try? LockedFile.open(data, recoveryPrivateKey: key) { return opened }
            }
            throw LockedFileError.authenticationFailed
        }
    }

    func cancelToHome() {
        stopCapture()
        identityNeedsCode = false
        isReenrolling = false
        returnToLabAfterEnroll = false
        clearEnrollment()
        pendingUnlock = []
        lastVerdict = nil
        livePath = []
        screen = profile == nil ? .enroll : .home
        say("", .neutral)
    }

    private struct UnlockOutcome {
        var restored: [URL] = []
        var wrongKey: [URL] = []
        var errors: [String] = []
    }

    private func unlockPending(open: (Data) throws -> (name: String, plaintext: Data)) -> UnlockOutcome {
        var outcome = UnlockOutcome()
        for url in pendingUnlock {
            do {
                outcome.restored.append(try FileLocker().unlock(url, open: open))
            } catch LockedFileError.authenticationFailed {
                outcome.wrongKey.append(url)
            } catch {
                outcome.errors.append("\(url.lastPathComponent): \(Self.describe(error))")
            }
        }
        pendingUnlock = outcome.wrongKey
        return outcome
    }

    private func report(heading: String, outcome: UnlockOutcome, extra: [String]) {
        let lines = [heading] + outcome.restored.map { "Unlocked \($0.lastPathComponent)" } + extra + outcome.errors
        let allDone = outcome.wrongKey.isEmpty && outcome.errors.isEmpty
        say(lines.joined(separator: "\n"), allDone ? .good : .bad)
        if !outcome.restored.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outcome.restored) }
        if allDone { screen = profile == nil ? .enroll : .home }
    }

    // MARK: - Proving identity (change signature, open the test lab)

    func beginChangeSignature() {
        beginIdentityCheck(.changeSignature, prompt: "Changing your signature needs your recovery code: press “Use recovery code…”.")
    }

    func beginLab() {
        guard testMode else { return }
        beginIdentityCheck(.openLab, prompt: "The owner opens the test lab: sign once, or use the recovery code.")
    }

    private func beginIdentityCheck(_ purpose: IdentityPurpose, prompt: String) {
        stopCapture()
        identityPurpose = purpose
        identityNeedsCode = purpose.needsRecoveryCode
        lastVerdict = nil
        livePath = []
        screen = .confirmIdentity
        say(prompt, .neutral)
    }

    private func confirmIdentity(_ signature: Signature) {
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
        } else if verdict.accepted {
            adjustLockout(.success)
            identityConfirmed()
        } else {
            adjustLockout(.failure)
            say(current.demoMode ? Self.describe(verdict) : "Not recognized.", .bad)
        }
    }

    private func identityConfirmed() {
        identityNeedsCode = false
        switch identityPurpose {
        case .changeSignature:
            startReenrollment(returningToLab: false)
        case .changeSignatureFromLab:
            startReenrollment(returningToLab: true)
        case .openLab:
            lastVerdict = nil
            livePath = []
            screen = .lab
            say("Test lab open. Pick the tester and scenario, then press Space.", .good)
        case .enableDemo:
            if var current = profile {
                current.demoMode = true
                persist(current)
            }
            lastVerdict = nil
            livePath = []
            screen = .home
            say("Demo mode on: scores, lights and reasons are shown.", .good)
        }
    }

    private func startReenrollment(returningToLab: Bool) {
        isReenrolling = true
        returnToLabAfterEnroll = returningToLab
        clearEnrollment()
        livePath = []
        lastVerdict = nil
        screen = .enroll
        say("Now sign your new signature 3 times.", .neutral)
    }

    // MARK: - Test lab (only with --test-mode)

    /// The owner re-enrolls from inside the lab so the templates' raw motion is logged too.
    func reenrollOwnerFromLab() {
        guard testMode, screen == .lab else { return }
        beginIdentityCheck(.changeSignatureFromLab, prompt: "Re-enrolling the owner needs the recovery code: press “Use recovery code…”.")
    }

    func labCount(for scenario: TestScenario) -> Int {
        labCounts[labKey(scenario)] ?? 0
    }

    func leaveLab() {
        cancelToHome()
    }

    private func labVerify(_ signature: Signature, rows: [MotionSample]) {
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

    private func logEnrollment(_ enrollment: Enrollment) {
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

    // MARK: - Settings

    /// Turning demo mode off is free; turning it on needs the owner, since it shows scores.
    func setDemoMode(_ on: Bool) {
        guard var current = profile, on != current.demoMode else { return }
        if on {
            beginIdentityCheck(.enableDemo, prompt: "Turning demo mode on shows scores: sign once, or use the recovery code.")
            return
        }
        current.demoMode = false
        persist(current)
        thresholdOverride = nil
    }

    // MARK: - Helpers

    private func adjustLockout(_ effect: Lockout.Effect) {
        guard var current = profile else { return }
        current.lockout.apply(effect, now: Date())
        persist(current)
    }

    private func save(_ updated: Profile) throws {
        try store.save(updated)
        profile = updated
    }

    /// Updates memory first so a failed write can't erase a failure count, then blocks attempts until saving works.
    private func persist(_ updated: Profile) {
        profile = updated
        do {
            try store.save(updated)
            saveBlocked = false
        } catch {
            saveBlocked = true
            NSLog("AirSign: could not save profile: %@", error.localizedDescription)
            say("Could not save AirSign settings, so unlocking is paused: \(error.localizedDescription)", .bad)
        }
    }

    private func say(_ text: String, _ newTone: Tone) {
        message = text
        tone = newTone
    }

    static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func describe(_ reason: AbortReason) -> String {
        switch reason {
        case .sensorSwitched: return "Discarded: use the same AirPod and keep the other one in the case."
        case .samplesStopped: return "Discarded: keep your finger over the AirPod's sensor."
        case .tooShort: return "Discarded: sign a little longer."
        }
    }

    private static func describe(_ verdict: Verdict) -> String {
        let numbers = "score \(format(verdict.score)) vs threshold \(format(verdict.threshold))"
        switch verdict.rejection {
        case .wrongBud: return "Not recognized: wrong AirPod side."
        case .wrongDevice: return "Not recognized: different AirPods."
        case .scoreTooHigh: return "Not recognized: signature doesn't match (\(numbers))."
        case .deviceUnknown: return "Set the sound output to your AirPods (Control Center → Sound), then sign again. This try was not counted."
        case nil: return "Recognized (\(numbers))."
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case FileLockerError.alreadyLocked: return "already locked"
        case FileLockerError.isDirectory: return "folders can't be locked yet"
        case FileLockerError.tooLarge: return "larger than 500 MB"
        case FileLockerError.unreadable: return "can't be read"
        case FileLockerError.notLocked: return "not an .airsign file"
        case FileLockerError.writeFailed(let reason): return "could not write: \(reason)"
        case LockedFileError.notAirSignFile: return "not a valid .airsign file"
        case LockedFileError.unsupportedVersion(let v): return "made by a newer AirSign (version \(v))"
        case LockedFileError.badRecoveryCode: return "not a valid recovery code"
        default: return error.localizedDescription
        }
    }
}
