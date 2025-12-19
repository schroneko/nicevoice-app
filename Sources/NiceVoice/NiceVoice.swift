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

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("✅ NiceVoice started")
    }
}

@Observable
final class AppState {
    var isRecording = false
    var currentTranscription = ""
    var isReady = false
    var statusMessage = "初期化中..."

    private var speechService: SpeechRecognitionService?
    private var fnKeyMonitor: FnKeyMonitor?
    private var floatingPanel: FloatingPanel?

    init() {
        setupServices()
    }

    private func setupServices() {
        speechService = SpeechRecognitionService { [weak self] text in
            DispatchQueue.main.async {
                self?.currentTranscription = text
            }
        }

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
        guard isReady, !isRecording else { return }
        isRecording = true
        currentTranscription = ""
        floatingPanel?.show()

        do {
            try speechService?.startRecording()
        } catch {
            print("Recording error: \(error)")
            isRecording = false
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        speechService?.stopRecording()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.currentTranscription.isEmpty else {
                self?.floatingPanel?.hide()
                return
            }
            self.copyToClipboard(self.currentTranscription)
            self.pasteFromClipboard()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.floatingPanel?.hide()
            }
        }
    }

    func cancelRecording() {
        speechService?.stopRecording()
        isRecording = false
        currentTranscription = ""
        floatingPanel?.hide()
        print("🚫 Recording cancelled")
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("📋 Copied to clipboard: \(text)")
    }

    private func pasteFromClipboard() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let source = CGEventSource(stateID: .privateState)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
                print("❌ Failed to create CGEvent")
                return
            }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand

            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            usleep(50000)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)

            print("📝 Paste command sent via cgAnnotatedSessionEventTap")
        }
    }
}

final class SpeechRecognitionService {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let onTranscription: (String) -> Void

    init(onTranscription: @escaping (String) -> Void) {
        self.onTranscription = onTranscription
    }

    func startRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

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

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result {
                self?.onTranscription(result.bestTranscription.formattedString)
            }

            if error != nil || (result?.isFinal ?? false) {
                self?.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self?.recognitionRequest = nil
                self?.recognitionTask = nil
            }
        }
    }

    func stopRecording() {
        audioEngine.stop()
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
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let fnPressed = event.modifierFlags.contains(.function)

            if fnPressed && !self.isFnPressed {
                self.isFnPressed = true
                DispatchQueue.main.async { self.onKeyDown() }
            } else if !fnPressed && self.isFnPressed {
                self.isFnPressed = false
                DispatchQueue.main.async { self.onKeyUp() }
            }
        }

        if monitor == nil {
            print("⚠️ アクセシビリティ権限が必要です")
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
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

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: FloatingPanelView(appState: appState))
        panel.contentView = hostingView

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = (screenFrame.width - 400) / 2 + screenFrame.origin.x
            let y = screenFrame.origin.y + 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.window = panel
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
        VStack(spacing: 8) {
            HStack {
                if appState.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 12, height: 12)
                    Text("録音中...")
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "text.bubble")
                    Text("文字起こし")
                }
                Spacer()
            }
            .font(.caption)

            Text(appState.currentTranscription.isEmpty ? "fn キーを押して話してください" : appState.currentTranscription)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
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

            if !appState.currentTranscription.isEmpty {
                Text(appState.currentTranscription)
                    .font(.caption)
                    .lineLimit(3)
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
        .frame(width: 250)
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
