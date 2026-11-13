import AirSignCore
import SwiftUI
import UniformTypeIdentifiers

struct BlockedView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AirSign can't read its profile").font(.title2.bold())
            HStack {
                Button("Try again") { model.retryLaunch() }
                    .disabled(model.isBusy)
                    .buttonStyle(.borderedProminent)
                Button("Unlock with the recovery code…") { pickLockedFiles() }
                Button("Reset AirSign…") { showResetConfirmation = true }
                    .disabled(model.isBusy)
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .confirmationDialog("Reset AirSign?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset and enroll again", role: .destructive) { model.beginReset() }
                .disabled(model.isBusy)
            Button("Cancel", role: .cancel) { }
                .disabled(model.isBusy)
        } message: {
            Text("Files you have locked so far will open only with their recovery code, and paired Macs are forgotten. Nothing is replaced until you finish enrolling and confirm the new recovery code.")
        }
    }

    private func pickLockedFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if let type = UTType(filenameExtension: FileLocker.lockedExtension) {
            panel.allowedContentTypes = [type]
        }
        if panel.runModal() == .OK { model.handleOpen(panel.urls) }
    }
}
