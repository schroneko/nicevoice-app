import SwiftUI
import AVFoundation
import Speech
import AppKit
import Carbon.HIToolbox
import ApplicationServices
import UniformTypeIdentifiers

extension Notification.Name {
    static let recordingStateChanged = Notification.Name("recordingStateChanged")
}

@main
struct NiceVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Nice Voice", id: "main") {
            MainWindowView(appState: appDelegate.appState)
        }
        .defaultSize(width: 800, height: 600)
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
    private var statusItem: NSStatusItem?
    private var recordingObservation: NSKeyValueObservation?

    @AppStorage("showInMenuBar") var showInMenuBar = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("✅ NiceVoice started")
        checkAccessibilityPermission()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarSettingChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(recordingStateChanged),
            name: .recordingStateChanged,
            object: nil
        )
    }

    @objc private func recordingStateChanged() {
        updateStatusItemIcon()
    }

    private func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        debugLog("🔐 Accessibility permission: \(trusted)")

        if !trusted {
            debugLog("⚠️ Accessibility not granted - opening System Settings")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    private func setupStatusItem() {
        guard showInMenuBar else {
            statusItem = nil
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Nice Voice")
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        updateStatusItemIcon()
    }

    func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let iconName = appState.isRecording ? "mic.fill" : "mic"
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Nice Voice")
        button.contentTintColor = appState.isRecording ? .systemRed : nil
    }

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            openMainWindow()
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Nice Voice" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            if let url = URL(string: "nicevoice://main") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: appState.statusMessage, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Nice Voice を開く", action: #selector(openMainWindowAction), keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = .command
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openMainWindowAction() {
        openMainWindow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func menuBarSettingChanged() {
        let newValue = UserDefaults.standard.bool(forKey: "showInMenuBar")
        if newValue && statusItem == nil {
            setupStatusItem()
        } else if !newValue && statusItem != nil {
            NSStatusBar.system.removeStatusItem(statusItem!)
            statusItem = nil
        }
    }
}

struct TranscriptionRecord: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date

    init(text: String, timestamp: Date) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
    }

    init(id: UUID, text: String, timestamp: Date) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
}

struct UsageStats: Codable {
    var totalConversions: Int = 0
    var totalCharacters: Int = 0
    var totalTokensUsed: Int = 0
    var todayConversions: Int = 0
    var todayCharacters: Int = 0
    var lastResetDate: Date = Date()

    mutating func resetTodayIfNeeded() {
        let calendar = Calendar.current
        if !calendar.isDateInToday(lastResetDate) {
            todayConversions = 0
            todayCharacters = 0
            lastResetDate = Date()
        }
    }

    mutating func recordConversion(characters: Int, tokens: Int) {
        resetTodayIfNeeded()
        totalConversions += 1
        totalCharacters += characters
        totalTokensUsed += tokens
        todayConversions += 1
        todayCharacters += characters
    }
}

struct DictionaryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var reading: String
    var writing: String
    var isEnabled: Bool = true

    init(id: UUID = UUID(), reading: String, writing: String, isEnabled: Bool = true) {
        self.id = id
        self.reading = reading
        self.writing = writing
        self.isEnabled = isEnabled
    }
}

struct FillerSettings: Codable {
    var removeFillers: Bool = true
    var enabledPresets: Set<String> = [
        "えー", "えぇ", "ええ",
        "あー", "あぁ", "ああ",
        "うーん", "うん",
        "まあ", "まぁ",
        "なんか",
        "ちょっと",
        "やっぱり", "やっぱ",
        "ですね", "ですよね"
    ]
    var customFillers: [String] = []

    var addPunctuation: Bool = true
    var removeRepetition: Bool = true

    var allEnabledFillers: [String] {
        var fillers = Array(enabledPresets)
        fillers.append(contentsOf: customFillers)
        return fillers.sorted { $0.count > $1.count }
    }
}

struct BenchmarkSample: Identifiable, Codable {
    let id: UUID
    let name: String
    let audioFileName: String
    let expectedText: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, audioFileName: String, expectedText: String = "", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.audioFileName = audioFileName
        self.expectedText = expectedText
        self.createdAt = createdAt
    }
}

struct BenchmarkResult: Identifiable {
    let id = UUID()
    let sample: BenchmarkSample
    let rawText: String
    let formattedText: String
    let duration: TimeInterval
    let success: Bool
}

@Observable
final class AppState {
    var isRecording = false
    var currentTranscription = ""
    var isReady = false
    var statusMessage = "初期化中..."
    var history: [TranscriptionRecord] = []
    var isConverting = false

    @ObservationIgnored
    @AppStorage("useGemini") var useGemini = true
    @ObservationIgnored
    @AppStorage("geminiApiKey") var geminiApiKey = ""

    @ObservationIgnored
    var usageStats: UsageStats = UsageStats()
    @ObservationIgnored
    var dictionaryEntries: [DictionaryEntry] = []
    @ObservationIgnored
    var fillerSettings: FillerSettings = FillerSettings()

    private var speechService: SpeechRecognitionService?
    private var fnKeyMonitor: FnKeyMonitor?
    private var floatingPanel: FloatingPanel?
    private var waitingForFinalResult = false
    private var finalResultTimer: DispatchWorkItem?
    private var sfSpeechResult = ""

    private enum UserDefaultsKey {
        static let usageStats = "usageStats"
        static let dictionary = "dictionaryEntries"
        static let fillerSettings = "fillerSettings"
        static let history = "transcriptionHistory"
    }

    init() {
        loadUsageStats()
        loadDictionary()
        loadFillerSettings()
        loadHistory()
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
        NotificationCenter.default.post(name: .recordingStateChanged, object: nil)

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
        debugLog("🎙️ Recording stopped")
        NotificationCenter.default.post(name: .recordingStateChanged, object: nil)

        sfSpeechResult = currentTranscription
        let fallbackResult = addLocalPunctuation(sfSpeechResult)
        debugLog("📝 SFSpeech result: '\(fallbackResult)'")

        if fallbackResult.isEmpty {
            debugLog("⚠️ No speech detected, skipping")
            floatingPanel?.hide()
            speechService?.clearAudioBuffers()
            return
        }

        if useGemini && !geminiApiKey.isEmpty {
            isConverting = true
            debugLog("🔄 Starting Gemini processing...")
            Task {
                do {
                    let geminiResult = try await processWithGemini()
                    await MainActor.run {
                        debugLog("✅ Gemini result: '\(geminiResult)'")
                        isConverting = false
                        floatingPanel?.hide()
                        addToHistory(geminiResult)
                        performPaste(geminiResult)
                        speechService?.clearAudioBuffers()
                    }
                } catch {
                    debugLog("❌ Gemini error: \(error), using fallback")
                    await MainActor.run {
                        isConverting = false
                        floatingPanel?.hide()
                        addToHistory(fallbackResult)
                        performPaste(fallbackResult)
                        speechService?.clearAudioBuffers()
                    }
                }
            }
        } else {
            floatingPanel?.hide()
            addToHistory(fallbackResult)
            performPaste(fallbackResult)
            speechService?.clearAudioBuffers()
        }
    }

    private func processWithGemini() async throws -> String {
        guard let audioData = speechService?.getRecordedAudioData(), !audioData.isEmpty else {
            throw GeminiError.audioDataEmpty
        }

        let geminiService = GeminiService(
            apiKey: geminiApiKey,
            dictionaryEntries: dictionaryEntries,
            fillerSettings: fillerSettings
        )
        let result = try await geminiService.transcribe(audioData: audioData)

        let estimatedTokens = audioData.count / 32
        await MainActor.run {
            recordConversion(characters: result.count, tokens: estimatedTokens)
        }

        return result
    }

    private func handleFinalResult(_ text: String) {
        guard waitingForFinalResult else { return }
        debugLog("✅ Final result received: '\(text)'")
        finalResultTimer?.cancel()
        performPaste(text)
    }

    private func addLocalPunctuation(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        if fillerSettings.removeFillers {
            let fillers = fillerSettings.allEnabledFillers
            for filler in fillers {
                result = result.replacingOccurrences(of: filler, with: "")
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            result = result.replacingOccurrences(of: "  ", with: " ")
            guard !result.isEmpty else { return result }
        }

        let greetings = ["こんにちは", "こんばんは", "おはよう", "おはようございます", "お疲れ様です", "お疲れさまです"]
        for greeting in greetings {
            if result.hasPrefix(greeting) && result.count > greeting.count {
                let afterGreeting = result.dropFirst(greeting.count)
                if let first = afterGreeting.first, first != "。" && first != "、" {
                    result = greeting + "。" + String(afterGreeting)
                }
            }
        }

        let questionPatterns = [
            "ですか", "ますか", "でしょうか", "かな", "かしら",
            "だろうか", "のか", "なの", "何", "なに",
            "どう", "どこ", "いつ", "誰", "なぜ",
            "どれ", "どちら", "いくつ", "いくら"
        ]

        let isQuestion = questionPatterns.contains { pattern in
            result.hasSuffix(pattern)
        }

        if isQuestion {
            if !result.hasSuffix("？") && !result.hasSuffix("?") {
                result += "？"
            }
        } else {
            if !result.hasSuffix("。") && !result.hasSuffix("？") && !result.hasSuffix("！") {
                result += "。"
            }
        }

        return result
    }

    private func performPaste(_ text: String) {
        waitingForFinalResult = false
        floatingPanel?.hide()
        guard !text.isEmpty else {
            debugLog("⚠️ No text to paste - text is empty")
            return
        }
        debugLog("🔍 [DEBUG] About to copy and paste: '\(text)'")
        pasteWithClipboardRestore(text)
    }

    private func pasteWithClipboardRestore(_ text: String) {
        let pasteboard = NSPasteboard.general

        let previousContents = pasteboard.string(forType: .string)
        debugLog("📋 Saving previous clipboard: '\(previousContents ?? "nil")'")

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        debugLog("📋 Set clipboard to: '\(text)'")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.simulatePaste {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let previous = previousContents {
                        pasteboard.clearContents()
                        pasteboard.setString(previous, forType: .string)
                        debugLog("📋 Restored clipboard to: '\(previous)'")
                    } else {
                        debugLog("📋 No previous clipboard to restore")
                    }
                }
            }
        }
    }

    private func simulatePaste(completion: @escaping () -> Void) {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if let error = error {
                debugLog("❌ AppleScript error: \(error)")
            } else {
                debugLog("✅ Paste executed successfully: \(result)")
            }
        }
        completion()
    }

    func cancelRecording() {
        speechService?.stopRecording()
        isRecording = false
        currentTranscription = ""
        floatingPanel?.hide()
        debugLog("🚫 Recording cancelled")
    }

    @discardableResult
    private func addToHistory(_ text: String) -> UUID {
        let record = TranscriptionRecord(text: text, timestamp: Date())
        history.insert(record, at: 0)
        if history.count > 20 {
            history.removeLast()
        }
        saveHistory()
        debugLog("📚 Added to history: '\(text)' (id: \(record.id))")
        return record.id
    }

    func copyHistoryItem(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        debugLog("📋 Copied from history: '\(text)'")
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
        debugLog("🗑️ History cleared")
    }

    func removeHistoryItem(_ record: TranscriptionRecord) {
        history.removeAll { $0.id == record.id }
        saveHistory()
        debugLog("🗑️ Removed from history: '\(record.text)'")
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

    private func saveUsageStats() {
        if let data = try? JSONEncoder().encode(usageStats) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKey.usageStats)
        }
    }

    private func loadUsageStats() {
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKey.usageStats),
           let stats = try? JSONDecoder().decode(UsageStats.self, from: data) {
            usageStats = stats
            usageStats.resetTodayIfNeeded()
        }
    }

    private func saveDictionary() {
        if let data = try? JSONEncoder().encode(dictionaryEntries) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKey.dictionary)
        }
    }

    private func loadDictionary() {
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKey.dictionary),
           let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            dictionaryEntries = entries
            deduplicateDictionary()
            sortDictionary()
        }
    }

    private func saveFillerSettings() {
        if let data = try? JSONEncoder().encode(fillerSettings) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKey.fillerSettings)
        }
    }

    private func loadFillerSettings() {
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKey.fillerSettings),
           let settings = try? JSONDecoder().decode(FillerSettings.self, from: data) {
            fillerSettings = settings
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKey.history)
            debugLog("💾 History saved (\(history.count) items)")
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKey.history),
           let records = try? JSONDecoder().decode([TranscriptionRecord].self, from: data) {
            history = records
            debugLog("📂 History loaded (\(records.count) items)")
        }
    }

    func addDictionaryEntry(_ entry: DictionaryEntry) {
        guard !dictionaryEntries.contains(where: { $0.reading == entry.reading }) else {
            debugLog("⚠️ Duplicate dictionary entry ignored: \(entry.reading)")
            return
        }
        dictionaryEntries.append(entry)
        sortDictionary()
        saveDictionary()
    }

    func removeDictionaryEntry(_ entry: DictionaryEntry) {
        dictionaryEntries.removeAll { $0.id == entry.id }
        saveDictionary()
    }

    func updateDictionaryEntry(_ entry: DictionaryEntry) {
        if let index = dictionaryEntries.firstIndex(where: { $0.id == entry.id }) {
            dictionaryEntries[index] = entry
            sortDictionary()
            saveDictionary()
        }
    }

    func deduplicateDictionary() {
        var seen = Set<String>()
        var unique: [DictionaryEntry] = []
        for entry in dictionaryEntries {
            if !seen.contains(entry.reading) {
                seen.insert(entry.reading)
                unique.append(entry)
            }
        }
        if unique.count != dictionaryEntries.count {
            debugLog("🧹 Removed \(dictionaryEntries.count - unique.count) duplicate entries")
            dictionaryEntries = unique
            sortDictionary()
            saveDictionary()
        }
    }

    private func sortDictionary() {
        dictionaryEntries.sort { $0.reading.localizedCompare($1.reading) == .orderedAscending }
    }

    func recordConversion(characters: Int, tokens: Int) {
        usageStats.recordConversion(characters: characters, tokens: tokens)
        saveUsageStats()
    }

    func updateFillerSettings(_ settings: FillerSettings) {
        fillerSettings = settings
        saveFillerSettings()
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
    private var accumulatedText = ""
    private var currentSegmentText = ""
    private var lastResultTime = Date()

    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var recordingFormat: AVAudioFormat?

    init(onTranscription: @escaping (String, Bool) -> Void, onRealtimeInput: @escaping (String, String) -> Void) {
        self.onTranscription = onTranscription
        self.onRealtimeInput = onRealtimeInput
    }

    func startRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        lastTranscription = ""
        accumulatedText = ""
        currentSegmentText = ""
        lastResultTime = Date()
        audioBuffers = []

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw NSError(domain: "SpeechService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create request"])
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        recordingFormat = format

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            recognitionRequest.append(buffer)
            if let copy = self?.copyBuffer(buffer) {
                self?.audioBuffers.append(copy)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        debugLog("🔍 [DEBUG] Starting recognition task")
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let error {
                debugLog("🔍 [DEBUG] Recognition error: \(error)")
            }
            if let result {
                let segmentText = result.bestTranscription.formattedString
                let oldText = self.lastTranscription
                let previousSegment = self.currentSegmentText
                let now = Date()
                let timeSinceLastResult = now.timeIntervalSince(self.lastResultTime)
                debugLog("🔍 [DEBUG] Recognition result: segment='\(segmentText)', isFinal: \(result.isFinal), accumulated='\(self.accumulatedText)', prevSegment='\(previousSegment)', timeDelta=\(String(format: "%.2f", timeSinceLastResult))s")

                let textGotShorter = previousSegment.count > 2 && segmentText.count < previousSegment.count / 2
                let enoughTimePassed = timeSinceLastResult > 1.0
                let isNewSegment = !previousSegment.isEmpty && enoughTimePassed && (textGotShorter || (!segmentText.hasPrefix(previousSegment) && !previousSegment.hasPrefix(segmentText)))
                if isNewSegment {
                    let separator = self.accumulatedText.isEmpty ? "" : " "
                    self.accumulatedText += separator + previousSegment
                    debugLog("🔍 [DEBUG] New segment detected (shorter=\(textGotShorter), timeDelta=\(String(format: "%.2f", timeSinceLastResult))s)! Accumulated previous: '\(self.accumulatedText)'")
                }

                self.currentSegmentText = segmentText
                self.lastResultTime = now

                if result.isFinal {
                    let separator = self.accumulatedText.isEmpty ? "" : " "
                    self.accumulatedText += separator + segmentText
                    self.currentSegmentText = ""
                    self.lastTranscription = self.accumulatedText
                    self.onTranscription(self.accumulatedText, true)
                    debugLog("🔍 [DEBUG] Segment finalized, accumulated: '\(self.accumulatedText)'")
                } else {
                    let separator = self.accumulatedText.isEmpty ? "" : " "
                    let fullText = self.accumulatedText + separator + segmentText
                    self.lastTranscription = fullText
                    self.onTranscription(fullText, false)
                }
                self.onRealtimeInput(oldText, self.lastTranscription)
            }
        }
        debugLog("🔍 [DEBUG] Recognition task created: \(recognitionTask != nil)")
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }
        copy.frameLength = buffer.frameLength

        if let srcFloatData = buffer.floatChannelData, let dstFloatData = copy.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                memcpy(dstFloatData[channel], srcFloatData[channel], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }
        return copy
    }

    func getRecordedAudioData() -> Data? {
        guard let format = recordingFormat, !audioBuffers.isEmpty else {
            debugLog("❌ No audio buffers to convert")
            return nil
        }

        let totalFrames = audioBuffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else {
            debugLog("❌ Audio buffers are empty")
            return nil
        }

        debugLog("🎵 Converting \(audioBuffers.count) buffers (\(totalFrames) frames) to WAV")

        let wavHeader = createWAVHeader(
            sampleRate: UInt32(format.sampleRate),
            channels: UInt16(format.channelCount),
            bitsPerSample: 16,
            dataSize: UInt32(totalFrames * Int(format.channelCount) * 2)
        )

        var audioData = Data()
        audioData.append(wavHeader)

        for buffer in audioBuffers {
            if let floatData = buffer.floatChannelData {
                for frame in 0..<Int(buffer.frameLength) {
                    for channel in 0..<Int(format.channelCount) {
                        let sample = floatData[channel][frame]
                        let clampedSample = max(-1.0, min(1.0, sample))
                        var int16Sample = Int16(clampedSample * Float(Int16.max))
                        withUnsafeBytes(of: &int16Sample) { audioData.append(contentsOf: $0) }
                    }
                }
            }
        }

        debugLog("🎵 WAV data created: \(audioData.count) bytes")
        return audioData
    }

    private func createWAVHeader(sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16, dataSize: UInt32) -> Data {
        var header = Data()

        header.append(contentsOf: "RIFF".utf8)
        var fileSize = dataSize + 36
        withUnsafeBytes(of: &fileSize) { header.append(contentsOf: $0) }

        header.append(contentsOf: "WAVE".utf8)

        header.append(contentsOf: "fmt ".utf8)
        var fmtSize: UInt32 = 16
        withUnsafeBytes(of: &fmtSize) { header.append(contentsOf: $0) }
        var audioFormat: UInt16 = 1
        withUnsafeBytes(of: &audioFormat) { header.append(contentsOf: $0) }
        var numChannels = channels
        withUnsafeBytes(of: &numChannels) { header.append(contentsOf: $0) }
        var sampleRateVal = sampleRate
        withUnsafeBytes(of: &sampleRateVal) { header.append(contentsOf: $0) }
        var byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        withUnsafeBytes(of: &byteRate) { header.append(contentsOf: $0) }
        var blockAlign = channels * bitsPerSample / 8
        withUnsafeBytes(of: &blockAlign) { header.append(contentsOf: $0) }
        var bitsPerSampleVal = bitsPerSample
        withUnsafeBytes(of: &bitsPerSampleVal) { header.append(contentsOf: $0) }

        header.append(contentsOf: "data".utf8)
        var dataSizeVal = dataSize
        withUnsafeBytes(of: &dataSizeVal) { header.append(contentsOf: $0) }

        return header
    }

    func clearAudioBuffers() {
        audioBuffers = []
    }
}

enum GeminiError: Error {
    case apiKeyMissing
    case audioDataEmpty
    case apiError(statusCode: Int, message: String)
    case parseError
    case timeout
}

final class GeminiService {
    private let apiKey: String
    private let modelName = "gemini-3-flash-preview"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let dictionaryEntries: [DictionaryEntry]
    private let fillerSettings: FillerSettings

    init(apiKey: String, dictionaryEntries: [DictionaryEntry] = [], fillerSettings: FillerSettings = FillerSettings()) {
        self.apiKey = apiKey
        self.dictionaryEntries = dictionaryEntries
        self.fillerSettings = fillerSettings
    }

    private func buildPrompt() -> String {
        var parts: [String] = [
            "この音声を書き起こしてください。",
            "重要: 音声に含まれている内容のみを書き起こしてください。音声にない内容を追加しないでください。"
        ]

        if fillerSettings.addPunctuation {
            parts.append("句読点を適切に入れてください（文末に「。」、疑問文に「？」、文中の区切りに「、」）。")
        }

        if fillerSettings.removeRepetition {
            parts.append("言い淀みの繰り返し（「あの、あの」など）は1回にまとめてください。")
        }

        if fillerSettings.removeFillers {
            let fillers = fillerSettings.allEnabledFillers
            if !fillers.isEmpty {
                parts.append("フィラー（\(fillers.joined(separator: "、"))）は除去してください。")
            }
        }

        let enabledEntries = dictionaryEntries.filter { $0.isEnabled }
        if !enabledEntries.isEmpty {
            let rules = enabledEntries.map { "「\($0.reading)」→「\($0.writing)」" }.joined(separator: "、")
            parts.append("音声内に以下の読みが含まれる場合のみ変換: \(rules)")
        }

        parts.append("書き起こし結果のみ出力：")

        return parts.joined(separator: "\n")
    }

    func transcribe(audioData: Data) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.apiKeyMissing
        }
        guard !audioData.isEmpty else {
            throw GeminiError.audioDataEmpty
        }

        let base64Audio = audioData.base64EncodedString()
        let url = URL(string: "\(baseURL)/\(modelName):generateContent")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let prompt = buildPrompt()
        debugLog("📝 Prompt: \(prompt)")

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    [
                        "inlineData": [
                            "mimeType": "audio/wav",
                            "data": base64Audio
                        ]
                    ]
                ]
            ]],
            "generationConfig": [
                "maxOutputTokens": 8192,
                "temperature": 0.2
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        debugLog("🌐 Transcribing audio with Gemini 3 Flash...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.apiError(statusCode: -1, message: "Invalid response")
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("❌ Gemini API error: \(httpResponse.statusCode) - \(errorMessage)")
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            debugLog("❌ Failed to parse Gemini response")
            throw GeminiError.parseError
        }

        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        debugLog("✅ Transcription result: '\(result)'")
        return result
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

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.level = .screenSaver

        let hostingView = NSHostingView(rootView: FloatingPanelView(appState: appState))
        panel.contentView = hostingView

        self.window = panel
    }

    private func positionNearCursor() {
        guard let window, let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let panelWidth = screenFrame.width * 0.35
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.minY + screenFrame.height * 0.12

        debugLog("📍 Position: fixed center-bottom (\(x), \(y)), panelWidth: \(panelWidth)")
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func getCaretPosition() -> NSPoint? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            debugLog("📍 getCaretPosition: Failed to get focused element")
            return nil
        }

        let element = focusedElement as! AXUIElement

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success {
            debugLog("📍 getCaretPosition: Element role = \(roleValue as? String ?? "unknown")")
        }

        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success else {
            debugLog("📍 getCaretPosition: Failed to get selected range")
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRangeValue!, &boundsValue) == .success else {
            debugLog("📍 getCaretPosition: Failed to get bounds for range")
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds) else {
            debugLog("📍 getCaretPosition: Failed to get bounds value")
            return nil
        }

        debugLog("📍 getCaretPosition: Raw bounds = \(bounds)")

        if bounds.width == 0 && bounds.height == 0 {
            debugLog("📍 getCaretPosition: Bounds size is zero, returning nil")
            return nil
        }
        if bounds.origin.x == 0 && bounds.width == 0 {
            debugLog("📍 getCaretPosition: Bounds x=0 and width=0, likely invalid")
            return nil
        }

        guard let screen = NSScreen.main else { return nil }
        let flippedY = screen.frame.height - bounds.origin.y - bounds.height
        debugLog("📍 getCaretPosition: screen.height=\(screen.frame.height), flippedY=\(flippedY)")
        return NSPoint(x: bounds.origin.x, y: flippedY)
    }

    private func getFocusedElementPosition() -> NSPoint? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            debugLog("📍 getFocusedElement: Failed to get focused element")
            return nil
        }

        let element = focusedElement as! AXUIElement

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success {
            debugLog("📍 getFocusedElement: Element role = \(roleValue as? String ?? "unknown")")
        }

        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success else {
            debugLog("📍 getFocusedElement: Failed to get position")
            return nil
        }

        var position = CGPoint.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else {
            debugLog("📍 getFocusedElement: Failed to get position value")
            return nil
        }

        var sizeValue: CFTypeRef?
        var size = CGSize.zero
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }

        debugLog("📍 getFocusedElement: Raw position = \(position), size = \(size)")

        if size.height > 100 {
            debugLog("📍 getFocusedElement: Element too tall (\(size.height)), likely a window/container")
            return nil
        }

        guard let screen = NSScreen.main else { return nil }
        let flippedY = screen.frame.height - position.y - size.height
        debugLog("📍 getFocusedElement: screen.height=\(screen.frame.height), flippedY=\(flippedY)")
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
        window?.orderFrontRegardless()
        if let window {
            debugLog("🪟 Window level: \(window.level.rawValue), isVisible: \(window.isVisible)")
        }
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

struct SpinningIcon: View {
    @State private var rotation = 0.0

    var body: some View {
        Image(systemName: "arrow.trianglehead.2.clockwise")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.blue)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

struct FloatingPanelView: View {
    var appState: AppState
    @State private var isPulsing = false

    private var panelWidth: CGFloat {
        (NSScreen.main?.frame.width ?? 1600) * 0.35
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.7 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }

            if appState.currentTranscription.isEmpty {
                Text("Listening...")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text(appState.currentTranscription)
                    .font(.system(size: 18, weight: .medium))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if appState.isConverting {
                SpinningIcon()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(width: panelWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct MenuBarView: View {
    var appState: AppState
    @Environment(\.openWindow) private var openWindow

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

            Button("Nice Voice を開く...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 200)
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

enum NavigationPage: String, CaseIterable {
    case overview = "概要"
    case history = "履歴"
    case dictionary = "辞書"
    case settings = "設定"

    var icon: String {
        switch self {
        case .overview: return "chart.bar"
        case .history: return "clock"
        case .dictionary: return "book"
        case .settings: return "gearshape"
        }
    }
}

struct MainWindowView: View {
    var appState: AppState
    @State private var selectedPage: NavigationPage = .overview

    var body: some View {
        NavigationSplitView {
            List(NavigationPage.allCases, id: \.self, selection: $selectedPage) { page in
                Label(page.rawValue, systemImage: page.icon)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        } detail: {
            switch selectedPage {
            case .overview:
                OverviewView(appState: appState)
            case .history:
                HistoryContentView(appState: appState)
            case .dictionary:
                DictionaryView(appState: appState)
            case .settings:
                SettingsContentView(appState: appState)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

struct OverviewView: View {
    var appState: AppState
    @State private var animateCards = false

    private var estimatedCost: Double {
        Double(appState.usageStats.totalTokensUsed) * 0.0000005
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("概要")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("音声認識の使用状況")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(isReady: appState.isReady, isRecording: appState.isRecording)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    StatCard(
                        title: "今日の変換",
                        value: "\(appState.usageStats.todayConversions)",
                        subtitle: "\(appState.usageStats.todayCharacters) 文字",
                        icon: "waveform",
                        color: .blue
                    )
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 20)

                    StatCard(
                        title: "累計変換",
                        value: "\(appState.usageStats.totalConversions)",
                        subtitle: "\(appState.usageStats.totalCharacters) 文字",
                        icon: "chart.line.uptrend.xyaxis",
                        color: .green
                    )
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 20)

                    StatCard(
                        title: "推定コスト",
                        value: String(format: "$%.4f", estimatedCost),
                        subtitle: String(format: "約 %.1f 円", estimatedCost * 150),
                        icon: "yensign.circle",
                        color: .orange
                    )
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 20)
                }

                RecentTranscriptionsCard(appState: appState)
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 20)

                Spacer()
            }
            .padding(28)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                animateCards = true
            }
        }
    }
}

struct StatusBadge: View {
    let isReady: Bool
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.1))
        .cornerRadius(20)
    }

    private var statusColor: Color {
        if isRecording { return .red }
        if isReady { return .green }
        return .orange
    }

    private var statusText: String {
        if isRecording { return "録音中" }
        if isReady { return "準備完了" }
        return "初期化中"
    }
}

struct RecentTranscriptionsCard: View {
    var appState: AppState
    @State private var hoveredId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("最近の変換", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if !appState.history.isEmpty {
                    Text("\(appState.history.count) 件")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            if appState.history.isEmpty {
                EmptyStateView(
                    icon: "waveform.slash",
                    title: "まだ変換履歴がありません",
                    description: "fn キーを押しながら話すと、\n音声がテキストに変換されます"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appState.history.prefix(5).enumerated()), id: \.element.id) { index, record in
                        RecentTranscriptionRow(
                            record: record,
                            isHovered: hoveredId == record.id,
                            onCopy: { appState.copyHistoryItem(record.text) }
                        )
                        .onHover { isHovered in
                            hoveredId = isHovered ? record.id : nil
                        }

                        if index < min(4, appState.history.count - 1) {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        }
    }
}

struct RecentTranscriptionRow: View {
    let record: TranscriptionRecord
    let isHovered: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: "text.bubble")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.text)
                    .lineLimit(1)
                    .font(.callout)
                Text(record.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
        .cornerRadius(8)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFocused ? .primary : .secondary)
            TextField("検索", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .frame(width: 140)
            if !text.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        }
    }
}

struct ModernHistoryRowView: View {
    let record: TranscriptionRecord
    var appState: AppState
    @State private var isHovered = false
    @State private var showCopiedFeedback = false

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: record.timestamp)
    }

    private var dateString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(record.timestamp) {
            return "今日"
        } else if calendar.isDateInYesterday(record.timestamp) {
            return "昨日"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: record.timestamp)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.text)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(dateString)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(timeString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if showCopiedFeedback {
                    Text("コピーしました")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale))
                }

                Button {
                    appState.copyHistoryItem(record.text)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showCopiedFeedback = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showCopiedFeedback = false
                        }
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(isHovered ? 0.1 : 0))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        appState.removeHistoryItem(record)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(isHovered ? 0.1 : 0))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.06) : Color.clear)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    var trend: Double? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                if let trend = trend {
                    HStack(spacing: 2) {
                        Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.weight(.bold))
                        Text("\(abs(Int(trend)))%")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(trend >= 0 ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background((trend >= 0 ? Color.green : Color.red).opacity(0.1))
                    .cornerRadius(6)
                }
            }

            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 12 : 8, y: isHovered ? 4 : 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct HistoryContentView: View {
    var appState: AppState
    @State private var searchText = ""
    @State private var showingClearConfirmation = false
    @State private var animateContent = false

    private var filteredHistory: [TranscriptionRecord] {
        if searchText.isEmpty {
            return appState.history
        }
        return appState.history.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("履歴")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("変換した音声の記録")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SearchField(text: $searchText)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            if filteredHistory.isEmpty {
                Spacer()
                if appState.history.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "履歴がありません",
                        description: "変換した音声はここに記録されます"
                    )
                } else {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "該当する履歴がありません",
                        description: "「\(searchText)」に一致する結果が見つかりませんでした"
                    )
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredHistory) { record in
                        ModernHistoryRowView(record: record, appState: appState)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        appState.removeHistoryItem(record)
                                    }
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    appState.copyHistoryItem(record.text)
                                } label: {
                                    Label("コピー", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(appState.history.count) 件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingClearConfirmation = true
                } label: {
                    Label("すべてクリア", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(appState.history.isEmpty ? Color.secondary.opacity(0.5) : Color.red)
                .disabled(appState.history.isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .alert("履歴をすべて削除しますか？", isPresented: $showingClearConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                appState.clearHistory()
            }
        } message: {
            Text("この操作は取り消せません。")
        }
    }
}

struct HistoryWindowView: View {
    var appState: AppState
    @State private var searchText = ""

    private var filteredHistory: [TranscriptionRecord] {
        if searchText.isEmpty {
            return appState.history
        }
        return appState.history.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("検索", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding()

            Divider()

            if filteredHistory.isEmpty {
                Spacer()
                if appState.history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("履歴がありません")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("該当する履歴がありません")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredHistory) { record in
                        HistoryRowView(record: record, appState: appState)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Text("\(appState.history.count) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("すべてクリア") {
                    appState.clearHistory()
                }
                .disabled(appState.history.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
    }
}

struct DictionaryView: View {
    var appState: AppState
    @State private var showingAddSheet = false
    @State private var editingEntry: DictionaryEntry?
    @State private var showingImportError = false
    @State private var importErrorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("辞書")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("カスタム変換ルール")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Menu {
                        Button {
                            importDictionary()
                        } label: {
                            Label("インポート", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            exportDictionary()
                        } label: {
                            Label("エクスポート", systemImage: "square.and.arrow.up")
                        }
                        .disabled(appState.dictionaryEntries.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("追加", systemImage: "plus")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            if appState.dictionaryEntries.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    EmptyStateView(
                        icon: "character.book.closed",
                        title: "辞書が空です",
                        description: "変換ルールを追加すると、\n音声認識結果に自動で適用されます"
                    )
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("ルールを追加", systemImage: "plus")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Spacer()
            } else {
                List {
                    ForEach(appState.dictionaryEntries) { entry in
                        DictionaryEntryRow(
                            entry: entry,
                            onToggle: { enabled in
                                var updated = entry
                                updated.isEnabled = enabled
                                appState.updateDictionaryEntry(updated)
                            },
                            onEdit: { editingEntry = entry },
                            onDelete: { appState.removeDictionaryEntry(entry) }
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    appState.removeDictionaryEntry(entry)
                                }
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            if !appState.dictionaryEntries.isEmpty {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("\(appState.dictionaryEntries.count) 件のルール")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let enabledCount = appState.dictionaryEntries.filter { $0.isEnabled }.count
                    Text("\(enabledCount) 件が有効")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(.bar)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            DictionaryEditSheet(appState: appState, entry: nil)
        }
        .sheet(item: $editingEntry) { entry in
            DictionaryEditSheet(appState: appState, entry: entry)
        }
        .alert("インポートエラー", isPresented: $showingImportError) {
            Button("OK") {}
        } message: {
            Text(importErrorMessage)
        }
    }

    private func exportDictionary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "nicevoice-dictionary.json"
        panel.title = "辞書をエクスポート"

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(appState.dictionaryEntries)
                try data.write(to: url)
                debugLog("📤 Dictionary exported to \(url.path)")
            } catch {
                debugLog("❌ Export failed: \(error)")
            }
        }
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "辞書をインポート"

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let entries = try decoder.decode([DictionaryEntry].self, from: data)

                for entry in entries {
                    if !appState.dictionaryEntries.contains(where: { $0.reading == entry.reading }) {
                        appState.addDictionaryEntry(entry)
                    }
                }
                debugLog("📥 Imported \(entries.count) dictionary entries")
            } catch {
                importErrorMessage = "ファイルの読み込みに失敗しました: \(error.localizedDescription)"
                showingImportError = true
                debugLog("❌ Import failed: \(error)")
            }
        }
    }
}

struct DictionaryEntryRow: View {
    let entry: DictionaryEntry
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(entry.isEnabled ? Color.purple.opacity(0.1) : Color.secondary.opacity(0.05))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(entry.isEnabled ? .purple : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.reading)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(entry.isEnabled ? .primary : .secondary)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text(entry.writing)
                        .font(.caption)
                        .foregroundStyle(entry.isEnabled ? .secondary : .tertiary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Toggle("", isOn: Binding(
                    get: { entry.isEnabled },
                    set: onToggle
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(isHovered ? 0.1 : 0))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(isHovered ? 0.1 : 0))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.06) : Color.clear)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct DictionaryEditSheet: View {
    var appState: AppState
    var entry: DictionaryEntry?
    @Environment(\.dismiss) private var dismiss
    @State private var reading = ""
    @State private var writing = ""

    private var isEditing: Bool { entry != nil }

    var body: some View {
        VStack(spacing: 20) {
            Text(isEditing ? "ルールを編集" : "ルールを追加")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("読み（認識される言葉）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("例: くろーど", text: $reading)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("表記（変換後の言葉）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("例: Claude", text: $writing)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("キャンセル") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "保存" : "追加") {
                    if let entry {
                        var updated = entry
                        updated.reading = reading
                        updated.writing = writing
                        appState.updateDictionaryEntry(updated)
                    } else {
                        let newEntry = DictionaryEntry(reading: reading, writing: writing)
                        appState.addDictionaryEntry(newEntry)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(reading.isEmpty || writing.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 350)
        .onAppear {
            if let entry {
                reading = entry.reading
                writing = entry.writing
            }
        }
    }
}

struct HistoryRowView: View {
    let record: TranscriptionRecord
    var appState: AppState
    @State private var isHovered = false

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: record.timestamp)
    }

    private var dateString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(record.timestamp) {
            return "今日"
        } else if calendar.isDateInYesterday(record.timestamp) {
            return "昨日"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: record.timestamp)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.text)
                    .lineLimit(3)
                HStack(spacing: 4) {
                    Text(dateString)
                    Text(timeString)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    appState.copyHistoryItem(record.text)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0.3)
                .help("コピー")

                Button {
                    appState.removeHistoryItem(record)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0.3)
                .help("削除")
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SettingsContentView: View {
    var appState: AppState
    @AppStorage("useGemini") private var useGemini = true
    @AppStorage("geminiApiKey") private var geminiApiKey = ""
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @State private var validationState: ValidationState = .none
    @State private var isValidating = false
    @State private var fillerSettings: FillerSettings
    @State private var newFiller = ""
    @State private var animateContent = false

    private let presetFillers = ["えー", "あー", "うーん", "まあ", "なんか", "ちょっと", "ですね", "ですよね"]

    enum ValidationState {
        case none
        case valid
        case invalid(String)
    }

    init(appState: AppState) {
        self.appState = appState
        _fillerSettings = State(initialValue: appState.fillerSettings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("設定")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("アプリの動作をカスタマイズ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SettingsSection(title: "一般", icon: "gearshape", color: .gray) {
                    SettingsToggleRow(
                        title: "メニューバーに常駐する",
                        description: "オフにすると Dock からのみ起動できます",
                        isOn: $showInMenuBar
                    )
                }
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 10)

                SettingsSection(title: "Gemini API", icon: "sparkles", color: .blue) {
                    SettingsToggleRow(
                        title: "高精度変換を使用",
                        description: "Gemini API を使用して高精度な変換を行います",
                        isOn: $useGemini
                    )

                    if useGemini {
                        Divider()
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                SecureField("API キー", text: $geminiApiKey)
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(8)
                                    .onChange(of: geminiApiKey) { _, _ in
                                        validationState = .none
                                    }

                                Button {
                                    validateApiKey()
                                } label: {
                                    if isValidating {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .frame(width: 60, height: 32)
                                    } else {
                                        Text("テスト")
                                            .font(.callout.weight(.medium))
                                            .frame(width: 60, height: 32)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(geminiApiKey.isEmpty || isValidating)
                            }

                            switch validationState {
                            case .none:
                                if geminiApiKey.isEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "key")
                                            .font(.caption)
                                        Text("API キーを入力してください")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            case .valid:
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("API キーは有効です")
                                }
                                .font(.caption)
                                .foregroundStyle(.green)
                            case .invalid(let message):
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text(message)
                                }
                                .font(.caption)
                                .foregroundStyle(.red)
                            }

                            Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                                HStack(spacing: 4) {
                                    Text("Google AI Studio で API キーを取得")
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 10)

                if useGemini {
                    SettingsSection(title: "書き起こし調整", icon: "text.alignleft", color: .purple) {
                        SettingsToggleRow(
                            title: "句読点を自動で付ける",
                            description: "。、？を適切な位置に追加して読みやすくします",
                            isOn: $fillerSettings.addPunctuation
                        )
                        .onChange(of: fillerSettings.addPunctuation) { _, _ in
                            appState.updateFillerSettings(fillerSettings)
                        }

                        Divider()
                            .padding(.vertical, 4)

                        SettingsToggleRow(
                            title: "言い淀み・繰り返しを整理",
                            description: "同じ言葉を繰り返した場合に1回にまとめます",
                            isOn: $fillerSettings.removeRepetition
                        )
                        .onChange(of: fillerSettings.removeRepetition) { _, _ in
                            appState.updateFillerSettings(fillerSettings)
                        }
                    }
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)

                    SettingsSection(title: "フィラー除去", icon: "text.badge.minus", color: .orange) {
                        SettingsToggleRow(
                            title: "フィラーを除去する",
                            description: "「えー」「あー」などの言葉を自動で除去します",
                            isOn: $fillerSettings.removeFillers
                        )
                        .onChange(of: fillerSettings.removeFillers) { _, _ in
                            appState.updateFillerSettings(fillerSettings)
                        }

                        if fillerSettings.removeFillers {
                            Divider()
                                .padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 12) {
                                Text("除去するフィラー")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)

                                FlowLayout(spacing: 8) {
                                    ForEach(presetFillers, id: \.self) { filler in
                                        ModernFillerChip(
                                            text: filler,
                                            isSelected: fillerSettings.enabledPresets.contains(filler)
                                        ) {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                if fillerSettings.enabledPresets.contains(filler) {
                                                    fillerSettings.enabledPresets.remove(filler)
                                                } else {
                                                    fillerSettings.enabledPresets.insert(filler)
                                                }
                                                appState.updateFillerSettings(fillerSettings)
                                            }
                                        }
                                    }
                                }

                                if !fillerSettings.customFillers.isEmpty {
                                    Text("カスタム")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)

                                    FlowLayout(spacing: 8) {
                                        ForEach(fillerSettings.customFillers, id: \.self) { filler in
                                            ModernFillerChip(text: filler, isSelected: true, canDelete: true) {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    fillerSettings.customFillers.removeAll { $0 == filler }
                                                    appState.updateFillerSettings(fillerSettings)
                                                }
                                            }
                                        }
                                    }
                                }

                                HStack(spacing: 8) {
                                    TextField("カスタムフィラーを追加", text: $newFiller)
                                        .textFieldStyle(.plain)
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(8)
                                        .frame(width: 180)
                                        .onSubmit {
                                            addCustomFiller()
                                        }

                                    Button {
                                        addCustomFiller()
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(newFiller.isEmpty)
                                }
                            }
                        }
                    }
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)

                    SettingsSection(title: "料金目安", icon: "yensign.circle", color: .green) {
                        VStack(spacing: 12) {
                            PriceRow(label: "Gemini 3 Flash", value: "$0.50 / 100万トークン")
                            PriceRow(label: "音声 1 分あたり", value: "約 $0.0008（≒ 0.12 円）")
                        }
                        Text("※ 1秒 ≈ 25トークン、1分 ≈ 1,500トークン")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)
                }

                Spacer(minLength: 20)
            }
            .padding(28)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                animateContent = true
            }
        }
    }

    private func validateApiKey() {
        isValidating = true
        validationState = .none

        Task {
            do {
                let isValid = try await testApiKey(geminiApiKey)
                await MainActor.run {
                    isValidating = false
                    validationState = isValid ? .valid : .invalid("API キーが無効です")
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    validationState = .invalid("接続エラー")
                }
            }
        }
    }

    private func testApiKey(_ apiKey: String) async throws -> Bool {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode == 200
    }

    private func addCustomFiller() {
        guard !newFiller.isEmpty else { return }
        guard !fillerSettings.customFillers.contains(newFiller) else {
            newFiller = ""
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            fillerSettings.customFillers.append(newFiller)
            appState.updateFillerSettings(fillerSettings)
            newFiller = ""
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.headline)
            }
            .padding(.bottom, 16)

            content
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct PriceRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
    }
}

struct ModernFillerChip: View {
    let text: String
    var isSelected: Bool = true
    var canDelete: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text)
                    .font(.caption)
                    .fontWeight(.medium)
                if canDelete {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}


struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = max(totalHeight, currentY + lineHeight)
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

struct FillerChip: View {
    let text: String
    var isSelected: Bool = true
    var canDelete: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text)
                if canDelete {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @AppStorage("useGemini") private var useGemini = true
    @AppStorage("geminiApiKey") private var geminiApiKey = ""
    @State private var validationState: ValidationState = .none
    @State private var isValidating = false

    enum ValidationState {
        case none
        case valid
        case invalid(String)
    }

    var body: some View {
        Form {
            Section {
                Text("Nice Voice 設定")
                    .font(.title)
                Text("fn キーを押している間、音声を録音します")
            }

            Section("Gemini API") {
                Toggle("高精度変換を行う", isOn: $useGemini)

                if useGemini {
                    HStack {
                        SecureField("API キー", text: $geminiApiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: geminiApiKey) { _, _ in
                                validationState = .none
                            }

                        Button {
                            validateApiKey()
                        } label: {
                            if isValidating {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 50)
                            } else {
                                Text("テスト")
                                    .frame(width: 50)
                            }
                        }
                        .disabled(geminiApiKey.isEmpty || isValidating)
                    }

                    switch validationState {
                    case .none:
                        if geminiApiKey.isEmpty {
                            Label("API キーを入力してください", systemImage: "key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .valid:
                        Label("API キーは有効です", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .invalid(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Link("Google AI Studio で API キーを取得", destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.caption)
                }
            }

            if useGemini {
                Section("料金目安") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Gemini 3 Flash")
                                .font(.caption)
                            Spacer()
                            Text("$0.50 / 100万トークン")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("音声 1 分あたり")
                                .font(.caption)
                            Spacer()
                            Text("約 $0.0008（≒ 0.12 円）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("※ 1秒 ≈ 25トークン、1分 ≈ 1,500トークン")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 450, height: useGemini ? 420 : 280)
    }

    private func validateApiKey() {
        isValidating = true
        validationState = .none

        Task {
            do {
                let isValid = try await testApiKey(geminiApiKey)
                await MainActor.run {
                    isValidating = false
                    validationState = isValid ? .valid : .invalid("API キーが無効です")
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    validationState = .invalid("接続エラー: \(error.localizedDescription)")
                }
            }
        }
    }

    private func testApiKey(_ apiKey: String) async throws -> Bool {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode == 200
    }
}
