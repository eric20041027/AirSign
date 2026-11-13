#if AIRSIGN_LAB
import AirSignCore
import Foundation

/// `AirSign --probe`: prints AirPods status, sample rate and output device once a second, then exits.
@MainActor
enum ProbeMode {
    static let seconds = 15
    private static var source: HeadphoneMotionSource?
    private static var count = 0, elapsed = 0

    static func run() {
        let source = HeadphoneMotionSource()
        count = 0
        elapsed = 0
        source.onSample = { _ in count += 1 }
        source.start()
        self.source = source
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            // This timer fires on the main run loop because run() is main-actor isolated.
            let finished = MainActor.assumeIsolated {
                elapsed += 1
                let device = AudioDeviceIdentity.currentOutput()
                let deviceText = device.map { "\($0.name) uid=\($0.uid) bluetooth=\($0.isBluetooth)" } ?? "none"
                print("t=\(elapsed)s status=\(source.status) hz=\(count) output=\(deviceText)")
                fflush(stdout)
                count = 0
                return elapsed >= seconds
            }
            if finished {
                timer.invalidate()
                exit(0)
            }
        }
    }
}
#endif
