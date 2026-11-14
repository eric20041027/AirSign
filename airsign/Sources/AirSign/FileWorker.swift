import AirSignCore
import CryptoKit
import Foundation

/// Serializes file work away from the main actor, including scratch-folder cleanup.
actor FileWorker {
    func lock(_ urls: [URL], masterKey: SymmetricKey,
              recoveryPublicKey: Curve25519.KeyAgreement.PublicKey) -> LockOutcome {
        LockRun.run(urls, locker: FileLocker(), masterKey: masterKey, recoveryPublicKey: recoveryPublicKey)
    }

    func unlock(_ urls: [URL], keys: UnlockKeys) -> UnlockOutcome {
        UnlockRun.run(urls, locker: FileLocker(), open: keys.open)
    }

    func unlock(_ urls: [URL], recoveryCode: String) -> UnlockOutcome {
        UnlockRun.run(urls, locker: FileLocker()) { try LockedFile.open($0, recoveryCode: recoveryCode) }
    }

    func sweepTemporaryFolders() {
        Scratch.sweepTemporaryFolders()
    }
}
