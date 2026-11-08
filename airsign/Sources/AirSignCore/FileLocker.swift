import CryptoKit
import Foundation

public enum FileLockerError: Error, Equatable {
    case alreadyLocked
    case isDirectory
    case tooLarge
    case unreadable
    case notLocked
    case writeFailed(String)
}

/// Turns files into `.airsign` files and back. The original only goes to the Trash after
/// the locked copy has been written and decrypted again to the same bytes.
public struct FileLocker {
    public static let maxBytes = 500 * 1024 * 1024
    public static let lockedExtension = "airsign"

    private let trash: (URL) throws -> Void

    public init(trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.trash = trash
    }

    public func lock(_ url: URL, masterKey: SymmetricKey, recoveryPublicKey: Curve25519.KeyAgreement.PublicKey) throws -> URL {
        let isFolder = try Self.isFolder(url)
        let plaintext = isFolder ? try FolderArchive.zip(url, maxBytes: Self.maxBytes) : try readLockable(url)
        let sealed = try LockedFile.seal(plaintext, originalName: url.lastPathComponent, masterKey: masterKey,
                                         recoveryPublicKey: recoveryPublicKey, kind: isFolder ? LockedFileHeader.folderKind : nil)
        let target = uniqueLockedURL(for: url)
        do {
            try sealed.write(to: target, options: .withoutOverwriting)
            let reopened = try LockedFile.open(Data(contentsOf: target), masterKey: masterKey)
            guard SHA256.hash(data: reopened.plaintext) == SHA256.hash(data: plaintext) else {
                throw FileLockerError.writeFailed("the locked copy did not decrypt to the same bytes")
            }
            try trash(url)
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw (error as? FileLockerError) ?? FileLockerError.writeFailed(error.localizedDescription)
        }
        return target
    }

    public func unlock(_ url: URL, open: (Data) throws -> (name: String, plaintext: Data)) throws -> URL {
        guard url.pathExtension.lowercased() == Self.lockedExtension else { throw FileLockerError.notLocked }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FileLockerError.unreadable
        }
        let opened = try open(data)
        // `open` succeeded, so the header (which says file or folder) is authentic.
        let isFolder = (try? LockedFile.header(of: data))?.kind == LockedFileHeader.folderKind
        let target = uniqueRestoreURL(in: url.deletingLastPathComponent(), name: Self.safeName(opened.name), isFolder: isFolder)
        do {
            if isFolder {
                try FolderArchive.unzip(opened.plaintext, to: target)
            } else {
                try opened.plaintext.write(to: target, options: .withoutOverwriting)
            }
        } catch {
            throw (error as? FileLockerError) ?? FileLockerError.writeFailed(error.localizedDescription)
        }
        do {
            try trash(url)
        } catch {
            throw FileLockerError.writeFailed("restored \(target.lastPathComponent) but could not move the locked file to the Trash")
        }
        return target
    }

    // MARK: - Private

    private static func isFolder(_ url: URL) throws -> Bool {
        guard url.pathExtension.lowercased() != lockedExtension else { throw FileLockerError.alreadyLocked }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { throw FileLockerError.unreadable }
        return isDirectory.boolValue
    }

    private func readLockable(_ url: URL) throws -> Data {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= Self.maxBytes else { throw FileLockerError.tooLarge }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw FileLockerError.unreadable
        }
    }

    /// `name.ext.airsign`, or `name.ext 2.airsign` when that is taken.
    private func uniqueLockedURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent(), name = url.lastPathComponent
        var candidate = dir.appendingPathComponent("\(name).\(Self.lockedExtension)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(name) \(n).\(Self.lockedExtension)")
            n += 1
        }
        return candidate
    }

    /// `name.ext`, then `name (unlocked).ext`, then `name (unlocked 2).ext`. A folder's whole name is the stem.
    private func uniqueRestoreURL(in dir: URL, name: String, isFolder: Bool = false) -> URL {
        let candidate = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let ext = isFolder ? "" : (name as NSString).pathExtension
        let stem = isFolder ? name : (name as NSString).deletingPathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var n = 1
        while true {
            let label = n == 1 ? "unlocked" : "unlocked \(n)"
            let next = dir.appendingPathComponent("\(stem) (\(label))\(suffix)")
            if !FileManager.default.fileExists(atPath: next.path) { return next }
            n += 1
        }
    }

    /// The stored name comes from inside the file; never let it point outside the folder.
    static func safeName(_ stored: String) -> String {
        let last = (stored as NSString).lastPathComponent
        return last.isEmpty || last == "." || last == ".." || last == "/" ? "unlocked-file" : last
    }
}
