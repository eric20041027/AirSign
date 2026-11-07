import AirSignCore
import Foundation

public enum ProbeMode {
    public static func run() {
        let source = HeadphoneMotionSource()
        var sampleCount = 0
        var lastCount = 0
        var currentSide: BudSide = .unknown

        source.onSample = { sample in
            sampleCount += 1
            currentSide = sample.side
        }
        source.onStatus = { status in
            if case .streaming(let side) = status {
                currentSide = side
            }
        }
        source.start()

        for _ in 1...5 {
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
            let hz = sampleCount - lastCount
            lastCount = sampleCount

            let audioInfo = AudioDeviceIdentity.currentOutput()
            let uid = audioInfo?.uid ?? "none"
            let name = audioInfo?.name ?? "none"

            print("\(currentSide.rawValue), \(hz) Hz, \(uid), \(name)")
            fflush(stdout)
        }

        source.stop()
        exit(0)
    }
}
