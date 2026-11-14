import CryptoKit
import Foundation

public struct UnlockOutcome: Sendable {
    public struct Failure: Sendable {
        public let url: URL
        public let error: Error
    }

    public var restored: [URL] = []
    /// Files locked under another key stay waiting.
    public var wrongKey: [URL] = []
    public var failures: [Failure] = []
    public var allDone: Bool { wrongKey.isEmpty && failures.isEmpty }
}

public enum UnlockRun {
    /// Unlocks each item in order. Authentication failures go in `wrongKey`, and other errors go in `failures`.
    public static func run(_ urls: [URL], locker: FileLocker,
                           open: (Data) throws -> (name: String, plaintext: Data)) -> UnlockOutcome {
        var outcome = UnlockOutcome()
        for url in urls {
            do {
                outcome.restored.append(try locker.unlock(url, open: open))
            } catch LockedFileError.authenticationFailed {
                outcome.wrongKey.append(url)
            } catch {
                outcome.failures.append(.init(url: url, error: error))
            }
        }
        return outcome
    }
}

public struct LockOutcome: Sendable {
    public struct Locked: Sendable {
        public let source: URL
        public let locked: URL
    }

    public struct Failure: Sendable {
        public let url: URL
        public let error: Error
    }

    /// One entry per item, in the order given.
    public enum Item: Sendable {
        case locked(Locked), failed(Failure)
    }

    public var items: [Item]
    public var anyFailed: Bool {
        items.contains {
            if case .failed = $0 { return true }
            return false
        }
    }
}

public enum LockRun {
    public static func run(_ urls: [URL], locker: FileLocker, masterKey: SymmetricKey,
                           recoveryPublicKey: Curve25519.KeyAgreement.PublicKey) -> LockOutcome {
        let items = urls.map { url -> LockOutcome.Item in
            do {
                let locked = try locker.lock(url, masterKey: masterKey, recoveryPublicKey: recoveryPublicKey)
                return .locked(.init(source: url, locked: locked))
            } catch {
                return .failed(.init(url: url, error: error))
            }
        }
        return LockOutcome(items: items)
    }
}
