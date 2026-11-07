import AirSignCore
import SwiftUI

@main
struct AirSignApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("AirSign") {
            Text("AirSign")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest-keychain") {
            runKeychainSelfTest()
        }
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
