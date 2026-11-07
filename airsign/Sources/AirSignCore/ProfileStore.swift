import CryptoKit
import Foundation

public struct Profile: Codable, Equatable {
    public var enrollment: Enrollment
    /// Raw X25519 public key derived from the recovery code (the code itself is never stored).
    public var recoveryPublicKey: Data
    public var lockout: Lockout
    public var demoMode: Bool

    public init(enrollment: Enrollment, recoveryPublicKey: Data, lockout: Lockout, demoMode: Bool) {
        self.enrollment = enrollment
        self.recoveryPublicKey = recoveryPublicKey
        self.lockout = lockout
        self.demoMode = demoMode
    }
}

/// Keeps the enrolled signatures and settings on this Mac only, encrypted at rest with a
/// key held in the secret store. Also owns the master key that wraps every file's data key.
public struct ProfileStore {
    static let fileName = "profile.bin"
    static let profileKeyName = "profile-key"
    static let masterKeyName = "master-key"
    static let pairedKeysName = "paired-recovery-keys"

    private let directory: URL
    private let secrets: SecretStore

    public init(directory: URL, secrets: SecretStore) {
        self.directory = directory
        self.secrets = secrets
    }

    /// ~/Library/Application Support/AirSign
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AirSign", isDirectory: true)
    }

    public func load() throws -> Profile? {
        let url = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let plaintext = try AES.GCM.open(box, using: key(Self.profileKeyName))
        return try JSONDecoder().decode(Profile.self, from: plaintext)
    }

    public func save(_ profile: Profile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let plaintext = try JSONEncoder().encode(profile)
        guard let sealed = try AES.GCM.seal(plaintext, using: key(Self.profileKeyName)).combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = directory.appendingPathComponent(Self.fileName)
        try sealed.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// First enrollment on this Mac, or after the profile was lost or deleted: a fresh master key,
    /// so a newly enrolled signature can never open files locked earlier. Those open with their recovery code.
    /// Pairings belong to the previous owner too, so they are forgotten here.
    public func createProfile(_ profile: Profile) throws {
        let key = SymmetricKey(size: .bits256)
        try secrets.save(key.withUnsafeBytes { Data($0) }, as: Self.masterKeyName)
        try forgetPairedMacs()
        try save(profile)
    }

    // MARK: - Paired Macs

    /// Recovery keys of the owner's other Macs. Files locked there open here after this Mac's signature check.
    public func pairedRecoveryKeys() throws -> [Curve25519.KeyAgreement.PrivateKey] {
        guard let data = try secrets.load(Self.pairedKeysName) else { return [] }
        return try JSONDecoder().decode([Data].self, from: data)
            .map { try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: $0) }
    }

    /// Returns false when that Mac was already paired.
    @discardableResult
    public func addPairedRecoveryKey(_ key: Curve25519.KeyAgreement.PrivateKey) throws -> Bool {
        var raws = try pairedRecoveryKeys().map(\.rawRepresentation)
        guard !raws.contains(key.rawRepresentation) else { return false }
        raws.append(key.rawRepresentation)
        try secrets.save(JSONEncoder().encode(raws), as: Self.pairedKeysName)
        return true
    }

    public func forgetPairedMacs() throws {
        try secrets.delete(Self.pairedKeysName)
    }

    public func masterKey() throws -> SymmetricKey {
        try key(Self.masterKeyName)
    }

    /// Loads a 256-bit key, creating it on first use. A store error is thrown, never treated as "missing".
    private func key(_ name: String) throws -> SymmetricKey {
        if let data = try secrets.load(name) { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        try secrets.save(key.withUnsafeBytes { Data($0) }, as: name)
        return key
    }
}
