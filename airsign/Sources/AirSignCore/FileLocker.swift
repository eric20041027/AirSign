import CryptoKit
import Darwin
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
    private let willPublish: (URL, URL) throws -> Void
    private let willWriteLocked: (URL) throws -> Void

    public init(trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.init(trash: trash, willPublish: { _, _ in })
    }

    init(trash: @escaping (URL) throws -> Void, willPublish: @escaping (_ source: URL, _ target: URL) throws -> Void,
         willWriteLocked: @escaping (URL) throws -> Void = { _ in }) {
        self.trash = trash
        self.willPublish = willPublish
        self.willWriteLocked = willWriteLocked
    }

    public func lock(_ url: URL, masterKey: SymmetricKey, recoveryPublicKey: Curve25519.KeyAgreement.PublicKey) throws -> URL {
        let isFolder = try Self.isFolder(url)
        let plaintext = isFolder ? try FolderArchive.zip(url, maxBytes: Self.maxBytes) : try readLockable(url)
        let sealed = try LockedFile.seal(plaintext, originalName: url.lastPathComponent, masterKey: masterKey,
                                         recoveryPublicKey: recoveryPublicKey, kind: isFolder ? LockedFileHeader.folderKind : nil)
        let target = uniqueLockedURL(for: url)
        var createdOutput = false
        do {
            try willWriteLocked(target)
            try sealed.write(to: target, options: .withoutOverwriting)
            createdOutput = true
            let reopened = try LockedFile.open(Data(contentsOf: target), masterKey: masterKey)
            guard SHA256.hash(data: reopened.plaintext) == SHA256.hash(data: plaintext) else {
                throw FileLockerError.writeFailed("the locked copy did not decrypt to the same bytes")
            }
            try trash(url)
        } catch {
            if createdOutput { _ = unlink(target.path) }
            throw (error as? FileLockerError) ?? FileLockerError.writeFailed(error.localizedDescription)
        }
        return target
    }

    public func unlock(_ url: URL, open: (Data) throws -> (name: String, plaintext: Data)) throws -> URL {
        Scratch.sweepPartials(in: url.deletingLastPathComponent())
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
                try FolderArchive.unzip(opened.plaintext, to: target, willPublish: willPublish)
            } else {
                let partial = try ScratchFolder(in: target.deletingLastPathComponent(), prefix: Scratch.partialPrefix)
                defer { partial.remove() }
                let source = partial.url.appendingPathComponent("payload")
                try opened.plaintext.write(to: source, options: .withoutOverwriting)
                try willPublish(source, target)
                try Self.publish(source, to: target)
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

    /// Moves `source` to `target` and never replaces what is at `target`.
    static func publish(_ source: URL, to target: URL,
                        exclusiveRename: (_ from: String, _ to: String) -> Int32 = FileLocker.exclusiveRename) throws {
        let failure = exclusiveRename(source.path, target.path)
        guard failure != 0 else { return }
        guard failure == ENOTSUP else { throw publicationError(failure) }
        var info = stat()
        guard lstat(source.path, &info) == 0 else { throw publicationError(errno) }
        switch info.st_mode & S_IFMT {
        case S_IFDIR: try publishFolder(source, to: target)
        case S_IFREG: try publishFile(source, to: target, permissions: info.st_mode & 0o7777)
        default: throw publicationError(ENOTSUP)
        }
    }

    /// 0, or the errno of `renamex_np(from, to, RENAME_EXCL)`.
    static func exclusiveRename(_ from: String, _ to: String) -> Int32 {
        renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
    }

    private static func publishFolder(_ source: URL, to target: URL) throws {
        guard mkdir(target.path, 0o700) == 0 else { throw publicationError(errno) }
        guard rename(source.path, target.path) == 0 else {
            let failure = errno
            _ = rmdir(target.path)
            throw publicationError(failure)
        }
    }

    private static func publishFile(_ source: URL, to target: URL, permissions: mode_t) throws {
        let descriptor = Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, permissions)
        guard descriptor >= 0 else { throw publicationError(errno) }
        defer { close(descriptor) }
        do {
            try copyBytes(from: source, to: descriptor)
            // Preserve the source mode even when the umask restricted the create.
            guard fchmod(descriptor, permissions) == 0 else { throw publicationError(errno) }
        } catch {
            removePublishedFile(target, descriptor: descriptor)
            throw (error as? FileLockerError) ?? FileLockerError.writeFailed(error.localizedDescription)
        }
        _ = unlink(source.path)
    }

    private static func copyBytes(from source: URL, to descriptor: Int32) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

    private static func removePublishedFile(_ target: URL, descriptor: Int32) {
        var created = stat(), current = stat()
        guard fstat(descriptor, &created) == 0, lstat(target.path, &current) == 0,
              created.st_dev == current.st_dev, created.st_ino == current.st_ino else { return }
        _ = unlink(target.path)
    }

    private static func publicationError(_ code: Int32) -> FileLockerError {
        .writeFailed(NSError(domain: NSPOSIXErrorDomain, code: Int(code)).localizedDescription)
    }

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
        if Scratch.isPartialName(last) { return String(last.dropFirst()) }
        return last.isEmpty || last == "." || last == ".." || last == "/" ? "unlocked-file" : last
    }
}
