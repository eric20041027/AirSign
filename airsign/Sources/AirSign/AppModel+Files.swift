import AirSignCore
import AppKit
import CryptoKit
import Foundation

extension AppModel {
    // MARK: - Files

    /// Finder and `open -a AirSign` land here: `.airsign` files unlock, everything else locks.
    func handleOpen(_ urls: [URL]) {
        guard allows(.openRequest), let request = openQueue.receive(urls) else { return }
        routeOpen(request)
    }

    private func routeOpen(_ urls: [URL]) {
        let routed = OpenRouting.route(urls)
        if !routed.toLock.isEmpty, lock(routed.toLock, thenUnlock: routed.toUnlock) { return }
        finishOpen(routed.toUnlock)
    }

    private func finishOpen(_ toUnlock: [URL]) {
        if !toUnlock.isEmpty { beginUnlock(toUnlock) }
        // Locking needs no signature, so Finder keeps the focus; the app comes forward only to sign or to show a problem.
        if !toUnlock.isEmpty || tone == .bad || tone == .warn { NSApp.activate() }
    }

    private func lock(_ urls: [URL], thenUnlock: [URL]) -> Bool {
        guard blockReason == nil else {
            screen = .blocked
            say("AirSign can't lock files until its profile can be read again.", .bad)
            return false
        }
        guard let profile else {
            screen = .enroll
            say("Enroll your signature first, then lock files.", .warn)
            return false
        }
        do {
            let master = try store.masterKey()
            let recoveryKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: profile.recoveryPublicKey)
            beginFileWork("Locking", count: urls.count)
            Task {
                let outcome = await fileWorker.lock(urls, masterKey: master, recoveryPublicKey: recoveryKey)
                reportLock(outcome)
                finishOpen(thenUnlock)
                endFileWork()
            }
            return true
        } catch ProfileStoreError.keyMissing {
            block(.keyMissing)
        } catch {
            say("Could not read AirSign's keys: \(error.localizedDescription)", .bad)
        }
        return false
    }

    private func reportLock(_ outcome: LockOutcome) {
        let lines = outcome.items.map { item -> String in
            switch item {
            case .locked(let locked):
                return "Locked \(locked.source.lastPathComponent) → \(locked.locked.lastPathComponent) (original moved to the Trash)"
            case .failed(let failure):
                return "\(failure.url.lastPathComponent): \(Self.describe(failure.error))"
            }
        }
        say(lines.joined(separator: "\n"), outcome.anyFailed ? .bad : .good)
    }

    private func beginUnlock(_ urls: [URL]) {
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

    /// Reserves the operation before a task can yield to another action or open request.
    func beginFileWork(_ verb: String, count: Int) {
        stopCapture()
        openQueue.operationBegan()
        fileWork = "\(verb) \(count) \(count == 1 ? "item" : "items")…"
        say("", .neutral)
    }

    func endFileWork() {
        fileWork = nil
        openQueue.operationEnded()
        while let request = openQueue.next() { routeOpen(request) }
    }
}
