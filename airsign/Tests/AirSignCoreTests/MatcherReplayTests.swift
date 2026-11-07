import Foundation
import Testing
@testable import AirSignCore

// Real recordings from the spike stay out of git (biometric-like data), so this test
// only runs on a machine that has them.
private let sessions = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../../spikes/airpods-motion/sessions").standardized

private struct Attempt {
    let id: String
    let mode: String
    let who: String
    let dur: Double
    let samples: [MotionSample]
}

private func loadAttempts() throws -> [Attempt] {
    let files = try FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("attempt-") && $0.pathExtension == "json" }
    return try files.map { url in
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let rows = try #require(object["rows"] as? [[Double]])
        let loc = object["loc"] as? String ?? "unknown"
        let name = url.deletingPathExtension().lastPathComponent
        return Attempt(
            id: String(name.dropFirst("attempt-20261107-".count)),
            mode: object["mode"] as? String ?? "",
            who: object["who"] as? String ?? "",
            dur: object["dur"] as? Double ?? 0,
            samples: rows.map { MotionSample.fromSpikeRow($0, loc: loc) }
        )
    }
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: sessions.path)))
func roundTwoOwnerVersusImitatorAUC() throws {
    let all = try loadAttempts()
    let templates = ["144527-280", "144533-012", "144616-034"]
        .compactMap { id in all.first { $0.id == id } }
        .map { Signature(samples: $0.samples) }
    try #require(templates.count == 3)
    let enrollment = try enroll(templates, deviceUID: nil)

    let attempts = all.filter { $0.mode == "verify" && $0.id >= "144617" && $0.id <= "145000" && $0.dur > 1.2 }
    let score = { (a: Attempt) in verify(Signature(samples: a.samples), deviceUID: nil, against: enrollment).score }
    let owner = attempts.filter { $0.who == "genuine" }.map(score)
    let fake = attempts.filter { $0.who == "forgery" }.map(score)
    try #require(!owner.isEmpty && !fake.isEmpty)

    let wins = fake.flatMap { f in owner.map { o in f > o ? 1.0 : (f == o ? 0.5 : 0) } }.reduce(0, +)
    let auc = wins / Double(owner.count * fake.count)
    #expect(auc >= 0.9)   // spike measured 0.96
}
