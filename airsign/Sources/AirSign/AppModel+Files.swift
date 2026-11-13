import AirSignCore
import AppKit
import CryptoKit
import Foundation

extension AppModel {
    // MARK: - Files

    /// Finder and `open -a AirSign` land here: `.airsign` files unlock, everything else locks.
    func handleOpen(_ urls: [URL]) {
        let routed = OpenRouting.route(urls)
        if !routed.toLock.isEmpty { lock(routed.toLock) }
        if !routed.toUnlock.isEmpty { beginUnlock(routed.toUnlock) }
        // Locking needs no signature, so Finder keeps the focus; the app comes forward only to sign or to show a problem.
        if !routed.toUnlock.isEmpty || tone == .bad || tone == .warn { NSApp.activate() }
    }

    func lock(_ urls: [URL]) {
        guard blockReason == nil else {
            screen = .blocked
            say("AirSign can't lock files until its profile can be read again.", .bad)
            return
        }
        guard let profile else {
            screen = .enroll
            say("Enroll your signature first, then lock files.", .warn)
            return
        }
        do {
            let master = try store.masterKey()
            let recoveryKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: profile.recoveryPublicKey)
            let outcome = LockRun.run(urls, locker: FileLocker(), masterKey: master, recoveryPublicKey: recoveryKey)
            let lines = outcome.items.map { item -> String in
                switch item {
                case .locked(let locked):
                    return "Locked \(locked.source.lastPathComponent) → \(locked.locked.lastPathComponent) (original moved to the Trash)"
                case .failed(let failure):
                    return "\(failure.url.lastPathComponent): \(Self.describe(failure.error))"
                }
            }
            say(lines.joined(separator: "\n"), outcome.anyFailed ? .bad : .good)
        } catch ProfileStoreError.keyMissing {
            block(.keyMissing)
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
        if blockReason != nil {
            say("AirSign's profile can't be read. Use the recovery code.", .neutral)
        } else {
            say(profile == nil ? "This Mac has no AirSign signature. Use the recovery code." : "Press Space, sign, then hold still.", .neutral)
        }
    }
}
