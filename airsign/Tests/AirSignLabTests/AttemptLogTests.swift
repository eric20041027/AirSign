import Foundation
import Testing
import AirSignCore
import AirSignLab
import AirSignTestSupport

@Test func attemptLogWritesSpikeCompatibleJSON() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let log = AttemptLog(directory: dir)
    let rows = strokes(ownerShape, n: 60, noise: 0.1)
    let e = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.2)) }, deviceUID: "UID-A")
    let verdict = verify(Signature(samples: rows), deviceUID: "UID-A", against: e)
    let labels = AttemptLabels(tester: "B", scenario: "A4-skilled", session: "S1", owner: "A")

    let url = try log.write(mode: .verify, labels: labels, samples: rows, verdict: verdict)

    #expect(url.lastPathComponent.hasPrefix("attempt-") && url.pathExtension == "json")
    let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(json["mode"] as? String == "verify")
    #expect(json["who"] as? String == "forgery")
    #expect(json["tester"] as? String == "B" && json["scenario"] as? String == "A4-skilled")
    #expect(json["session"] as? String == "S1" && json["owner"] as? String == "A")
    #expect(json["loc"] as? String == "right")
    #expect((json["rows"] as? [[Double]])?.count == 60)
    #expect((json["rows"] as? [[Double]])?.first?.count == 14)
    #expect(json["accepted"] as? Bool == verdict.accepted)
    #expect(abs((json["score"] as? Double ?? .nan) - verdict.score) < 1e-12)
    #expect(abs((json["threshold"] as? Double ?? .nan) - verdict.threshold) < 1e-12)
    #expect((json["lights"] as? [String: Double])?.keys.sorted() == ["grip", "rhythm", "sizeTempo"])
    // Rows written by the log parse back into the same samples the spike tools use.
    let parsed = (json["rows"] as? [[Double]] ?? []).map { MotionSample.fromSpikeRow($0, loc: "right") }
    let close = { (a: MotionSample, b: MotionSample) in
        abs(a.t - b.t) < 1e-9 && ((a.rot - b.rot) * (a.rot - b.rot)).sum() < 1e-18
            && ((a.acc - b.acc) * (a.acc - b.acc)).sum() < 1e-18 && a.side == b.side
    }
    #expect(parsed.count == rows.count && zip(parsed, rows).allSatisfy(close))
}

@Test func enrollmentFingerprintIsStableAndLinksRecords() throws {
    let sigs = (0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.2)) }
    let e = try enroll(sigs, deviceUID: "UID-A")
    let again = try JSONDecoder().decode(Enrollment.self, from: JSONEncoder().encode(e))
    let other = try enroll((0..<3).map { _ in Signature(samples: strokes(ownerShape, noise: 0.2)) }, deviceUID: "UID-A")
    #expect(e.fingerprint == again.fingerprint && e.fingerprint.count == 12)
    #expect(e.fingerprint != other.fingerprint)

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var labels = AttemptLabels(tester: "A", scenario: AttemptLabels.ownerScenario, session: "S1", owner: "A")
    labels.enrollment = e.fingerprint
    let url = try AttemptLog(directory: dir).write(mode: .enroll, labels: labels, samples: strokes(ownerShape, n: 30), verdict: nil)
    let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(json["enrollment"] as? String == e.fingerprint)
}

@Test func ownerScenarioIsGenuineAndEnrollmentsHaveNoVerdict() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let log = AttemptLog(directory: dir)
    let labels = AttemptLabels(tester: "A", scenario: AttemptLabels.ownerScenario, session: "S1", owner: "A")
    let url = try log.write(mode: .enroll, labels: labels, samples: strokes(ownerShape, n: 30), verdict: nil)
    let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(json["mode"] as? String == "enroll" && json["who"] as? String == "genuine")
    #expect(json["accepted"] == nil || json["accepted"] is NSNull)
    let second = try log.write(mode: .enroll, labels: labels, samples: strokes(ownerShape, n: 30), verdict: nil)
    #expect(second != url)
}
