import Foundation
import Testing
@testable import AirSignCore
import AirSignTestSupport

private func finished(_ events: [RecorderEvent]) -> [[MotionSample]] {
    events.compactMap { if case .finished(let s) = $0 { s } else { nil } }
}

@Test func recordsFromOnsetUntilStillWithPadding() {
    var r = SignatureRecorder()
    let idle = (0..<10).map { sample($0, speed: 0.1) }
    let moving = (10..<70).map { sample($0, speed: 2.0) }
    let still = (70..<110).map { sample($0, speed: 0.1) }
    let done = finished(run(&r, idle + moving + still))
    #expect(done.count == 1)
    #expect(done.first?.count == 3 + 60 + 3)
    #expect(done.first?.first?.t == sample(7, speed: 0).t)
}

@Test func switchingBudAbortsTheAttempt() {
    var r = SignatureRecorder()
    let events = run(&r, (0..<30).map { sample($0, speed: 2.0) } + [sample(30, speed: 2.0, side: .left)])
    #expect(events.last == .aborted(.sensorSwitched))
}

@Test func stalledStreamAbortsOnlyWhileRecording() {
    var r = SignatureRecorder()
    #expect(r.checkStall(lastSampleAge: 1.0) == nil)
    _ = run(&r, (0..<5).map { sample($0, speed: 2.0) })
    #expect(r.checkStall(lastSampleAge: 0.31) == .aborted(.samplesStopped))
    #expect(r.isRecording == false)
}

@Test func shortBurstIsTooShort() {
    var r = SignatureRecorder()
    let events = run(&r, (0..<8).map { sample($0, speed: 2.0) } + (8..<40).map { sample($0, speed: 0.1) })
    #expect(events.contains(.aborted(.tooShort)))
}

@Test func longSigningStopsAtMaxDuration() {
    var r = SignatureRecorder()
    let done = finished(run(&r, (0..<500).map { sample($0, speed: 2.0) }))
    #expect(done.count >= 1)
    if let first = done.first, let start = first.first, let end = first.last {
        #expect(end.t - start.t <= 8.0 + 0.1)
    }
}

@Test func spikeRowParsesColumnsInOrder() {
    let row: [Double] = [1.5, 0.1, 0.2, 0.3, 0.9, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    let s = MotionSample.fromSpikeRow(row, loc: "left")
    #expect(s.t == 1.5 && s.quat == SIMD4(0.1, 0.2, 0.3, 0.9))
    #expect(s.rot == SIMD3(1, 2, 3) && s.acc == SIMD3(4, 5, 6) && s.grav == SIMD3(7, 8, 9))
    #expect(s.side == .left)
}
