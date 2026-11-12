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

public enum ProfileStoreError: Error, Equatable {
    case keyMissing(String)
    case profileExists
}

public enum BlockReason: Equatable {
    case keyMissing, profileUnreadable, storeError
}

public enum LaunchState: Equatable {
    case noProfile, ready(Profile), blocked(BlockReason)

    public var allowsEnrollment: Bool {
        if case .noProfile = self { return true }
        return false
    }

    public var allowsLocking: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Keeps the enrolled signatures and settings on this Mac only, encrypted at rest with a
/// key held in the secret store. Also owns the master key that wraps every file's data key.
public struct ProfileStore {
    static let fileName = "profile.bin"
    static let profileKeyName = "profile-key"
    static let masterKeyName = "master-key"
    static let pairedKeysName = "paired-recovery-keys"
    static let lockoutName = "lockout"

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

    public func load(now: Date = Date(), boot: BootClock? = BootClock.current()) throws -> Profile? {
        let url = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let profileKey = try key(Self.profileKeyName)
        let lockoutData = try secrets.load(Self.lockoutName)
        let profile = try readProfile(using: profileKey, lockoutData: lockoutData, now: now, boot: boot)
        if lockoutData == nil { try save(profile) }
        return profile
    }

    public func launchState(now: Date = Date(), boot: BootClock? = BootClock.current()) -> LaunchState {
        let url = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return .noProfile }
        let profileKey: Data?, masterKey: Data?, lockoutData: Data?
        do {
            profileKey = try secrets.load(Self.profileKeyName)
            masterKey = try secrets.load(Self.masterKeyName)
            lockoutData = try secrets.load(Self.lockoutName)
        } catch {
            return .blocked(.storeError)
        }
        guard let profileKey, masterKey != nil else { return .blocked(.keyMissing) }
        let profile: Profile
        do {
            profile = try readProfile(using: SymmetricKey(data: profileKey), lockoutData: lockoutData,
                                      now: now, boot: boot)
        } catch {
            return .blocked(.profileUnreadable)
        }
        if lockoutData == nil {
            do { try save(profile) }
            catch { return .blocked(.storeError) }
        }
        return .ready(profile)
    }

    private func readProfile(using profileKey: SymmetricKey, lockoutData: Data?,
                             now: Date, boot: BootClock?) throws -> Profile {
        let url = directory.appendingPathComponent(Self.fileName)
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let plaintext = try AES.GCM.open(box, using: profileKey)
        var profile = try JSONDecoder().decode(Profile.self, from: plaintext)
        // The Keychain keeps its own copy of the count, so restoring an old profile.bin can't reset it.
        if let lockoutData {
            let kept = try JSONDecoder().decode(Lockout.self, from: lockoutData)
            profile.lockout = Lockout.mostRestrictive(profile.lockout, kept)
        } else {
            profile.lockout = Lockout.mostRestrictive(profile.lockout, .tampered(now: now, boot: boot))
        }
        return profile
    }

    public func save(_ profile: Profile) throws {
        let profileKey = try key(Self.profileKeyName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try secrets.save(JSONEncoder().encode(profile.lockout), as: Self.lockoutName)
        let plaintext = try JSONEncoder().encode(profile)
        guard let sealed = try AES.GCM.seal(plaintext, using: profileKey).combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = directory.appendingPathComponent(Self.fileName)
        try sealed.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// First enrollment on this Mac, or an explicit reset: a fresh master key,
    /// so a newly enrolled signature can never open files locked earlier. Those open with their recovery code.
    /// Pairings belong to the previous owner too, so they are forgotten here.
    public func createProfile(_ profile: Profile, replacingExisting: Bool = false) throws {
        let url = directory.appendingPathComponent(Self.fileName)
        if FileManager.default.fileExists(atPath: url.path), !replacingExisting {
            throw ProfileStoreError.profileExists
        }
        // Delete before saving so unreadable old items cannot prevent a reset.
        for name in [Self.masterKeyName, Self.profileKeyName] {
            try secrets.delete(name)
            let key = SymmetricKey(size: .bits256)
            try secrets.save(key.withUnsafeBytes { Data($0) }, as: name)
        }
        try forgetPairedMacs()
        try secrets.delete(Self.lockoutName)
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

    /// Reading never creates a key; only enrollment or reset may replace one.
    private func key(_ name: String) throws -> SymmetricKey {
        guard let data = try secrets.load(name) else { throw ProfileStoreError.keyMissing(name) }
        return SymmetricKey(data: data)
    }
}
