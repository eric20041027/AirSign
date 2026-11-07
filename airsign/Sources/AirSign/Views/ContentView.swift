import AirSignCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.testMode { TestModeBanner() }
            HStack {
                Text("AirSign").font(.largeTitle.bold())
                Spacer()
                MotionStatusPill(status: model.motionStatus)
            }
            Group {
                if let code = model.recoveryCodeToShow {
                    RecoveryCodeView(code: code)
                } else {
                    switch model.screen {
                    case .enroll: EnrollView()
                    case .unlock, .confirmIdentity: UnlockView()
                    case .lab: TestLabView()
                    case .home: HomeView()
                    }
                }
            }
            if !model.message.isEmpty {
                Text(model.message)
                    .foregroundStyle(Self.color(model.tone))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 600, alignment: .topLeading)
    }

    static func color(_ tone: Tone) -> Color {
        switch tone {
        case .neutral: return .primary
        case .good: return .green
        case .warn: return .orange
        case .bad: return .red
        }
    }
}

/// Space starts a capture; pressing it again cancels.
struct CaptureButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button(model.isCapturing ? "Cancel (Space)" : "Start signing (Space)") { model.toggleCapture() }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}

private struct MotionStatusPill: View {
    var status: MotionStatus

    var body: some View {
        Label(text, systemImage: "airpods")
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private var text: String {
        switch status {
        case .streaming(let side): return "\(side.rawValue.capitalized) AirPod streaming"
        case .waitingForAirPods: return "Hold an AirPod with a finger over its sensor"
        case .denied: return "Motion access denied: System Settings → Privacy & Security → Motion & Fitness"
        case .unavailable: return "Headphone motion unavailable on this Mac"
        }
    }

    private var color: Color {
        switch status {
        case .streaming: return .green
        case .waitingForAirPods: return .orange
        case .denied, .unavailable: return .red
        }
    }
}
