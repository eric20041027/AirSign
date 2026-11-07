import AirSignCore
import SwiftUI

struct EnrollView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.isReenrolling ? "Choose your new air signature" : "Enroll your air signature")
                .font(.title2.bold())
            Text("Hold one AirPod in your signing hand with a finger over its sensor, and keep the other one in the case. Press Space, sign in the air for about 2 seconds, then hold still.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(0..<MatcherConfig.enrollCount, id: \.self) { i in
                    Circle()
                        .fill(i < model.enrolledSoFar.count ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 14, height: 14)
                }
                Text("\(model.enrolledSoFar.count) of \(MatcherConfig.enrollCount)").monospacedDigit()
            }
            SignaturePad(path: model.livePath, templates: model.enrolledSoFar, lights: nil, gateOne: nil,
                         latestColor: .blue, isCapturing: model.isCapturing)
            HStack {
                CaptureButton()
                Button("Start over") { model.restartEnrollment() }
                    .disabled(model.enrolledSoFar.isEmpty)
                Spacer()
                if model.profile != nil {
                    Button("Cancel") { model.cancelToHome() }
                }
            }
        }
    }
}

/// Shown once after the first enrollment. The code is never written to disk.
struct RecoveryCodeView: View {
    @EnvironmentObject private var model: AppModel
    var code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your recovery code").font(.title2.bold())
            Text("It opens your locked files if you lose your AirPods or can't sign. AirSign shows it only this once and does not keep it. Write it down or print it, and keep it away from this Mac.")
                .foregroundStyle(.secondary)
            Text(code)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor)))
            Button("I wrote it down") { model.confirmRecoveryCodeWritten() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}
