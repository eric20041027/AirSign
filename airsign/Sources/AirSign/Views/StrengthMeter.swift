import AirSignCore
import SwiftUI

/// Three-segment bar like a password-strength meter, with what was measured and what to fix.
struct StrengthMeter: View {
    var strength: SignatureStrength
    /// During enrollment a weak signature is refused; in Settings it is an already-enrolled one.
    var isEnrolling = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Strength").frame(width: 52, alignment: .leading)
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i <= strength.level.rawValue ? color : Color.secondary.opacity(0.25))
                            .frame(width: 34, height: 8)
                    }
                }
                Text(label).bold().foregroundStyle(color)
            }
            Text(metricsLine).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            ForEach(strength.issues, id: \.self) { issue in
                Text("• " + AppModel.describe(issue, strength.metrics).capitalizedFirst)
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var label: String {
        switch strength.level {
        case .weak: return isEnrolling ? "Weak: refused" : "Weak: consider changing it"
        case .fair: return "Fair"
        case .strong: return "Strong"
        }
    }

    private var color: Color {
        switch strength.level {
        case .weak: return .red
        case .fair: return .orange
        case .strong: return .green
        }
    }

    private var metricsLine: String {
        let m = strength.metrics
        return String(format: "%.1f s · %.1f rad of turning · %d changes of direction · %.0f%% on one axis",
                      m.duration, m.turning, m.reversals, m.dominantShare * 100)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
