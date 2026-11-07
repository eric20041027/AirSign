import Foundation

public enum MatcherConfig {
    public static let durationWeight = 0.5
    /// From spike round 2: 1.2× the worst enrolled pair separated owner 10/10 from imitators 14/15.
    public static let thresholdFactor = 1.25
    public static let enrollCount = 3
    public static let band = 0.25
}

public enum MatcherError: Error, Equatable {
    case needAtLeast(Int)
    case mixedSides
}

/// Diagnostic groups shown as lights. Only the total score decides; gate 1 (bud and device) is separate.
public enum Gate: String, Codable, CaseIterable, CodingKeyRepresentable {
    case grip, sizeTempo, rhythm

    var columns: Range<Int> {
        switch self {
        case .grip: return 6..<9
        case .sizeTempo: return 3..<6
        case .rhythm: return 0..<3
        }
    }

    var usesDuration: Bool { self == .sizeTempo }
}

public struct Enrollment: Codable, Equatable {
    public var templates: [Signature]
    public var side: BudSide
    public var deviceUID: String?
    public var threshold: Double
    public var gateThresholds: [Gate: Double]
}

public struct GateLight: Equatable {
    public var gate: Gate
    /// Gate score divided by the gate's threshold: at or below 1 looks like the owner.
    public var ratio: Double
}

public enum Rejection: Equatable {
    case wrongBud, wrongDevice, scoreTooHigh
    /// A device was enrolled but the current output is not identifiable headphones; not a failed signature.
    case deviceUnknown
}

public struct Verdict: Equatable {
    public var accepted: Bool
    public var score: Double
    public var threshold: Double
    public var rejection: Rejection?
    public var lights: [GateLight]
}

/// DTW distance, stretched when one signature took much longer than the other.
public func distance(_ a: Signature, _ b: Signature, columns: Range<Int> = 0..<9, useDuration: Bool = true) -> Double {
    let warped = dtwDistance(a.features, b.features, band: MatcherConfig.band, columns: columns)
    guard useDuration else { return warped }
    let ratio = max(a.duration, 1e-3) / max(b.duration, 1e-3)
    return warped * (1 + MatcherConfig.durationWeight * abs(log(ratio)))
}

private func gateDistance(_ a: Signature, _ b: Signature, _ gate: Gate) -> Double {
    distance(a, b, columns: gate.columns, useDuration: gate.usesDuration)
}

private func worstPair(_ templates: [Signature], _ measure: (Signature, Signature) -> Double) -> Double {
    var worst = 0.0
    for i in templates.indices {
        for j in templates.indices where j > i {
            worst = max(worst, measure(templates[i], templates[j]))
        }
    }
    return worst
}

public func enroll(_ sigs: [Signature], deviceUID: String?) throws -> Enrollment {
    guard sigs.count >= MatcherConfig.enrollCount else { throw MatcherError.needAtLeast(MatcherConfig.enrollCount) }
    guard let side = sigs.first?.side, sigs.allSatisfy({ $0.side == side }) else { throw MatcherError.mixedSides }
    let factor = MatcherConfig.thresholdFactor
    var gateThresholds: [Gate: Double] = [:]
    for gate in Gate.allCases {
        gateThresholds[gate] = factor * worstPair(sigs) { gateDistance($0, $1, gate) }
    }
    return Enrollment(
        templates: sigs,
        side: side,
        deviceUID: deviceUID,
        threshold: factor * worstPair(sigs) { distance($0, $1) },
        gateThresholds: gateThresholds
    )
}

/// `override` can only make the check stricter than the enrolled threshold, never looser.
public func verify(_ sig: Signature, deviceUID: String?, against e: Enrollment, threshold override: Double? = nil) -> Verdict {
    let threshold = min(override ?? e.threshold, e.threshold)
    let score = e.templates.map { distance(sig, $0) }.min() ?? .infinity
    let lights = Gate.allCases.map { gate in
        let best = e.templates.map { gateDistance(sig, $0, gate) }.min() ?? .infinity
        return GateLight(gate: gate, ratio: best / max(e.gateThresholds[gate] ?? 0, 1e-6))
    }
    let rejection: Rejection?
    if sig.side != e.side {
        rejection = .wrongBud
    } else if e.deviceUID != nil, deviceUID == nil {
        rejection = .deviceUnknown
    } else if let enrolled = e.deviceUID, deviceUID != enrolled {
        rejection = .wrongDevice
    } else if !(score <= threshold) {
        rejection = .scoreTooHigh
    } else {
        rejection = nil
    }
    return Verdict(accepted: rejection == nil, score: score, threshold: threshold, rejection: rejection, lights: lights)
}
