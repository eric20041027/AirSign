import Foundation

/// Packs a folder into one zip so it can be sealed like a file, and unpacks it again.
/// Uses the system's `ditto`, which keeps non-ASCII names and Finder metadata.
enum FolderArchive {
    static func zip(_ folder: URL, maxBytes: Int) throws -> Data {
        guard try size(of: folder, stoppingAbove: maxBytes) <= maxBytes else { throw FileLockerError.tooLarge }
        let work = try ScratchFolder()
        defer { work.remove() }
        let archive = work.url.appendingPathComponent("folder.zip")
        try ditto(["-c", "-k", "--keepParent", folder.path, archive.path])
        let data = try Data(contentsOf: archive)
        guard data.count <= maxBytes else { throw FileLockerError.tooLarge }
        return data
    }

    /// Unpacks into a fresh scratch folder first, then moves the one folder inside to `target`.
    static func unzip(_ data: Data, to target: URL, willPublish: (_ source: URL, _ target: URL) throws -> Void) throws {
        let work = try ScratchFolder(in: target.deletingLastPathComponent(), prefix: Scratch.partialPrefix)
        defer { work.remove() }
        let archive = work.url.appendingPathComponent("folder.zip"), out = work.url.appendingPathComponent("out")
        try data.write(to: archive)
        try ditto(["-x", "-k", archive.path, out.path])
        let items = try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "__MACOSX" }
        guard items.count == 1 else { throw FileLockerError.writeFailed("the locked folder's archive is not one folder") }
        try willPublish(items[0], target)
        try FileLocker.publish(items[0], to: target)
    }

    private static func size(of folder: URL, stoppingAbove limit: Int) throws -> Int {
        var total = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            throw FileLockerError.unreadable
        }
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isRegularFile == true { total += values.fileSize ?? 0 }
            if total > limit { break }
        }
        return total
    }

    private static func ditto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw FileLockerError.writeFailed("ditto failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
