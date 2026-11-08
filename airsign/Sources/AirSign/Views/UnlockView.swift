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
                // The enrolled shapes are only drawn after the owner has proven it's them.
                templates: model.lastVerdict?.accepted == true ? (model.profile?.enrollment.templates ?? []) : [],
                lights: model.demoMode ? model.lastVerdict?.lights : nil,
                gateOne: model.demoMode ? model.lastVerdict.map { $0.rejection != .wrongBud && $0.rejection != .wrongDevice } : nil,
                latestColor: model.lastVerdict.map { $0.accepted ? Color.green : Color.red } ?? .blue,
                isCapturing: model.isCapturing
            )
            HStack {
                if model.unlockFinished {
                    Spacer()
                    Button("Done") { model.cancelToHome() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    if !model.identityNeedsCode {
                        CaptureButton()
                            .disabled(model.profile == nil || model.lockoutRemaining != nil)
                    }
                    Button("Use recovery code…") { showRecovery = true }
                    Spacer()
                    Button("Cancel") { model.cancelToHome() }
                }
            }
        }
        // A sheet keeps the Space shortcut away from the code field.
        .sheet(isPresented: $showRecovery) {
            // Pairing needs this Mac's own signature to guard the stored key, so only enrolled Macs offer it.
            RecoveryEntrySheet(canRemember: model.profile != nil && model.screen == .unlock) {
                model.submitRecoveryCode($0, rememberOnThisMac: $1)
            }
        }
    }
}

private struct RecoveryEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var remember = false
    var canRemember: Bool
    var onSubmit: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter your recovery code").font(.headline)
            TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $code)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 460)
                .onSubmit(submit)
            if canRemember {
                Toggle("Remember on this Mac: pair it with the Mac that locked this file, so your AirPods and signature open its files here next time",
                       isOn: $remember)
                    .frame(width: 460, alignment: .leading)
            }
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
        onSubmit(code, canRemember && remember)
        dismiss()
    }
}
