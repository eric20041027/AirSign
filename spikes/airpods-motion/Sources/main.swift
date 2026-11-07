// Throwaway spike: read AirPods head motion on this Mac and stream it to a local browser page.
import Cocoa
import CoreMotion
import Network

let serverPort: NWEndpoint.Port = 8765
let pageURL = URL(string: "http://127.0.0.1:8765/")!

// MARK: - Server-Sent Events hub

final class EventHub {
    private let queue = DispatchQueue(label: "spike.hub")
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var lastStatus = "{}"

    var clientCount: Int { queue.sync { clients.count } }

    func add(_ connection: NWConnection) {
        queue.async {
            self.clients[ObjectIdentifier(connection)] = connection
            self.send(Self.frame(event: "status", json: self.lastStatus), to: connection)
        }
    }

    func remove(_ connection: NWConnection) {
        queue.async { self.clients.removeValue(forKey: ObjectIdentifier(connection)) }
    }

    func publishStatus(_ json: String) {
        queue.async {
            self.lastStatus = json
            self.broadcast(Self.frame(event: "status", json: json))
        }
    }

    func publishSample(_ json: String) {
        queue.async { self.broadcast(Self.frame(event: nil, json: json)) }
    }

    private static func frame(event: String?, json: String) -> Data {
        let prefix = event.map { "event: \($0)\n" } ?? ""
        return Data("\(prefix)data: \(json)\n\n".utf8)
    }

    private func broadcast(_ data: Data) {
        clients.values.forEach { send(data, to: $0) }
    }

    private func send(_ data: Data, to connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }
            self?.remove(connection)
            connection.cancel()
        })
    }
}

// MARK: - Minimal HTTP server: "/" serves the page, "/events" streams samples, "/save" stores an attempt

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// Returns nil until the buffer holds the whole header block and body.
    init?(_ buffer: Data) {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return nil }
        method = String(requestLine[0])
        path = String(requestLine[1].split(separator: "?").first ?? "/")
        self.headers = headers
        body = buffer.subdata(in: bodyStart..<(bodyStart + length))
    }
}

final class WebServer {
    private static let maxRequestBytes = 8 * 1024 * 1024
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    private let listener: NWListener
    private let hub: EventHub
    private let page: Data
    private let saveDirectory: URL

    init(hub: EventHub, page: Data, saveDirectory: URL) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: serverPort)
        listener = try NWListener(using: params)
        self.hub = hub
        self.page = page
        self.saveDirectory = saveDirectory
    }

    func start(onFailure: @escaping (String) -> Void) {
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { onFailure("port \(serverPort): \(error)") }
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak hub] state in
            switch state {
            case .failed, .cancelled: hub?.remove(connection)
            default: break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest(buffer) {
                self.route(request, connection)
            } else if isComplete || buffer.count > Self.maxRequestBytes {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func route(_ request: HTTPRequest, _ connection: NWConnection) {
        switch (request.method, request.path) {
        case ("GET", "/events"):
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n"
                + "Connection: keep-alive\r\n\r\n"
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
            hub.add(connection)
        case ("GET", "/"), ("GET", "/index.html"):
            respond(connection, status: "200 OK", type: "text/html; charset=utf-8", body: page)
        case ("POST", "/save"):
            save(request, connection)
        default:
            respond(connection, status: "404 Not Found", type: "text/plain", body: Data("not found".utf8))
        }
    }

    // The custom header forces a CORS preflight, which this server never answers, so other sites cannot write files.
    private func save(_ request: HTTPRequest, _ connection: NWConnection) {
        guard request.headers["x-spike"] == "1",
              (try? JSONSerialization.jsonObject(with: request.body)) != nil else {
            respondJSON(connection, status: "400 Bad Request", ["error": "expected a JSON body and X-Spike: 1"])
            return
        }
        let name = "attempt-\(Self.stamp.string(from: Date())).json"
        do {
            try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
            try request.body.write(to: saveDirectory.appendingPathComponent(name), options: .atomic)
            respondJSON(connection, status: "200 OK", ["saved": name])
        } catch {
            NSLog("AirPodsMotion: save failed: %@", error.localizedDescription)
            respondJSON(connection, status: "500 Internal Server Error", ["error": error.localizedDescription])
        }
    }

    private func respondJSON(_ connection: NWConnection, status: String, _ object: [String: String]) {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        respond(connection, status: status, type: "application/json", body: body)
    }

    private func respond(_ connection: NWConnection, status: String, type: String, body: Data) {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, contentContext: .defaultMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}

// MARK: - AirPods motion

final class MotionStreamer: NSObject, CMHeadphoneMotionManagerDelegate {
    private let manager = CMHeadphoneMotionManager()
    private let updates = OperationQueue()
    private let hub: EventHub
    private let lock = NSLock()
    private var samples = 0
    private var connected = false
    private var lastError: String?

    init(hub: EventHub) {
        self.hub = hub
        super.init()
        updates.maxConcurrentOperationCount = 1
    }

    var sampleCount: Int { locked { samples } }
    var connectionText: String { locked { connected } ? "connected" : "not connected" }
    var errorText: String? { locked { lastError } }

    func start() {
        manager.delegate = self
        guard manager.isDeviceMotionAvailable else {
            setError("this Mac reports headphone motion as unavailable")
            return
        }
        manager.startDeviceMotionUpdates(to: updates) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                self.setError(error.localizedDescription)
                return
            }
            guard let motion else { return }
            self.locked { self.samples += 1 }
            self.hub.publishSample(Self.json(for: motion))
        }
        publishStatus()
    }

    func publishStatus() {
        let (isConnected, error, count) = locked { (connected, lastError, samples) }
        let errorField = error.map { "\"\(Self.escape($0))\"" } ?? "null"
        hub.publishStatus("{\"available\":\(manager.isDeviceMotionAvailable),\"active\":\(manager.isDeviceMotionActive),"
            + "\"connected\":\(isConnected),\"auth\":\"\(Self.authText())\",\"samples\":\(count),\"error\":\(errorField)}")
    }

    static func authText() -> String {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        locked {
            connected = true
            lastError = nil
        }
        publishStatus()
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        locked { connected = false }
        publishStatus()
    }

    private func setError(_ message: String) {
        locked { lastError = message }
        NSLog("AirPodsMotion: %@", message)
        publishStatus()
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func json(for motion: CMDeviceMotion) -> String {
        let q = motion.attitude.quaternion
        let a = motion.attitude, r = motion.rotationRate, u = motion.userAcceleration, g = motion.gravity
        let numbers = String(
            format: "\"t\":%.4f,\"q\":[%.5f,%.5f,%.5f,%.5f],\"att\":[%.5f,%.5f,%.5f],"
                + "\"rot\":[%.4f,%.4f,%.4f],\"acc\":[%.4f,%.4f,%.4f],\"grav\":[%.4f,%.4f,%.4f]",
            motion.timestamp, q.x, q.y, q.z, q.w, a.pitch, a.roll, a.yaw,
            r.x, r.y, r.z, u.x, u.y, u.z, g.x, g.y, g.z)
        return "{\(numbers),\"loc\":\"\(location(of: motion))\"}"
    }

    private static func location(of motion: CMDeviceMotion) -> String {
        switch motion.sensorLocation {
        case .headphoneLeft: return "left"
        case .headphoneRight: return "right"
        default: return "default"
        }
    }
}

// MARK: - App shell: a small status window so the stream has a visible owner

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hub = EventHub()
    private lazy var motion = MotionStreamer(hub: hub)
    private var server: WebServer?
    private var window: NSWindow?
    private let label = NSTextField(wrappingLabelWithString: "Starting…")
    private var serverError: String?
    private var lastCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        startServer()
        motion.start()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        NSWorkspace.shared.open(pageURL)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func startServer() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html"),
              let page = try? Data(contentsOf: url) else {
            serverError = "index.html missing from app bundle"
            return
        }
        // build/AirPodsMotion.app -> spikes/airpods-motion/sessions
        let sessions = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("sessions")
        do {
            let server = try WebServer(hub: hub, page: page, saveDirectory: sessions)
            server.start { [weak self] message in DispatchQueue.main.async { self?.serverError = message } }
            self.server = server
        } catch {
            serverError = "could not open port \(serverPort): \(error)"
        }
    }

    // Runs once a second; samples/sec shows whether macOS keeps streaming while this app is in the background.
    private func tick() {
        let count = motion.sampleCount
        let rate = count - lastCount
        lastCount = count
        motion.publishStatus()
        var lines = [
            "AirPods: \(motion.connectionText)",
            "Motion access: \(MotionStreamer.authText())",
            "Samples/sec: \(rate)    total: \(count)",
            "Browser tabs connected: \(hub.clientCount)",
            "Page: \(pageURL.absoluteString)",
        ]
        if let serverError { lines.append("Server error: \(serverError)") }
        if let error = motion.errorText { lines.append("Motion error: \(error)") }
        label.stringValue = lines.joined(separator: "\n")
    }

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "AirPods Motion Spike"
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let button = NSButton(title: "Open in browser", target: self, action: #selector(openPage))
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        window.contentView = stack
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }

    @objc private func openPage() { NSWorkspace.shared.open(pageURL) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
