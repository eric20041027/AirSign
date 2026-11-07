import Foundation

/// Dynamic time warping distance over all feature columns.
public func dtwDistance(_ a: [[Double]], _ b: [[Double]], band: Double = 0.25) -> Double {
    dtwDistance(a, b, band: band, columns: 0..<(a.first?.count ?? 0))
}

/// Banded DTW around the diagonal, normalized by the two lengths so short and long signatures compare.
/// Returns `.infinity` when either side is empty or the band cannot connect the ends.
func dtwDistance(_ a: [[Double]], _ b: [[Double]], band: Double, columns: Range<Int>) -> Double {
    let n = a.count, m = b.count
    guard n > 0, m > 0 else { return .infinity }
    let width = Int((band * Double(max(n, m))).rounded(.up))
    var previous = [Double](repeating: .infinity, count: m + 1)
    var current = [Double](repeating: .infinity, count: m + 1)
    previous[0] = 0
    for i in 1...n {
        for j in 0...m { current[j] = .infinity }
        let center = Int((Double(i * m) / Double(n)).rounded())
        let lower = max(1, center - width), upper = min(m, center + width)
        if lower <= upper {
            for j in lower...upper {
                let cost = frameDistance(a[i - 1], b[j - 1], columns)
                current[j] = cost + min(previous[j], current[j - 1], previous[j - 1])
            }
        }
        swap(&previous, &current)
    }
    return previous[m] / Double(n + m)
}

private func frameDistance(_ x: [Double], _ y: [Double], _ columns: Range<Int>) -> Double {
    var sum = 0.0
    for k in columns {
        let d = x[k] - y[k]
        sum += d * d
    }
    return sum.squareRoot()
}
