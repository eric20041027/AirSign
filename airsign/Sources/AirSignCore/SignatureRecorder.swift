import Foundation

public enum AbortReason: Equatable, Sendable {
    case sensorSwitched, samplesStopped, tooShort
}

public enum RecorderEvent: Equatable {
    case waiting
    case recording(sampleCount: Int)
    case finished([MotionSample])
    case aborted(AbortReason)
}

/// Cuts one signature out of the sample stream: starts when the AirPod moves,
/// ends when it is held still, keeping a few samples of padding on both sides.
public struct SignatureRecorder {
    public static let startSpeed = 0.6
    public static let stillSpeed = 0.3
    public static let stillDuration = 0.5
    public static let maxDuration = 8.0
    public static let stallAge = 0.3
    public static let pad = 3
    public static let minSamples = 20

    private var preRoll: [MotionSample] = []
    private var rows: [MotionSample] = []
    private var started = false
    private var startT = 0.0
    private var stillSince: Double?
    private var side: BudSide?

    public init() {}

    public var isRecording: Bool { started }

    public mutating func feed(_ s: MotionSample) -> RecorderEvent {
        guard started else { return waitForOnset(s) }
        if s.side != side {
            reset()
            return .aborted(.sensorSwitched)
        }
        rows.append(s)
        stillSince = s.speed < Self.stillSpeed ? (stillSince ?? s.t) : nil
        if let stillSince, s.t - stillSince >= Self.stillDuration - 1e-9 { return finish() }
        if s.t - startT >= Self.maxDuration { return finish() }
        return .recording(sampleCount: rows.count)
    }

    /// Call periodically; a stream that goes quiet mid-signature means the finger left the sensor.
    public mutating func checkStall(lastSampleAge: TimeInterval) -> RecorderEvent? {
        guard started, lastSampleAge > Self.stallAge else { return nil }
        reset()
        return .aborted(.samplesStopped)
    }

    public mutating func reset() {
        preRoll = []
        rows = []
        started = false
        startT = 0
        stillSince = nil
        side = nil
    }

    private mutating func waitForOnset(_ s: MotionSample) -> RecorderEvent {
        guard s.speed >= Self.startSpeed else {
            preRoll.append(s)
            if preRoll.count > Self.pad { preRoll.removeFirst() }
            return .waiting
        }
        started = true
        startT = s.t
        side = s.side
        rows = preRoll.filter { $0.side == s.side } + [s]
        preRoll = []
        return .recording(sampleCount: rows.count)
    }

    private mutating func finish() -> RecorderEvent {
        let lastMoving = rows.lastIndex { $0.speed >= Self.stillSpeed } ?? 0
        let trimmed = Array(rows.prefix(lastMoving + 1 + Self.pad))
        reset()
        return trimmed.count < Self.minSamples ? .aborted(.tooShort) : .finished(trimmed)
    }
}
