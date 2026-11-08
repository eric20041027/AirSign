import AirSignCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.headline)
            Toggle("Demo mode: show the signature, score, lights and reasons",
                   isOn: Binding(get: { model.demoMode }, set: { model.setDemoMode($0) }))
            if model.demoMode, let enrolled = model.profile?.enrollment.threshold {
                HStack {
                    Text("Threshold (stricter only)")
                    Slider(value: Binding(get: { model.thresholdOverride ?? enrolled },
                                          set: { model.thresholdOverride = $0 }),
                           in: 0...max(enrolled, 0.01))
                    Text(AppModel.format(model.thresholdOverride ?? enrolled)).monospacedDigit()
                    Button("Reset") { model.thresholdOverride = nil }
                        .disabled(model.thresholdOverride == nil)
                }
            }
            if let enrollment = model.profile?.enrollment {
                HStack {
                    Text("Enrolled with the \(enrollment.side.rawValue) AirPod · \(enrollment.templates.count) signatures"
                         + (enrollment.addedCount > 0 ? " (\(enrollment.addedCount) added after unlocking)" : "")
                         + " · threshold \(AppModel.format(enrollment.threshold))")
                        .foregroundStyle(.secondary)
                    if enrollment.addedCount > 0 {
                        Button("Remove added signatures") { model.removeAddedSamples() }
                    }
                }
            }
            if let strength = model.enrolledStrength {
                StrengthMeter(strength: strength, isEnrolling: false)
            }
            HStack {
                Text("Paired Macs: \(model.pairedMacCount)").foregroundStyle(.secondary)
                Button("Forget paired Macs") { model.forgetPairedMacs() }
                    .disabled(model.pairedMacCount == 0)
            }
            Button("Change signature…") { model.beginChangeSignature() }
        }
    }
}
