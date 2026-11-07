import CryptoKit
import Foundation

public enum LockedFileError: Error, Equatable {
    case notAirSignFile
    case unsupportedVersion(Int)
    case authenticationFailed
    case badRecoveryCode
}

public struct LockedFileHeader: Codable {
    public var version: Int
    public var originalName: String
    public var createdAt: Date
    /// The file's data key sealed with the master key (AES-GCM, combined form).
    public var masterWrapped: Data
    /// HPKE encapsulated key and the data key sealed to the recovery public key.
    public var recoveryEncapsulated: Data
    public var recoveryWrapped: Data
}

/// `.airsign` layout: magic(8) | header length UInt32 big-endian | header JSON | AES-GCM combined content.
/// The content is authenticated together with the header, so renaming or editing the header breaks it.
public enum LockedFile {
    public static let magic = Data("AIRSIGN1".utf8)
    static let version = 1
    static let hpkeInfo = Data("airsign-file-v1".utf8)
    static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    private static let prefixLength = 12

    public static func seal(_ plaintext: Data, originalName: String, masterKey: SymmetricKey,
                            recoveryPublicKey: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let dataKey = SymmetricKey(size: .bits256)
        let keyBytes = dataKey.withUnsafeBytes { Data($0) }
        var sender = try HPKE.Sender(recipientKey: recoveryPublicKey, ciphersuite: suite, info: hpkeInfo)
        let header = LockedFileHeader(
            version: version,
            originalName: originalName,
            createdAt: Date(),
            masterWrapped: try combined(AES.GCM.seal(keyBytes, using: masterKey)),
            recoveryEncapsulated: sender.encapsulatedKey,
            recoveryWrapped: try sender.seal(keyBytes)
        )
        let headerData = try encoder.encode(header)
        let content = try combined(AES.GCM.seal(plaintext, using: dataKey, authenticating: headerData))

        var out = magic
        withUnsafeBytes(of: UInt32(headerData.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(headerData)
        out.append(content)
        return out
    }

    public static func open(_ data: Data, masterKey: SymmetricKey) throws -> (name: String, plaintext: Data) {
        let parsed = try parse(data)
        let keyBytes = try authenticated {
            try AES.GCM.open(AES.GCM.SealedBox(combined: parsed.header.masterWrapped), using: masterKey)
        }
        return try decryptContent(parsed, keyBytes)
    }

    public static func open(_ data: Data, recoveryCode: String) throws -> (name: String, plaintext: Data) {
        try open(data, recoveryPrivateKey: RecoveryCode.privateKey(for: recoveryCode))
    }

    /// Opens with the key a recovery code derives, as kept by a Mac paired with the locking Mac.
    public static func open(_ data: Data, recoveryPrivateKey privateKey: Curve25519.KeyAgreement.PrivateKey) throws
        -> (name: String, plaintext: Data) {
        let parsed = try parse(data)
        let keyBytes = try authenticated {
            var recipient = try HPKE.Recipient(privateKey: privateKey, ciphersuite: suite, info: hpkeInfo,
                                               encapsulatedKey: parsed.header.recoveryEncapsulated)
            return try recipient.open(parsed.header.recoveryWrapped)
        }
        return try decryptContent(parsed, keyBytes)
    }

    public static func header(of data: Data) throws -> LockedFileHeader {
        try parse(data).header
    }

    // MARK: - Private

    private struct Parsed {
        let header: LockedFileHeader
        let headerData: Data
        let content: Data
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static func parse(_ input: Data) throws -> Parsed {
        let data = Data(input)
        guard data.count > prefixLength, data.prefix(magic.count) == magic else { throw LockedFileError.notAirSignFile }
        let length = Int(data.subdata(in: magic.count..<prefixLength).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        guard data.count >= prefixLength + length else { throw LockedFileError.notAirSignFile }
        let headerData = data.subdata(in: prefixLength..<(prefixLength + length))
        guard let header = try? JSONDecoder().decode(LockedFileHeader.self, from: headerData) else {
            throw LockedFileError.notAirSignFile
        }
        guard header.version == version else { throw LockedFileError.unsupportedVersion(header.version) }
        return Parsed(header: header, headerData: headerData, content: data.subdata(in: (prefixLength + length)..<data.count))
    }

    private static func decryptContent(_ parsed: Parsed, _ keyBytes: Data) throws -> (name: String, plaintext: Data) {
        let plaintext = try authenticated {
            try AES.GCM.open(AES.GCM.SealedBox(combined: parsed.content), using: SymmetricKey(data: keyBytes),
                             authenticating: parsed.headerData)
        }
        return (parsed.header.originalName, plaintext)
    }

    /// Any CryptoKit failure means wrong key or tampered data; callers only need to know it did not open.
    private static func authenticated(_ body: () throws -> Data) throws -> Data {
        do {
            return try body()
        } catch {
            throw LockedFileError.authenticationFailed
        }
    }

    private static func combined(_ box: AES.GCM.SealedBox) throws -> Data {
        guard let data = box.combined else { throw LockedFileError.authenticationFailed }
        return data
    }
}
