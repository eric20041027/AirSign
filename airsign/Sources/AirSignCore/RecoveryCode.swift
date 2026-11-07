import CryptoKit
import Foundation

/// A one-time recovery code: 160 random bits written as 32 Crockford base32 characters
/// (`XXXX-XXXX-…`). It is shown once and never stored; it derives the X25519 key that
/// can unwrap every `.airsign` file's data key.
public enum RecoveryCode {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let byteCount = 20
    static let length = 32
    static let groupSize = 4
    static let salt = Data("airsign-recovery-v1".utf8)

    public static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        let chars = encode(bytes)
        return stride(from: 0, to: chars.count, by: groupSize)
            .map { String(chars[$0..<min($0 + groupSize, chars.count)]) }
            .joined(separator: "-")
    }

    /// Accepts lowercase, spaces, missing dashes, and the look-alikes O→0, I/L→1.
    public static func normalize(_ input: String) throws -> String {
        let mapped: [Character] = input.uppercased().compactMap { c in
            switch c {
            case " ", "-", "\t", "\n": return nil
            case "O": return "0"
            case "I", "L": return "1"
            default: return c
            }
        }
        guard mapped.count == length, mapped.allSatisfy({ alphabet.contains($0) }) else {
            throw LockedFileError.badRecoveryCode
        }
        return String(mapped)
    }

    public static func privateKey(for code: String) throws -> Curve25519.KeyAgreement.PrivateKey {
        let bytes = decode(try normalize(code))
        let derived = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes), salt: salt, outputByteCount: 32)
        return try derived.withUnsafeBytes { try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data($0)) }
    }

    static func encode(_ bytes: [UInt8]) -> [Character] {
        var out: [Character] = []
        var buffer = 0, bits = 0
        for byte in bytes {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(alphabet[(buffer >> bits) & 31])
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { out.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return out
    }

    /// Expects an already-normalized code.
    static func decode(_ normalized: String) -> [UInt8] {
        var out: [UInt8] = []
        var buffer = 0, bits = 0
        for c in normalized {
            guard let value = alphabet.firstIndex(of: c) else { continue }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((buffer >> bits) & 0xFF))
            }
            buffer &= (1 << bits) - 1
        }
        return out
    }
}
