#if AIRSIGN_LAB
import AirSignCore
import AppKit
import SwiftUI

/// Scenarios from the evaluation plan. Only A1 is the owner; every other one is an imitation.
enum TestScenario: String, CaseIterable, Identifiable {
    case owner = "A1-owner"
    case zeroEffort = "A2-zero-effort"
    case watchedOnce = "A3-watched-once"
    case skilled = "A4-skilled"
    case otherBud = "A5-other-bud"
    case otherPair = "A5-other-pair"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner: return "A1 Owner signs their own signature"
        case .zeroEffort: return "A2 Imitator signs their own name"
        case .watchedOnce: return "A3 Imitator watched the owner once"
        case .skilled: return "A4 Skilled imitator (video ×3, knows grip and plane, practiced 5 min)"
        case .otherBud: return "A5 Owner's signature with the other AirPod"
        case .otherPair: return "A5 Owner's signature with a different pair of AirPods"
        }
    }

    /// Target count per tester and session.
    var target: Int {
        switch self {
        case .owner: return 20
        case .skilled: return 25
        case .zeroEffort, .watchedOnce, .otherBud, .otherPair: return 10
        }
    }
}

enum TestSession: String, CaseIterable, Identifiable {
    case tonight = "S1-tonight"
    case midnight = "S2-midnight"
    case morning = "S3-morning"
    case extra = "S4-extra"

    var id: String { rawValue }
}

struct TestModeBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.testMode {
                Text("TEST MODE · Test-lab attempts are logged and never count toward the lockout · Unlocking files still uses it")
            }
            if let path = model.sandboxPath {
                Text("Sandbox data: \(path)")
            }
        }
        .font(.callout.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red))
    }
}

struct TestLabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test lab").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Owner")
                    TextField("Owner's name", text: $model.testOwner).frame(width: 180)
                    Text("Tester")
                    TextField("Who is signing now", text: $model.testTester).frame(width: 180)
                }
                GridRow {
                    Text("Session")
                    Picker("", selection: $model.testSession) {
                        ForEach(TestSession.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    Text("Scenario")
                    Picker("", selection: $model.testScenario) {
                        ForEach(TestScenario.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }
            Text(model.testScenario.title).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                ForEach(TestScenario.allCases) { scenario in
                    let count = model.labCount(for: scenario)
                    Text("\(scenario.rawValue.prefix(2)) \(count)/\(scenario.target)")
                        .monospacedDigit()
                        .foregroundStyle(count >= scenario.target ? Color.green : (scenario == model.testScenario ? .primary : .secondary))
                }
            }
            .font(.callout)
            SignaturePad(
                path: model.livePath,
                templates: [],
                lights: model.lastVerdict?.lights,
                gateOne: model.lastVerdict.map { $0.rejection != .wrongBud && $0.rejection != .wrongDevice },
                latestColor: model.lastVerdict.map { $0.accepted ? Color.green : Color.red } ?? .blue,
                isCapturing: model.isCapturing
            )
            HStack {
                CaptureButton()
                Button("Re-enroll owner (logged)") { model.reenrollOwnerFromLab() }
                Button("Open log folder") {
                    let dir = AttemptLog.defaultDirectory
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                Spacer()
                Button("Leave lab") { model.leaveLab() }
            }
        }
    }
}
#endif
