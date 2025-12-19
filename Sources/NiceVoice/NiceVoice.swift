import SwiftUI
import AVFoundation
import Speech
import AppKit
import Carbon.HIToolbox

@main
struct NiceVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Nice Voice", systemImage: appDelegate.appState.isRecording ? "mic.fill" : "mic") {
            MenuBarView(appState: appDelegate.appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"
    print(logMessage, terminator: "")

    let logPath = "/tmp/nicevoice-debug.log"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(logMessage.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: logMessage.data(using: .utf8))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("✅ NiceVoice started")
    }
}

struct TranscriptionRecord: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
}

@Observable
final class AppState {
    var isRecording = false
    var currentTranscription = ""
    var isReady = false
    var statusMessage = "初期化中..."
    var history: [TranscriptionRecord] = []

    private var speechService: SpeechRecognitionService?
    private var fnKeyMonitor: FnKeyMonitor?
    private var floatingPanel: FloatingPanel?
    private var waitingForFinalResult = false
    private var finalResultTimer: DispatchWorkItem?

    init() {
        setupServices()
    }

    private func setupServices() {
        speechService = SpeechRecognitionService(
            onTranscription: { [weak self] text, isFinal in
                DispatchQueue.main.async {
                    self?.currentTranscription = text
                    if isFinal {
                        self?.handleFinalResult(text)
                    }
                }
            },
            onRealtimeInput: { [weak self] oldText, newText in
                self?.handleRealtimeInput(oldText: oldText, newText: newText)
            }
        )

        fnKeyMonitor = FnKeyMonitor(
            onKeyDown: { [weak self] in self?.startRecording() },
            onKeyUp: { [weak self] in self?.stopRecording() }
        )

        floatingPanel = FloatingPanel(appState: self)

        Task {
            await requestPermissions()
        }
    }

    private func requestPermissions() async {
        statusMessage = "権限を確認中..."

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            await MainActor.run {
                statusMessage = "音声認識の権限が必要です"
            }
            return
        }

        let micStatus = await AVCaptureDevice.requestAccess(for: .audio)
        guard micStatus else {
            await MainActor.run {
                statusMessage = "マイクの権限が必要です"
            }
            return
        }

        await MainActor.run {
            isReady = true
            statusMessage = "準備完了 - fn キーを押して録音"
        }
    }

    func startRecording() {
        debugLog("🔍 [DEBUG] startRecording called - isReady: \(isReady), isRecording: \(isRecording)")
        guard isReady, !isRecording else {
            debugLog("🔍 [DEBUG] startRecording guard failed")
            return
        }
        isRecording = true
        currentTranscription = ""
        debugLog("🎙️ Recording started")

        floatingPanel?.show()

        do {
            try speechService?.startRecording()
            debugLog("🔍 [DEBUG] speechService.startRecording() succeeded")
        } catch {
            debugLog("❌ Recording error: \(error)")
            isRecording = false
            floatingPanel?.hide()
        }
    }

    func stopRecording() {
        debugLog("🔍 [DEBUG] stopRecording called - isRecording: \(isRecording)")
        guard isRecording else {
            debugLog("🔍 [DEBUG] stopRecording guard failed - not recording")
            return
        }
        isRecording = false
        speechService?.stopRecording()
        debugLog("🎙️ Recording stopped, waiting for final result...")

        waitingForFinalResult = true

        finalResultTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            guard let self, self.waitingForFinalResult else { return }
            debugLog("⏱️ Timeout - using current transcription: '\(self.currentTranscription)'")
            self.performPaste(self.currentTranscription)
        }
        finalResultTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timer)
    }

    private func handleFinalResult(_ text: String) {
        guard waitingForFinalResult else { return }
        debugLog("✅ Final result received: '\(text)'")
        finalResultTimer?.cancel()
        performPaste(text)
    }

    private func performPaste(_ text: String) {
        waitingForFinalResult = false
        floatingPanel?.hide()
        guard !text.isEmpty else {
            debugLog("⚠️ No text to paste - text is empty")
            return
        }
        debugLog("🔍 [DEBUG] About to copy and paste: '\(text)'")
        addToHistory(text)
        copyToClipboard(text)
        pasteFromClipboard()
    }

    func cancelRecording() {
        speechService?.stopRecording()
        isRecording = false
        currentTranscription = ""
        floatingPanel?.hide()
        debugLog("🚫 Recording cancelled")
    }

    private func addToHistory(_ text: String) {
        let record = TranscriptionRecord(text: text, timestamp: Date())
        history.insert(record, at: 0)
        if history.count > 20 {
            history.removeLast()
        }
        debugLog("📚 Added to history: '\(text)'")
    }

    func copyHistoryItem(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        debugLog("📋 Copied from history: '\(text)'")
    }

    func clearHistory() {
        history.removeAll()
        debugLog("🗑️ History cleared")
    }

    private func copyToClipboard(_ text: String) {
        debugLog("🔍 [DEBUG] copyToClipboard called with: '\(text)'")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        debugLog("📋 Copied to clipboard: '\(text)', success: \(success)")

        let verify = pasteboard.string(forType: .string)
        debugLog("🔍 [DEBUG] Clipboard verification: '\(verify ?? "nil")'")
    }

    private func pasteFromClipboard() {
        debugLog("🔍 [DEBUG] pasteFromClipboard called - trying AppleScript")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let script = """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
            debugLog("🔍 [DEBUG] AppleScript: \(script)")

            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                debugLog("🔍 [DEBUG] NSAppleScript created")
                let result = appleScript.executeAndReturnError(&error)
                if let error = error {
                    debugLog("❌ AppleScript error: \(error)")
                } else {
                    debugLog("✅ AppleScript executed successfully, result: \(result)")
                }
            } else {
                debugLog("❌ Failed to create NSAppleScript")
            }
        }
    }

    private func handleRealtimeInput(oldText: String, newText: String) {
    }

    private func deleteCharacters(count: Int) {
        let source = CGEventSource(stateID: .privateState)

        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: false) else {
                continue
            }

            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            usleep(10000)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
            usleep(10000)
        }
    }

    private func typeTextViaPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0.0

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return
        }

        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand

        keyDown.post(tap: .cghidEventTap)
        usleep(50000)
        keyUp.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
}

final class SpeechRecognitionService {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let onTranscription: (String, Bool) -> Void
    private let onRealtimeInput: (String, String) -> Void
    private var lastTranscription = ""

    init(onTranscription: @escaping (String, Bool) -> Void, onRealtimeInput: @escaping (String, String) -> Void) {
        self.onTranscription = onTranscription
        self.onRealtimeInput = onRealtimeInput
    }

    func startRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        lastTranscription = ""

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw NSError(domain: "SpeechService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create request"])
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        debugLog("🔍 [DEBUG] Starting recognition task")
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let error {
                debugLog("🔍 [DEBUG] Recognition error: \(error)")
            }
            if let result {
                let newText = result.bestTranscription.formattedString
                let oldText = self?.lastTranscription ?? ""
                debugLog("🔍 [DEBUG] Recognition result: '\(newText)', isFinal: \(result.isFinal)")
                self?.lastTranscription = newText
                self?.onTranscription(newText, result.isFinal)
                self?.onRealtimeInput(oldText, newText)
            }
        }
        debugLog("🔍 [DEBUG] Recognition task created: \(recognitionTask != nil)")
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }
}

final class FnKeyMonitor {
    private var monitor: Any?
    private var isFnPressed = false
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void

    init(onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        startMonitoring()
    }

    private func startMonitoring() {
        debugLog("🔍 [DEBUG] FnKeyMonitor startMonitoring called")
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let fnPressed = event.modifierFlags.contains(.function)

            if fnPressed && !self.isFnPressed {
                debugLog("🔍 [DEBUG] fn key DOWN detected")
                self.isFnPressed = true
                DispatchQueue.main.async {
                    debugLog("🔍 [DEBUG] Calling onKeyDown callback")
                    self.onKeyDown()
                }
            } else if !fnPressed && self.isFnPressed {
                debugLog("🔍 [DEBUG] fn key UP detected")
                self.isFnPressed = false
                DispatchQueue.main.async {
                    debugLog("🔍 [DEBUG] Calling onKeyUp callback")
                    self.onKeyUp()
                }
            }
        }

        if monitor == nil {
            debugLog("⚠️ アクセシビリティ権限が必要です - monitor is nil")
        } else {
            debugLog("✅ FnKeyMonitor started successfully")
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FloatingPanel {
    private var window: NSPanel?
    private weak var appState: AppState?
    private var escMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        setupWindow()
        setupEscapeMonitor()
    }

    private func setupWindow() {
        guard let appState else { return }

        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true

        let hostingView = NSHostingView(rootView: FloatingPanelView(appState: appState))
        panel.contentView = hostingView

        self.window = panel
    }

    private func positionNearCursor() {
        guard let window, let screen = NSScreen.main else { return }

        var position: NSPoint?

        if let caretPos = getCaretPosition() {
            position = caretPos
        } else if let focusedPos = getFocusedElementPosition() {
            position = focusedPos
        } else {
            let mouseLocation = NSEvent.mouseLocation
            position = mouseLocation
        }

        if let pos = position {
            let panelWidth: CGFloat = 400
            let panelHeight: CGFloat = 100
            var x = pos.x
            var y = pos.y - panelHeight - 10

            let screenFrame = screen.frame
            x = max(screenFrame.minX + 10, min(x, screenFrame.maxX - panelWidth - 10))
            y = max(screenFrame.minY + 10, min(y, screenFrame.maxY - panelHeight - 10))

            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func getCaretPosition() -> NSPoint? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil
        }

        let element = focusedElement as! AXUIElement

        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success else {
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRangeValue!, &boundsValue) == .success else {
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds) else {
            return nil
        }

        guard let screen = NSScreen.main else { return nil }
        let flippedY = screen.frame.height - bounds.origin.y
        return NSPoint(x: bounds.origin.x, y: flippedY)
    }

    private func getFocusedElementPosition() -> NSPoint? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil
        }

        let element = focusedElement as! AXUIElement

        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success else {
            return nil
        }

        var position = CGPoint.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else {
            return nil
        }

        guard let screen = NSScreen.main else { return nil }
        let flippedY = screen.frame.height - position.y
        return NSPoint(x: position.x, y: flippedY)
    }

    private func setupEscapeMonitor() {
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    self?.appState?.cancelRecording()
                }
            }
        }
    }

    func show() {
        positionNearCursor()
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    deinit {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
        }
    }
}

struct FloatingPanelView: View {
    var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("🎤")
                .font(.title2)
            if appState.currentTranscription.isEmpty {
                Text("fn キーを押している間、文字起こしされます。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text(appState.currentTranscription)
                    .font(.body)
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(width: 380)
    }
}

struct MenuBarView: View {
    var appState: AppState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: appState.isRecording ? "mic.fill" : "mic")
                    .foregroundStyle(appState.isRecording ? .red : .primary)
                Text("Nice Voice")
                    .font(.headline)
            }

            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            if !appState.history.isEmpty {
                HStack {
                    Text("履歴")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("クリア") {
                        appState.clearHistory()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(appState.history) { record in
                            HistoryItemView(record: record, appState: appState)
                        }
                    }
                }
                .frame(maxHeight: 200)

                Divider()
            }

            SettingsLink {
                Text("設定...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 300)
    }
}

struct HistoryItemView: View {
    let record: TranscriptionRecord
    var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.text)
                    .font(.caption)
                    .lineLimit(2)
                Text(record.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.copyHistoryItem(record.text)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Nice Voice 設定")
                .font(.title)
            Text("fn キーを押している間、音声を録音します")
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}
