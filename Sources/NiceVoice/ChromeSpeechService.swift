import Foundation
import Network
import AppKit
import CommonCrypto

final class ChromeSpeechService {
    private static let wsPort: UInt16 = 9473
    private static let httpPort: UInt16 = 9474

    private static let supportedBrowsers: [(path: String, bundleId: String)] = [
        ("/Applications/Google Chrome.app", "com.google.Chrome"),
        ("/Applications/Microsoft Edge.app", "com.microsoft.edgemac"),
        ("/Applications/Brave Browser.app", "com.brave.Browser"),
        ("/Applications/Arc.app", "company.thebrowser.Browser"),
        ("/Applications/Vivaldi.app", "com.vivaldi.Vivaldi"),
        ("/Applications/Opera.app", "com.operasoftware.Opera"),
        ("/Applications/Chromium.app", "org.chromium.Chromium"),
    ]

    private var wsListener: NWListener?
    private var httpListener: NWListener?
    private var connection: NWConnection?
    private var isConnected = false
    private var browserPath: String?
    private var htmlContent: String = ""
    private var connectionTimeoutTimer: DispatchWorkItem?
    private static let connectionTimeout: TimeInterval = 5.0

    private let onTranscription: (String, Bool) -> Void
    private let onError: (String) -> Void
    private let onStatusChange: ((String) -> Void)?

    static func detectInstalledBrowser() -> (path: String, bundleId: String)? {
        supportedBrowsers.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func detectBrowser() -> String? {
        detectInstalledBrowser()?.path
    }

    static func detectRunningBrowser() -> (path: String, bundleId: String)? {
        let runningApps = NSWorkspace.shared.runningApplications
        return supportedBrowsers.first { browser in
            FileManager.default.fileExists(atPath: browser.path) &&
            runningApps.contains { $0.bundleIdentifier == browser.bundleId }
        }
    }

    static var isAvailable: Bool {
        detectRunningBrowser() != nil
    }

    init(
        onTranscription: @escaping (String, Bool) -> Void,
        onError: @escaping (String) -> Void,
        onStatusChange: ((String) -> Void)? = nil
    ) {
        self.onTranscription = onTranscription
        self.onError = onError
        self.onStatusChange = onStatusChange
        loadHtmlContent()
    }

    private func loadHtmlContent() {
        let bundlePath = Bundle.main.resourceURL?
            .appendingPathComponent("speech-recognition.html").path
        let fallbackPath = getResourcePath()

        let htmlPath: String
        if let bundlePath, FileManager.default.fileExists(atPath: bundlePath) {
            htmlPath = bundlePath
        } else {
            htmlPath = fallbackPath
        }

        if let content = try? String(contentsOfFile: htmlPath, encoding: .utf8) {
            htmlContent = content
            debugLog("✅ HTML content loaded from: \(htmlPath)")
        } else {
            debugLog("❌ Failed to load HTML from: \(htmlPath)")
        }
    }

    func start() {
        guard let runningBrowser = Self.detectRunningBrowser() else {
            if Self.detectInstalledBrowser() != nil {
                onError("ブラウザが起動していません: Chrome を起動してください")
            } else {
                onError("非対応: Chromium 系ブラウザが見つかりません")
            }
            return
        }

        browserPath = runningBrowser.path
        onStatusChange?("ブラウザ接続待ち...")
        startConnectionTimeout()
        startHttpServer()
        startWebSocketServer()
    }

    private func startConnectionTimeout() {
        connectionTimeoutTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            guard let self, !self.isConnected else { return }
            debugLog("❌ Browser connection timeout")
            self.onError("ブラウザ接続タイムアウト: Chrome を起動してください")
            self.stop()
        }
        connectionTimeoutTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectionTimeout, execute: timer)
    }

    private func cancelConnectionTimeout() {
        connectionTimeoutTimer?.cancel()
        connectionTimeoutTimer = nil
    }

    func stop() {
        stopWebSocketServer()
        stopHttpServer()
    }

    private func startHttpServer() {
        guard let port = NWEndpoint.Port(rawValue: Self.httpPort) else {
            debugLog("❌ Invalid HTTP port: \(Self.httpPort)")
            return
        }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
            httpListener = try NWListener(using: parameters, on: port)

            httpListener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    debugLog("🌐 HTTP server ready on localhost:\(Self.httpPort)")
                case .failed(let error):
                    debugLog("❌ HTTP server failed: \(error)")
                default:
                    break
                }
            }

            httpListener?.newConnectionHandler = { [weak self] connection in
                self?.handleHttpConnection(connection)
            }

            httpListener?.start(queue: .main)
        } catch {
            debugLog("❌ Failed to create HTTP server: \(error)")
        }
    }

    private func stopHttpServer() {
        httpListener?.cancel()
        httpListener = nil
    }

    private func handleHttpConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
                    guard let self, let data, String(data: data, encoding: .utf8)?.contains("GET") == true else {
                        connection.cancel()
                        return
                    }
                    self.sendHttpResponse(connection)
                }
            }
        }
        connection.start(queue: .main)
    }

    private func sendHttpResponse(_ connection: NWConnection) {
        let body = htmlContent.data(using: .utf8) ?? Data()
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        guard var responseData = response.data(using: .utf8) else {
            connection.cancel()
            return
        }
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func startWebSocketServer() {
        guard let port = NWEndpoint.Port(rawValue: Self.wsPort) else {
            debugLog("❌ Invalid WebSocket port: \(Self.wsPort)")
            onError("WebSocket ポートが無効")
            return
        }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
            wsListener = try NWListener(using: parameters, on: port)

            wsListener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    debugLog("🌐 WebSocket server ready on localhost:\(Self.wsPort)")
                    self?.openBrowser()
                case .failed(let error):
                    debugLog("❌ WebSocket server failed: \(error)")
                    self?.onError("WebSocket サーバー起動失敗")
                default:
                    break
                }
            }

            wsListener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            wsListener?.start(queue: .main)
        } catch {
            debugLog("❌ Failed to create WebSocket server: \(error)")
            onError("WebSocket サーバー作成失敗")
        }
    }

    private func stopWebSocketServer() {
        sendCommand("stop")
        connection?.cancel()
        connection = nil
        wsListener?.cancel()
        wsListener = nil
        isConnected = false
    }

    private func handleNewConnection(_ newConnection: NWConnection) {
        connection?.cancel()
        connection = newConnection

        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                debugLog("🔗 Browser connected")
                self?.cancelConnectionTimeout()
                self?.isConnected = true
                self?.performWebSocketHandshake()
            case .failed(let error):
                debugLog("❌ Connection failed: \(error)")
                self?.isConnected = false
            case .cancelled:
                debugLog("🔌 Connection cancelled")
                self?.isConnected = false
            default:
                break
            }
        }

        connection?.start(queue: .main)
    }

    private func performWebSocketHandshake() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else { return }

            if let request = String(data: data, encoding: .utf8), request.contains("Upgrade: websocket") {
                self.completeHandshake(request: request)
            }
        }
    }

    private func completeHandshake(request: String) {
        guard let keyLine = request.split(separator: "\r\n").first(where: { $0.hasPrefix("Sec-WebSocket-Key:") }) else {
            debugLog("❌ No WebSocket key found")
            return
        }

        let key = keyLine.replacingOccurrences(of: "Sec-WebSocket-Key: ", with: "").trimmingCharacters(in: .whitespaces)
        let acceptKey = generateAcceptKey(key)

        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r
        \r

        """

        connection?.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if error == nil {
                debugLog("✅ WebSocket handshake complete")
                self?.receiveMessages()
            }
        })
    }

    private func generateAcceptKey(_ key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + magic
        let hash = combined.data(using: .utf8)!.sha1()
        return hash.base64EncodedString()
    }

    private func receiveMessages() {
        connection?.receive(minimumIncompleteLength: 2, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                if let message = self.decodeWebSocketFrame(data) {
                    self.handleMessage(message)
                }
            }

            if !isComplete && error == nil {
                self.receiveMessages()
            }
        }
    }

    private func decodeWebSocketFrame(_ data: Data) -> String? {
        guard data.count >= 2 else { return nil }

        let secondByte = data[1]
        let isMasked = (secondByte & 0x80) != 0
        var payloadLength = Int(secondByte & 0x7F)
        var offset = 2

        if payloadLength == 126 {
            guard data.count >= 4 else { return nil }
            payloadLength = Int(data[2]) << 8 | Int(data[3])
            offset = 4
        } else if payloadLength == 127 {
            guard data.count >= 10 else { return nil }
            payloadLength = 0
            for i in 0..<8 {
                payloadLength = payloadLength << 8 | Int(data[2 + i])
            }
            offset = 10
        }

        var maskKey: [UInt8] = []
        if isMasked {
            guard data.count >= offset + 4 else { return nil }
            maskKey = Array(data[offset..<(offset + 4)])
            offset += 4
        }

        guard data.count >= offset + payloadLength else { return nil }

        var payload = Array(data[offset..<(offset + payloadLength)])
        if isMasked {
            for i in 0..<payload.count {
                payload[i] ^= maskKey[i % 4]
            }
        }

        return String(bytes: payload, encoding: .utf8)
    }

    private func handleMessage(_ message: String) {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "ready":
            debugLog("🎤 Browser ready for speech recognition")
        case "started":
            debugLog("🎙️ Chrome speech recognition started")
        case "result":
            if let text = json["text"] as? String, let isFinal = json["isFinal"] as? Bool {
                debugLog("📝 Chrome result: \(text.count) chars (final: \(isFinal))")
                DispatchQueue.main.async {
                    self.onTranscription(text, isFinal)
                }
            }
        case "error":
            if let errorMsg = json["message"] as? String {
                debugLog("❌ Chrome speech error: \(errorMsg)")
                DispatchQueue.main.async {
                    self.onError(errorMsg)
                }
            }
        default:
            break
        }
    }

    func startRecording() {
        sendCommand("start")
    }

    func stopRecording() {
        sendCommand("stop")
    }

    private func sendCommand(_ command: String) {
        guard isConnected else {
            debugLog("⚠️ Cannot send command: not connected")
            return
        }

        let json = "{\"type\":\"\(command)\"}"
        if let frame = encodeWebSocketFrame(json) {
            connection?.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    debugLog("❌ Send error: \(error)")
                }
            })
        }
    }

    private func encodeWebSocketFrame(_ text: String) -> Data? {
        guard let payload = text.data(using: .utf8) else { return nil }

        var frame = Data()
        frame.append(0x81)

        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count < 65536 {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(127)
            for i in (0..<8).reversed() {
                frame.append(UInt8((payload.count >> (i * 8)) & 0xFF))
            }
        }

        frame.append(payload)
        return frame
    }

    private func openBrowser() {
        guard let browserPath else { return }

        let url = URL(string: "http://localhost:\(Self.httpPort)")!

        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--app=\(url.absoluteString)"]
        config.createsNewApplicationInstance = false

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: browserPath),
            configuration: config
        ) { _, error in
            if let error {
                debugLog("❌ Failed to open browser: \(error)")
            } else {
                debugLog("🌐 Opened browser: \(browserPath) with localhost URL")
            }
        }
    }

    private func getResourcePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("NiceVoice/speech-recognition.html").path
    }
}

extension Data {
    func sha1() -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        _ = withUnsafeBytes { bytes in
            CC_SHA1(bytes.baseAddress, CC_LONG(count), &digest)
        }
        return Data(digest)
    }
}
