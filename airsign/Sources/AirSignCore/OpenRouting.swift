import Foundation

public enum OpenRouting {
    /// `.airsign` items unlock, anything else locks. Each list keeps the order given.
    public static func route(_ urls: [URL]) -> (toLock: [URL], toUnlock: [URL]) {
        let toUnlock = urls.filter { $0.pathExtension.lowercased() == FileLocker.lockedExtension }
        let toLock = urls.filter { $0.pathExtension.lowercased() != FileLocker.lockedExtension }
        return (toLock: toLock, toUnlock: toUnlock)
    }
}
