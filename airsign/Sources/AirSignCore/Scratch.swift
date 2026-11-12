import Darwin
import Foundation

/// Keeps scratch space owned and locked through publication and cleanup.
final class ScratchFolder {
    private static let markerName = ".airsign-owner"
    let url: URL
    private var directoryFD: Int32 = -1
    private var markerFD: Int32 = -1

    init(in base: URL = FileManager.default.temporaryDirectory, prefix: String = Scratch.temporaryPrefix) throws {
        url = base.appendingPathComponent("\(prefix)\(UUID().uuidString)")
        guard mkdir(url.path, 0o700) == 0 else { throw Self.posixError() }
        do {
            directoryFD = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directoryFD >= 0 else { throw Self.posixError() }
            let pending = ".airsign-owner-pending"
            markerFD = openat(directoryFD, pending, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard markerFD >= 0 else { throw Self.posixError() }
            guard flock(markerFD, LOCK_EX) == 0 else { throw Self.posixError() }
            // A sweep must never see the marker before its lock is held.
            try FileLocker.publish(url.appendingPathComponent(pending), to: url.appendingPathComponent(Self.markerName))
        } catch {
            if directoryIsUnchanged { try? FileManager.default.removeItem(at: url) }
            release()
            throw error
        }
    }

    private init(url: URL, directoryFD: Int32, markerFD: Int32) {
        self.url = url
        self.directoryFD = directoryFD
        self.markerFD = markerFD
    }

    static func claimIfUnused(_ url: URL) -> ScratchFolder? {
        let directory = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { return nil }
        var claimed = false
        defer { if !claimed { close(directory) } }
        let marker = openat(directory, markerName, O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard marker >= 0 else { return nil }
        defer { if !claimed { close(marker) } }
        var info = stat()
        guard fstat(marker, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              flock(marker, LOCK_EX | LOCK_NB) == 0 else { return nil }
        claimed = true
        return ScratchFolder(url: url, directoryFD: directory, markerFD: marker)
    }

    @discardableResult func remove() -> Bool {
        defer { release() }
        var opened = stat(), current = stat()
        // A replacement at the same path is not ours.
        guard directoryIsUnchanged,
              fstat(markerFD, &opened) == 0,
              fstatat(directoryFD, Self.markerName, &current, AT_SYMLINK_NOFOLLOW) == 0,
              current.st_mode & S_IFMT == S_IFREG,
              opened.st_dev == current.st_dev, opened.st_ino == current.st_ino else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    private var directoryIsUnchanged: Bool {
        var opened = stat(), current = stat()
        return fstat(directoryFD, &opened) == 0 && lstat(url.path, &current) == 0
            && current.st_mode & S_IFMT == S_IFDIR
            && opened.st_dev == current.st_dev && opened.st_ino == current.st_ino
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private func release() {
        if markerFD >= 0 { close(markerFD); markerFD = -1 }
        if directoryFD >= 0 { close(directoryFD); directoryFD = -1 }
    }

    deinit { remove() }
}

public enum Scratch {
    static let temporaryPrefix = "airsign-scratch-"
    static let partialPrefix = ".airsign-partial-"

    static func isPartialName(_ name: String) -> Bool {
        name.hasPrefix(partialPrefix) && UUID(uuidString: String(name.dropFirst(partialPrefix.count))) != nil
    }

    /// Removes only owned folders that no process is still using.
    @discardableResult public static func sweepTemporaryFolders(in base: URL = FileManager.default.temporaryDirectory) -> Int {
        sweep(in: base) { name in
            name.hasPrefix(temporaryPrefix) && UUID(uuidString: String(name.dropFirst(temporaryPrefix.count))) != nil
        }
    }

    @discardableResult static func sweepPartials(in folder: URL) -> Int {
        sweep(in: folder, matching: isPartialName)
    }

    private static func sweep(in folder: URL, matching matches: (String) -> Bool) -> Int {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return 0 }
        var removed = 0
        for item in items {
            let name = item.lastPathComponent
            guard matches(name), let stale = ScratchFolder.claimIfUnused(item) else { continue }
            if stale.remove() { removed += 1 }
        }
        return removed
    }
}
