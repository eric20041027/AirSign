import Foundation

/// What can be asked of the app. While a file operation runs, only an open request (it waits) and quitting are accepted.
public enum AppAction: CaseIterable {
    case openRequest, quit
    case signatureTry, recoveryCodeTry, enrollmentStep, changeSignature, reset, forgetPairedMacs,
         setDemoMode, addSample, removeSamples, cancel, retryLaunch, labAction
}

public enum BusyPolicy {
    public static func allows(_ action: AppAction, whileBusy: Bool) -> Bool {
        !whileBusy || action == .openRequest || action == .quit
    }
}

/// Open requests in arrival order. Nothing is dropped; nothing is handed out while an operation runs.
public struct OpenQueue {
    public private(set) var isBusy = false
    private var waiting: [[URL]] = []
    public var waitingCount: Int { waiting.count }

    public init() {}

    /// Returns the request when it can be handled now; nil when it was put behind the running operation.
    public mutating func receive(_ urls: [URL]) -> [URL]? {
        guard !isBusy, waiting.isEmpty else {
            waiting.append(urls)
            return nil
        }
        return urls
    }

    public mutating func operationBegan() {
        isBusy = true
    }

    public mutating func operationEnded() {
        isBusy = false
    }

    /// The oldest waiting request, or nil while an operation runs or when nothing waits.
    public mutating func next() -> [URL]? {
        guard !isBusy, !waiting.isEmpty else { return nil }
        return waiting.removeFirst()
    }
}
