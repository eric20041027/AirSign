import AirSignCore
import AppKit
import CryptoKit
import Foundation

enum Tone {
    case neutral, good, warn, bad
}

/// Drives every flow: enroll, lock, unlock by signature or recovery code, and changing the signature.
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case enroll, home, unlock, confirmIdentity
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
    @Published private(set) var isReenrolling = false
    @Published private(set) var recoveryCodeToShow: String?
    @Published private(set) var pendingUnlock: [URL] = []
    @Published private(set) var lockoutRemaining: TimeInterval?
    /// Set while the profile can't be written: attempts are refused so the lockout can't be dodged.
    @Published private(set) var saveBlocked = false
    @Published var thresholdOverride: Double?

    private let store = ProfileStore(directory: ProfileStore.defaultDirectory, secrets: KeychainSecretStore())
    private let motion = HeadphoneMotionSource()
    private var recorder = SignatureRecorder()
    private var signingSamples: [MotionSample] = []
    /// A first enrollment waits here until the user confirms the recovery code, so quitting early saves nothing.
    private var pendingProfile: Profile?
    private var timer: Timer?

    var demoMode: Bool { profile?.demoMode ?? true }

    init() {
        do {
            profile = try store.load()
        } catch {
            NSLog("AirSign: could not read profile: %@", error.localizedDescription)
            say("Your AirSign profile could not be read. Enroll again; locked files still open with the recovery code.", .bad)
        }
        screen = profile == nil ? .enroll : .home
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
        if screen != .enroll, let remaining = profile?.lockout.remaining(now: Date()) {
            say("Too many tries. Wait \(Int(remaining.rounded(.up))) s.", .bad)
            return
        }
        if screen != .enroll, saveBlocked {
            say("AirSign can't save its settings, so unlocking is paused. Check the AirSign folder in Application Support.", .bad)
            return
        }
        if screen == .enroll, AudioDeviceIdentity.headphoneUID() == nil {
            say("Set the sound output to your AirPods (Control Center → Sound), then enroll.", .bad)
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
            complete(signature)
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

    private func complete(_ signature: Signature) {
        switch screen {
        case .enroll: addEnrollment(signature)
        case .unlock: verifyAndUnlock(signature)
        case .confirmIdentity: confirmIdentity(signature)
        case .home: break
        }
    }

    // MARK: - Enrollment

    private func addEnrollment(_ signature: Signature) {
        if let first = enrolledSoFar.first, first.side != signature.side {
            say("Use the same AirPod as your first signature (\(first.side.rawValue)).", .warn)
            return
        }
        enrolledSoFar.append(signature)
        guard enrolledSoFar.count >= MatcherConfig.enrollCount else {
            say("Got \(enrolledSoFar.count) of \(MatcherConfig.enrollCount). Sign again the same way.", .good)
            return
        }
        finishEnrollment()
    }

    private func finishEnrollment() {
        guard let deviceUID = AudioDeviceIdentity.headphoneUID() else {
            enrolledSoFar.removeLast()
            say("Set the sound output to your AirPods (Control Center → Sound), then sign once more.", .bad)
            return
        }
        do {
            let enrollment = try enroll(enrolledSoFar, deviceUID: deviceUID)
            if isReenrolling, var updated = profile {
                updated.enrollment = enrollment
                updated.lockout.recordSuccess()
                try save(updated)
                isReenrolling = false
                enrolledSoFar = []
                screen = .home
                say("New signature saved. Your locked files open with it.", .good)
                return
            }
            let code = RecoveryCode.generate()
            let recoveryKey = try RecoveryCode.privateKey(for: code).publicKey.rawRepresentation
            pendingProfile = Profile(enrollment: enrollment, recoveryPublicKey: recoveryKey, lockout: Lockout(), demoMode: true)
            recoveryCodeToShow = code
            say("Write down your recovery code. Your signature is saved when you confirm.", .good)
        } catch {
            enrolledSoFar = []
            say("Could not save the signature: \(error.localizedDescription). Start again.", .bad)
        }
    }

    func confirmRecoveryCodeWritten() {
        guard let pending = pendingProfile else { return }
        do {
            try store.createProfile(pending)
            profile = pending
            pendingProfile = nil
        } catch {
            recoveryCodeToShow = nil
            pendingProfile = nil
            enrolledSoFar = []
            say("Could not save the signature: \(error.localizedDescription). Enroll again.", .bad)
            return
        }
        recoveryCodeToShow = nil
        enrolledSoFar = []
        screen = pendingUnlock.isEmpty ? .home : .unlock
        say(pendingUnlock.isEmpty ? "Right-click any file in Finder → Lock with AirSign." : "Now sign to unlock.", .neutral)
    }

    func restartEnrollment() {
        stopCapture()
        enrolledSoFar = []
        livePath = []
        say("Start over: sign 3 times the same way.", .neutral)
    }

    // MARK: - Unlock

    private func verifyAndUnlock(_ signature: Signature) {
        guard var current = profile else {
            say("This Mac has no AirSign signature. Use the recovery code.", .warn)
            return
        }
        let verdict = verify(signature, deviceUID: AudioDeviceIdentity.headphoneUID(), against: current.enrollment,
                             threshold: thresholdOverride)
        lastVerdict = verdict
        if verdict.rejection == .deviceUnknown {
            say(Self.describe(verdict), .warn)
            return
        }
        guard verdict.accepted else {
            current.lockout.recordFailure(now: Date())
            persist(current)
            say(current.demoMode ? Self.describe(verdict) : "Not recognized.", .bad)
            return
        }
        current.lockout.recordSuccess()
        persist(current)
        let heading = current.demoMode ? Self.describe(verdict) : "Recognized."
        do {
            let master = try store.masterKey()
            let outcome = unlockPending { try LockedFile.open($0, masterKey: master) }
            let foreign = outcome.wrongKey.map { "\($0.lastPathComponent): locked on another Mac. Use that Mac's recovery code." }
            report(heading: heading, outcome: outcome, extra: foreign)
        } catch {
            say("Could not read AirSign's keys: \(error.localizedDescription)", .bad)
        }
    }

    func submitRecoveryCode(_ code: String) {
        if let remaining = profile?.lockout.remaining(now: Date()) {
            say("Too many tries. Wait \(Int(remaining.rounded(.up))) s.", .bad)
            return
        }
        if saveBlocked {
            say("AirSign can't save its settings, so unlocking is paused.", .bad)
            return
        }
        guard (try? RecoveryCode.normalize(code)) != nil else {
            registerFailure()
            say("That is not a valid recovery code (32 characters).", .bad)
            return
        }
        if screen == .confirmIdentity {
            let key = try? RecoveryCode.privateKey(for: code).publicKey.rawRepresentation
            guard let key, key == profile?.recoveryPublicKey else {
                registerFailure()
                say("Wrong recovery code.", .bad)
                return
            }
            startReenrollment()
            return
        }
        let outcome = unlockPending { try LockedFile.open($0, recoveryCode: code) }
        if var current = profile {
            current.lockout.apply(Lockout.recoveryEffect(restored: outcome.restored.count, wrongKey: outcome.wrongKey.count),
                                  now: Date())
            persist(current)
        }
        let wrong = outcome.wrongKey.map { "\($0.lastPathComponent): wrong recovery code." }
        report(heading: "Recovery code", outcome: outcome, extra: wrong)
    }

    func cancelToHome() {
        stopCapture()
        isReenrolling = false
        enrolledSoFar = []
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

    // MARK: - Changing the signature

    func beginChangeSignature() {
        stopCapture()
        lastVerdict = nil
        livePath = []
        screen = .confirmIdentity
        say("First prove it's you: sign with your current signature, or use the recovery code.", .neutral)
    }

    private func confirmIdentity(_ signature: Signature) {
        guard var current = profile else { return }
        // Never the demo slider here: changing the signature always uses the enrolled threshold.
        let verdict = verify(signature, deviceUID: AudioDeviceIdentity.headphoneUID(), against: current.enrollment)
        lastVerdict = verdict
        if verdict.rejection == .deviceUnknown {
            say(Self.describe(verdict), .warn)
        } else if verdict.accepted {
            current.lockout.recordSuccess()
            persist(current)
            startReenrollment()
        } else {
            current.lockout.recordFailure(now: Date())
            persist(current)
            say(current.demoMode ? Self.describe(verdict) : "Not recognized.", .bad)
        }
    }

    private func startReenrollment() {
        isReenrolling = true
        enrolledSoFar = []
        livePath = []
        lastVerdict = nil
        screen = .enroll
        say("Now sign your new signature 3 times.", .neutral)
    }

    // MARK: - Settings

    func setDemoMode(_ on: Bool) {
        guard var current = profile else { return }
        current.demoMode = on
        persist(current)
        if !on { thresholdOverride = nil }
    }

    // MARK: - Helpers

    private func registerFailure() {
        guard var current = profile else { return }
        current.lockout.recordFailure(now: Date())
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
