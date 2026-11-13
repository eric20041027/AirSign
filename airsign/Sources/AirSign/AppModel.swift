import AirSignCore
import AppKit
import CryptoKit
import Foundation
#if AIRSIGN_LAB
import AirSignLab
#endif

enum Tone {
    case neutral, good, warn, bad
}

/// Drives enrollment, file locking, signature and recovery unlock, and settings.
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case enroll, home, blocked, unlock, confirmIdentity, lab
    }

    // Views read the published state, and only AppModel assigns it.
    @Published var profile: Profile?
    @Published var blockReason: BlockReason?
    @Published var isResetting = false
    @Published var screen: Screen = .home
    @Published private(set) var motionStatus: MotionStatus = .waitingForAirPods
    @Published var isCapturing = false
    @Published var livePath: [SIMD3<Double>] = []
    @Published private(set) var message = ""
    @Published private(set) var tone: Tone = .neutral
    @Published var lastVerdict: Verdict?
    /// The last unlocking signature, kept only when it passed strongly enough to be added to the enrollment.
    @Published var sampleCandidate: Signature?
    @Published private(set) var enrolledSoFar: [Signature] = []
    /// Built from the enrolled signatures; kept only after `MatcherConfig.confirmCount` checks all pass.
    @Published private(set) var pendingEnrollment: Enrollment?
    @Published private(set) var confirmations = 0
    /// Rating of the signatures just enrolled; a weak one is refused, like a too-simple password.
    @Published private(set) var enrollStrength: SignatureStrength?

    @Published var isReenrolling = false
    @Published var recoveryCodeToShow: String?
    @Published var pendingUnlock: [URL] = []
    @Published var lockoutRemaining: TimeInterval?
    /// Set while the profile can't be written: attempts are refused so the lockout can't be dodged.
    @Published private(set) var saveBlocked = false
    @Published var pairedMacs: PairedMacs = .readable(count: 0)
    @Published var thresholdOverride: Double?

    #if AIRSIGN_LAB
    /// `open -a AirSign --args --test-mode` adds the test lab. Lab attempts open no files, so they
    /// never count toward the lockout; every other flow keeps it.
    let testMode = CommandLine.arguments.contains("--test-mode")
    /// No default: a pre-filled name got the wrong owner logged on the second Mac.
    @Published var testOwner = ""
    @Published var testTester = ""
    @Published var testSession = TestSession.tonight
    @Published var testScenario = TestScenario.owner
    @Published var labCounts: [String: Int] = [:]
    let sandboxPath = ProcessInfo.processInfo.environment["AIRSIGN_SANDBOX"]
    let attemptLog = AttemptLog(directory: AttemptLog.defaultDirectory)
    #else
    let testMode = false
    #endif

    let store: ProfileStore = {
        #if AIRSIGN_LAB
        if let path = ProcessInfo.processInfo.environment["AIRSIGN_SANDBOX"] {
            return ProfileStore(directory: URL(fileURLWithPath: path), secrets: KeychainSecretStore(service: "com.makeuc.airsign.sandbox"))
        }
        #endif
        return ProfileStore(directory: ProfileStore.defaultDirectory, secrets: KeychainSecretStore())
    }()
    let motion = HeadphoneMotionSource()
    var recorder = SignatureRecorder()
    var signingSamples: [MotionSample] = []
    var enrollmentSession = EnrollmentSession() {
        didSet {
            enrolledSoFar = enrollmentSession.signatures
            pendingEnrollment = enrollmentSession.pending
            confirmations = enrollmentSession.confirmations
            enrollStrength = enrollmentSession.strength
        }
    }
    #if AIRSIGN_LAB
    var enrolledRows: [[MotionSample]] = []
    var returnToLabAfterEnroll = false
    #endif
    /// A first enrollment waits here until the user confirms the recovery code, so quitting early saves nothing.
    var pendingProfile: Profile?
    var identityPurpose = IdentityPurpose.changeSignature
    private var timer: Timer?

    /// True while the identity screen accepts only the recovery code.
    @Published var identityNeedsCode = false

    var restingScreen: Screen {
        if blockReason != nil { return .blocked }
        if profile == nil { return .enroll }
        return .home
    }

    init() {
        retryLaunch()
        motion.onSample = { [weak self] sample in self?.handle(sample) }
        motion.onStatus = { [weak self] status in self?.motionStatus = status }
        motion.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func retryLaunch() {
        profile = nil
        blockReason = nil
        saveBlocked = false
        switch store.launchState() {
        case .noProfile:
            screen = .enroll
            say("", .neutral)
        case .ready(let loaded):
            profile = loaded
            screen = .home
            say("", .neutral)
        case .blocked(let reason):
            block(reason)
        }
        pairedMacs = store.pairedMacs()
    }

    func block(_ reason: BlockReason) {
        stopCapture()
        // Recovery unlock must work just as it does on a Mac with no profile.
        profile = nil
        saveBlocked = false
        lockoutRemaining = nil
        lastVerdict = nil
        sampleCandidate = nil
        blockReason = reason
        screen = .blocked
        say(Self.describe(reason), .bad)
    }

    // MARK: - Helpers

    func adjustLockout(_ effect: Lockout.Effect) -> Bool {
        guard var current = profile else { return true }
        current.lockout.apply(effect, now: Date(), boot: BootClock.current())
        return persist(current)
    }

    func save(_ updated: Profile) throws {
        try store.save(updated)
        profile = updated
    }

    /// Updates memory first so a failed write can't erase a failure count, then blocks attempts until saving works.
    func persist(_ updated: Profile) -> Bool {
        profile = updated
        do {
            try store.save(updated)
            saveBlocked = false
            return true
        } catch ProfileStoreError.keyMissing {
            block(.keyMissing)
        } catch {
            saveBlocked = true
            NSLog("AirSign: could not save profile: %@", error.localizedDescription)
            say("Could not save AirSign settings, so unlocking is paused: \(error.localizedDescription)", .bad)
        }
        return false
    }

    func say(_ text: String, _ newTone: Tone) {
        message = text
        tone = newTone
    }

}
