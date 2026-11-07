import AirSignCore
import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showRecovery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.screen == .confirmIdentity ? "Confirm it's you" : "Unlock with AirSign")
                .font(.title2.bold())
            if !model.pendingUnlock.isEmpty {
                Text(model.pendingUnlock.map(\.lastPathComponent).joined(separator: ", "))
                    .font(.callout.monospaced())
            }
            if let remaining = model.lockoutRemaining {
                Text("Too many tries. Try again in \(Int(remaining.rounded(.up))) s.")
                    .foregroundStyle(.red)
                    .monospacedDigit()
            }
            SignaturePad(
                path: model.livePath,
                templates: model.profile?.enrollment.templates ?? [],
                lights: model.demoMode ? model.lastVerdict?.lights : nil,
                gateOne: model.demoMode ? model.lastVerdict.map { $0.rejection != .wrongBud && $0.rejection != .wrongDevice } : nil,
                latestColor: model.lastVerdict.map { $0.accepted ? Color.green : Color.red } ?? .blue,
                isCapturing: model.isCapturing
            )
            HStack {
                CaptureButton()
                    .disabled(model.profile == nil || model.lockoutRemaining != nil)
                Button("Use recovery code…") { showRecovery = true }
                Spacer()
                Button("Cancel") { model.cancelToHome() }
            }
        }
        // A sheet keeps the Space shortcut away from the code field.
        .sheet(isPresented: $showRecovery) {
            RecoveryEntrySheet { model.submitRecoveryCode($0) }
        }
    }
}

private struct RecoveryEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    var onSubmit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter your recovery code").font(.headline)
            TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $code)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 460)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Unlock", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func submit() {
        onSubmit(code)
        dismiss()
    }
}
