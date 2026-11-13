import AirSignCore
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AirSign is ready").font(.title2.bold())
            Text("Right-click any file in Finder → Lock with AirSign. To open it, right-click the .airsign file → Unlock with AirSign, then sign in the air.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Lock a file…") { pick(lockedFiles: false) }
                Button("Unlock a file…") { pick(lockedFiles: true) }
                #if AIRSIGN_LAB
                if model.testMode {
                    Button("Open test lab") { model.beginLab() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
                #endif
            }
            Divider()
            SettingsView()
        }
    }

    private func pick(lockedFiles: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = !lockedFiles
        if lockedFiles, let type = UTType(filenameExtension: FileLocker.lockedExtension) {
            panel.allowedContentTypes = [type]
        }
        if panel.runModal() == .OK { model.handleOpen(panel.urls) }
    }
}
