import AirSignCore
import SwiftUI

/// Draws the signature's shape (gyro integrated over time) so judges watching a screen share can see it,
/// plus the gate lights in demo mode.
struct SignaturePad: View {
    var path: [SIMD3<Double>]
    var templates: [Signature]
    var lights: [GateLight]?
    /// Gate 1 (same AirPods, same bud): nil hides it.
    var gateOne: Bool?
    var latestColor: Color
    var isCapturing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in draw(in: &context, size: size) }
                .frame(minHeight: 240)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isCapturing ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isCapturing ? 2 : 1)
                )
            if let lights {
                HStack(spacing: 18) {
                    if let gateOne { Light(label: "AirPod", color: gateOne ? .green : .red, detail: nil) }
                    ForEach(lights, id: \.gate) { light in
                        Light(label: Self.label(light.gate), color: Self.color(light.ratio),
                              detail: String(format: "×%.2f", light.ratio))
                    }
                }
                .font(.callout)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let projection = Projection(reference: templates.first?.path ?? path)
        var shapes = templates.map { (points: projection.points($0.path), color: Color.secondary.opacity(0.45)) }
        if path.count > 1 { shapes.append((projection.points(path), isCapturing ? Color.accentColor : latestColor)) }
        guard !shapes.isEmpty else {
            context.draw(Text("Your signature appears here").foregroundStyle(.secondary),
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        let extent = max(1e-3, shapes.flatMap(\.points).map { max(abs($0.x), abs($0.y)) }.max() ?? 1e-3)
        let scale = (min(size.width, size.height) / 2 - 16) / extent
        for shape in shapes {
            var line = Path()
            for (i, point) in shape.points.enumerated() {
                let q = CGPoint(x: size.width / 2 + point.x * scale, y: size.height / 2 + point.y * scale)
                if i == 0 { line.move(to: q) } else { line.addLine(to: q) }
            }
            context.stroke(line, with: .color(shape.color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    private static func label(_ gate: Gate) -> String {
        switch gate {
        case .grip: return "Grip & plane"
        case .sizeTempo: return "Size & tempo"
        case .rhythm: return "Rhythm"
        }
    }

    /// At or under the enrolled spread is green; up to 1.5× is yellow; beyond is red.
    private static func color(_ ratio: Double) -> Color {
        ratio <= 1 ? .green : ratio <= 1.5 ? .yellow : .red
    }
}

private struct Light: View {
    var label: String
    var color: Color
    var detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(label)
            if let detail { Text(detail).foregroundStyle(.secondary).monospacedDigit() }
        }
    }
}

/// Projects 3-D gyro paths onto the reference path's two main directions, each path centred on itself.
private struct Projection {
    let first: SIMD3<Double>
    let second: SIMD3<Double>

    init(reference: [SIMD3<Double>]) {
        (first, second) = Self.principalAxes(reference)
    }

    func points(_ path: [SIMD3<Double>]) -> [CGPoint] {
        guard !path.isEmpty else { return [] }
        let mean = path.reduce(SIMD3<Double>.zero, +) / Double(path.count)
        return path.map { p in
            let d = p - mean
            return CGPoint(x: (d * first).sum(), y: -(d * second).sum())
        }
    }

    private static func principalAxes(_ path: [SIMD3<Double>]) -> (SIMD3<Double>, SIMD3<Double>) {
        guard path.count > 2 else { return (SIMD3(1, 0, 0), SIMD3(0, 1, 0)) }
        let mean = path.reduce(SIMD3<Double>.zero, +) / Double(path.count)
        var rows = [SIMD3<Double>](repeating: .zero, count: 3)
        for p in path {
            let d = p - mean
            rows[0] += d * d.x
            rows[1] += d * d.y
            rows[2] += d * d.z
        }
        let multiply = { (v: SIMD3<Double>) in SIMD3((rows[0] * v).sum(), (rows[1] * v).sum(), (rows[2] * v).sum()) }
        let v1 = powerIteration(multiply)
        let l1 = (v1 * multiply(v1)).sum()
        let v2 = powerIteration { v in multiply(v) - v1 * (l1 * (v1 * v).sum()) }
        return (v1, v2)
    }

    private static func powerIteration(_ apply: (SIMD3<Double>) -> SIMD3<Double>) -> SIMD3<Double> {
        var v = SIMD3(0.6, 0.5, 0.62)
        for _ in 0..<60 {
            let next = apply(v)
            let length = (next * next).sum().squareRoot()
            guard length > 1e-12 else { break }
            v = next / length
        }
        return v
    }
}
