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
                Text("Enrolled with the \(enrollment.side.rawValue) AirPod · \(enrollment.templates.count) signatures · threshold \(AppModel.format(enrollment.threshold))")
                    .foregroundStyle(.secondary)
            }
            Button("Change signature…") { model.beginChangeSignature() }
        }
    }
}
