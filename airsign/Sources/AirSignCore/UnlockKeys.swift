import CryptoKit
import Foundation

public struct UnlockKeys {
    private let master: SymmetricKey
    private let paired: [Curve25519.KeyAgreement.PrivateKey]

    public init(master: SymmetricKey, paired: [Curve25519.KeyAgreement.PrivateKey]) {
        self.master = master
        self.paired = paired
    }

    /// This Mac's master key first, then the key of each paired Mac, in order.
    /// Throws `LockedFileError.authenticationFailed` when none opens the file. Other master-key errors pass through.
    public func open(_ data: Data) throws -> (name: String, plaintext: Data) {
        do {
            return try LockedFile.open(data, masterKey: master)
        } catch LockedFileError.authenticationFailed {
            for key in paired {
                if let opened = try? LockedFile.open(data, recoveryPrivateKey: key) { return opened }
            }
            throw LockedFileError.authenticationFailed
        }
    }
}
