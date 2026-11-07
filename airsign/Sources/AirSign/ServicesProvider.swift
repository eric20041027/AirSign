import AppKit
import Foundation

final class ServicesProvider: NSObject {
    var onFiles: (([URL]) -> Void)?

    init(onFiles: (([URL]) -> Void)? = nil) {
        self.onFiles = onFiles
        super.init()
    }

    @objc func lockFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        handleFiles(from: pboard)
    }

    @objc func unlockFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        handleFiles(from: pboard)
    }

    private func handleFiles(from pboard: NSPasteboard) {
        let urls = extractURLs(from: pboard)
        guard !urls.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onFiles?(urls)
        }
    }

    private func extractURLs(from pboard: NSPasteboard) -> [URL] {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return urls
        }
        if let filenames = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            return filenames.map { URL(fileURLWithPath: $0) }
        }
        return []
    }
}
