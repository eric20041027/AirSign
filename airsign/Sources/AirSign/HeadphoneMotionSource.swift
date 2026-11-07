import AirSignCore
import CoreMotion
import Foundation

public enum MotionStatus: Equatable, Sendable {
    case unavailable
    case denied
    case waitingForAirPods
    case streaming(BudSide)
}

final class HeadphoneMotionSource: NSObject, CMHeadphoneMotionManagerDelegate {
    private let manager = CMHeadphoneMotionManager()
    private let queue = OperationQueue()

    var onSample: ((MotionSample) -> Void)?
    var onStatus: ((MotionStatus) -> Void)?

    private(set) var lastSampleDate: Date?
    private var currentStatus: MotionStatus?

    override init() {
        super.init()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        manager.delegate = self
    }

    func start() {
        guard manager.isDeviceMotionAvailable else {
            notifyStatus(.unavailable)
            return
        }

        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            notifyStatus(.denied)
            return
        default:
            break
        }

        notifyStatus(.waitingForAirPods)

        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self = self else { return }
            if error != nil {
                if CMHeadphoneMotionManager.authorizationStatus() == .denied {
                    self.notifyStatus(.denied)
                }
                return
            }
            guard let motion = motion else { return }

            let side: BudSide
            switch motion.sensorLocation {
            case .headphoneLeft:
                side = .left
            case .headphoneRight:
                side = .right
            default:
                side = .unknown
            }

            let q = motion.attitude.quaternion
            let r = motion.rotationRate
            let u = motion.userAcceleration
            let g = motion.gravity

            let sample = MotionSample(
                t: motion.timestamp,
                quat: SIMD4<Double>(q.x, q.y, q.z, q.w),
                rot: SIMD3<Double>(r.x, r.y, r.z),
                acc: SIMD3<Double>(u.x, u.y, u.z),
                grav: SIMD3<Double>(g.x, g.y, g.z),
                side: side
            )

            DispatchQueue.main.async {
                self.lastSampleDate = Date()
                self.notifyStatus(.streaming(side))
                self.onSample?(sample)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        notifyStatus(.waitingForAirPods)
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        notifyStatus(.waitingForAirPods)
    }

    private func notifyStatus(_ status: MotionStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.currentStatus != status {
                self.currentStatus = status
                self.onStatus?(status)
            }
        }
    }
}
