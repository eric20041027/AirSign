import AirSignCore
import SwiftUI

@main
struct AirSignApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("AirSign", id: "main") {
            ContentView()
                .environmentObject(appDelegate.model)
        }
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel()
    private var services: ServicesProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Scratch.sweepTemporaryFolders()
        if CommandLine.arguments.contains("--selftest-keychain") {
            runKeychainSelfTest()
        }
        if CommandLine.arguments.contains("--probe") {
            ProbeMode.run()
            return
        }
        registerFinderServices()
    }

    /// Finder → right-click → "Lock with AirSign" / "Unlock with AirSign" (declared under NSServices in Info.plist).
    private func registerFinderServices() {
        let provider = ServicesProvider { [weak self] urls in
            MainActor.assumeIsolated { self?.model.handleOpen(urls) }
        }
        services = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
    }

    /// Double-clicking an `.airsign` file or `open -a AirSign <file>` arrives here.
    func application(_ application: NSApplication, open urls: [URL]) {
        model.handleOpen(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // Proves the Keychain item written by one build is readable by the next build without a prompt.
    private func runKeychainSelfTest() {
        let store = KeychainSecretStore()
        do {
            if let found = try store.load("selftest") {
                print("FOUND \(found.hexString)")
            } else {
                let bytes = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
                try store.save(bytes, as: "selftest")
                print("SAVED \(bytes.hexString)")
            }
        } catch {
            print("ERROR \(error)")
        }
        fflush(stdout)
        exit(0)
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
