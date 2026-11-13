import AirSignCore
import CoreMotion
import Foundation

enum MotionStatus: Equatable {
    case unavailable
    case denied
    case waitingForAirPods
    case streaming(BudSide)
}

/// Streams AirPods motion as `MotionSample`s on the main thread.
final class HeadphoneMotionSource: NSObject, CMHeadphoneMotionManagerDelegate {
    var onSample: ((MotionSample) -> Void)?
    var onStatus: ((MotionStatus) -> Void)?
    private(set) var lastSampleDate: Date?
    private(set) var status: MotionStatus = .waitingForAirPods

    private let manager = CMHeadphoneMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    func start() {
        guard manager.isDeviceMotionAvailable else {
            report(.unavailable)
            return
        }
        if Self.isDenied {
            report(.denied)
            return
        }
        manager.delegate = self
        report(.waitingForAirPods)
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            if let error {
                NSLog("AirSign: headphone motion error: %@", error.localizedDescription)
                DispatchQueue.main.async { if Self.isDenied { self?.report(.denied) } }
                return
            }
            guard let motion else { return }
            let sample = Self.sample(from: motion)
            DispatchQueue.main.async { self?.deliver(sample) }
        }
    }

    /// Call periodically: no samples for a second means the AirPod left the ear or the finger left the sensor.
    func refreshStaleness(now: Date = Date()) {
        guard case .streaming = status, let last = lastSampleDate, now.timeIntervalSince(last) > 1 else { return }
        report(.waitingForAirPods)
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async { self.report(.waitingForAirPods) }
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {}

    // MARK: - Private

    private static var isDenied: Bool {
        let auth = CMHeadphoneMotionManager.authorizationStatus()
        return auth == .denied || auth == .restricted
    }

    private func deliver(_ sample: MotionSample) {
        lastSampleDate = Date()
        if status != .streaming(sample.side) { report(.streaming(sample.side)) }
        onSample?(sample)
    }

    private func report(_ newStatus: MotionStatus) {
        status = newStatus
        onStatus?(newStatus)
    }

    private static func sample(from motion: CMDeviceMotion) -> MotionSample {
        let q = motion.attitude.quaternion, r = motion.rotationRate, a = motion.userAcceleration, g = motion.gravity
        let side: BudSide
        switch motion.sensorLocation {
        case .headphoneLeft: side = .left
        case .headphoneRight: side = .right
        default: side = .unknown
        }
        return MotionSample(t: motion.timestamp, quat: SIMD4(q.x, q.y, q.z, q.w), rot: SIMD3(r.x, r.y, r.z),
                            acc: SIMD3(a.x, a.y, a.z), grav: SIMD3(g.x, g.y, g.z), side: side)
    }
}
