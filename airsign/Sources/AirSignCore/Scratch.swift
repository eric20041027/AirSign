import Foundation

public enum Scratch {
    static let temporaryPrefix = "airsign-scratch-"
    static let partialPrefix = ".airsign-partial-"

    /// Keeps temporary plaintext private to the current user.
    static func makeTemporaryFolder(in base: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let folder = base.appendingPathComponent("\(temporaryPrefix)\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return folder
    }

    static func partialURL(in folder: URL) -> URL {
        folder.appendingPathComponent("\(partialPrefix)\(UUID().uuidString)")
    }

    static func isPartialName(_ name: String) -> Bool {
        name.hasPrefix(partialPrefix) && UUID(uuidString: String(name.dropFirst(partialPrefix.count))) != nil
    }

    /// Removes scratch items a previous run may have left behind.
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
            guard matches(name) else { continue }
            do {
                try fm.removeItem(at: item)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }
}
