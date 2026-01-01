import SwiftUI
import AVFoundation
import Speech
import AppKit
import Carbon.HIToolbox
import ApplicationServices
import os.log
import Network
import CommonCrypto

private let logger = Logger(subsystem: "com.nicevoice.app", category: "general")

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

private let logDirectory: URL = {
    let logsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NiceVoice")
    try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    return logsDir
}()

private let logFilePath: String = {
    logDirectory.appendingPathComponent("debug.log").path
}()

private let maxLogFileSize: UInt64 = 5 * 1024 * 1024
private let maxLogBackups = 3

private func rotateLogIfNeeded() {
    let fm = FileManager.default
    guard let attrs = try? fm.attributesOfItem(atPath: logFilePath),
          let fileSize = attrs[.size] as? UInt64,
          fileSize >= maxLogFileSize else {
        return
    }

    for i in stride(from: maxLogBackups - 1, through: 0, by: -1) {
        let oldPath = i == 0 ? logFilePath : "\(logFilePath).\(i)"
        let newPath = "\(logFilePath).\(i + 1)"

        if i == maxLogBackups - 1 {
            try? fm.removeItem(atPath: newPath)
        }
        if fm.fileExists(atPath: oldPath) {
            try? fm.moveItem(atPath: oldPath, toPath: newPath)
        }
    }
}

func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"
    print(logMessage, terminator: "")
    logger.debug("\(message, privacy: .public)")

    rotateLogIfNeeded()

    guard let logData = logMessage.data(using: .utf8) else { return }
    if let handle = FileHandle(forWritingAtPath: logFilePath) {
        handle.seekToEndOfFile()
        handle.write(logData)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logFilePath, contents: logData)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: NSStatusItem?

    @AppStorage("showInMenuBar") var showInMenuBar = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("✅ NiceVoice started")
        checkAccessibilityPermission()
        setupStatusItem()
        setupFillerDetection()

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

    private func setupFillerDetection() {
        let devVarsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("nicevoice-app/.dev.vars").path
        FillerDetectionService.setupAPIKey(from: devVarsPath)
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
    let audioPath: String?

    init(text: String, timestamp: Date, audioPath: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.audioPath = audioPath
    }

    init(id: UUID, text: String, timestamp: Date, audioPath: String? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.audioPath = audioPath
    }

    var hasAudio: Bool {
        guard let path = audioPath else { return false }
        return FileManager.default.fileExists(atPath: path)
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
        "えー", "えぅ", "えぇ",
        "あー", "あぁ",
        "うーん"
    ]
    var customFillers: [String] = []

    var addPunctuation: Bool = true
    var removeRepetition: Bool = true

    var useSmartFillerDetection: Bool = false
    var ambiguousFillers: Set<String> = [
        "あの", "その", "ちょっと",
        "なんか", "まあ", "まぁ",
        "こう", "ほら",
        "やっぱり", "やっぱ"
    ]

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
    var errorMessage: String?
    var history: [TranscriptionRecord] = []
    var audioLevels: [Float] = Array(repeating: 0, count: 20)

    @ObservationIgnored
    @AppStorage("shortcutKey") var shortcutKeyRaw = ShortcutKey.fn.rawValue

    var shortcutKey: ShortcutKey {
        get { ShortcutKey(rawValue: shortcutKeyRaw) ?? .fn }
        set {
            shortcutKeyRaw = newValue.rawValue
            keyMonitor?.updateShortcutKey(newValue)
        }
    }

    @ObservationIgnored
    var usageStats: UsageStats = UsageStats()
    @ObservationIgnored
    var dictionaryEntries: [DictionaryEntry] = []
    @ObservationIgnored
    var fillerSettings: FillerSettings = FillerSettings()

    private var speechService: SpeechRecognitionService?
    private var chromeSpeechService: ChromeSpeechService?
    private var speechAnalyzerService: Any?
    private(set) var keyMonitor: KeyMonitor?
    private var floatingPanel: FloatingPanel?
    private var waitingForFinalResult = false
    private var finalResultTimer: DispatchWorkItem?
    private var sfSpeechResult = ""
    private var useChromeSpeech = false
    private var useSpeechAnalyzer = false

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
                    guard let self else { return }
                    self.currentTranscription = self.addLocalPunctuation(text, isFinal: isFinal)
                    if isFinal {
                        self.handleFinalResult(text)
                    }
                }
            },
            onRealtimeInput: { [weak self] oldText, newText in
                self?.handleRealtimeInput(oldText: oldText, newText: newText)
            },
            onRecognitionError: { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    debugLog("❌ Apple speech error: \(error)")
                    self.isReady = false
                    self.isRecording = false
                    self.statusMessage = error
                    self.errorMessage = error
                }
            }
        )

        chromeSpeechService = ChromeSpeechService(
            onTranscription: { [weak self] text, isFinal in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.currentTranscription = self.addLocalPunctuation(text, isFinal: isFinal)
                    if isFinal {
                        self.handleFinalResult(text)
                    }
                }
            },
            onError: { [weak self] error in
                debugLog("❌ Chrome speech error: \(error)")
                self?.statusMessage = error
            },
            onStatusChange: { [weak self] status in
                DispatchQueue.main.async {
                    self?.statusMessage = status
                }
            }
        )

        if #available(macOS 26.0, *) {
            speechAnalyzerService = SpeechAnalyzerService(
                onTranscription: { [weak self] text, isFinal in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.currentTranscription = self.addLocalPunctuation(text, isFinal: isFinal)
                        if isFinal {
                            self.handleFinalResult(text)
                        }
                    }
                },
                onError: { [weak self] error in
                    debugLog("❌ SpeechAnalyzer error: \(error)")
                    self?.statusMessage = error
                },
                onStatusChange: { [weak self] status in
                    DispatchQueue.main.async {
                        self?.statusMessage = status
                    }
                },
                onAudioLevel: { [weak self] level in
                    guard let self else { return }
                    self.audioLevels.removeFirst()
                    self.audioLevels.append(level)
                }
            )
        }

        keyMonitor = KeyMonitor(
            shortcutKey: shortcutKey,
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

        let micStatus = await AVCaptureDevice.requestAccess(for: .audio)
        guard micStatus else {
            await MainActor.run {
                statusMessage = "マイクの権限が必要です"
            }
            return
        }

        if #available(macOS 26.0, *), let service = speechAnalyzerService as? SpeechAnalyzerService {
            await MainActor.run {
                statusMessage = "SpeechAnalyzer を初期化中..."
            }
            await service.start()
            await MainActor.run {
                useSpeechAnalyzer = true
                useChromeSpeech = false
                isReady = true
                statusMessage = "準備完了 - \(shortcutKey.displayName) キーを押して録音 (SpeechAnalyzer)"
                debugLog("✅ Using Apple SpeechAnalyzer")
            }
        } else if ChromeSpeechService.isAvailable {
            await MainActor.run {
                useChromeSpeech = true
                useSpeechAnalyzer = false
                isReady = true
                let browserName = ChromeSpeechService.detectBrowser()?.split(separator: "/").last?.replacingOccurrences(of: ".app", with: "") ?? "Chrome"
                statusMessage = "準備完了 - \(shortcutKey.displayName) キーを押して録音 (\(browserName))"
                debugLog("✅ Using Chrome Web Speech API")
                chromeSpeechService?.start()
            }
        } else {
            let speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }

            if speechStatus == .authorized {
                await MainActor.run {
                    useChromeSpeech = false
                    useSpeechAnalyzer = false
                    isReady = true
                    statusMessage = "準備完了 - \(shortcutKey.displayName) キーを押して録音 (Apple Legacy)"
                    debugLog("✅ Using Apple SFSpeechRecognizer")
                }
            } else {
                await MainActor.run {
                    statusMessage = "音声認識が利用できません"
                    debugLog("❌ No speech recognition available")
                }
            }
        }
    }

    func startRecording() {
        debugLog("🔍 [DEBUG] startRecording called - isReady: \(isReady), isRecording: \(isRecording), useSpeechAnalyzer: \(useSpeechAnalyzer), useChrome: \(useChromeSpeech)")

        guard !isRecording else {
            debugLog("🔍 [DEBUG] startRecording guard failed - already recording")
            return
        }

        if !isReady {
            debugLog("🔍 [DEBUG] startRecording - not ready, showing error")
            errorMessage = "音声認識が初期化されていません"
            floatingPanel?.show()
            return
        }

        errorMessage = nil
        isRecording = true
        currentTranscription = ""
        debugLog("🎙️ Recording started")
        NotificationCenter.default.post(name: .recordingStateChanged, object: nil)

        floatingPanel?.show()

        if useSpeechAnalyzer {
            if #available(macOS 26.0, *), let service = speechAnalyzerService as? SpeechAnalyzerService {
                service.startRecording()
                debugLog("🔍 [DEBUG] speechAnalyzerService.startRecording() called")
            }
        } else if useChromeSpeech {
            chromeSpeechService?.startRecording()
            debugLog("🔍 [DEBUG] chromeSpeechService.startRecording() called")
        } else {
            do {
                try speechService?.startRecording()
                debugLog("🔍 [DEBUG] speechService.startRecording() succeeded")
            } catch {
                debugLog("❌ Recording error: \(error)")
                isRecording = false
                floatingPanel?.hide()
            }
        }
    }

    func stopRecording() {
        debugLog("🔍 [DEBUG] stopRecording called - isRecording: \(isRecording), errorMessage: \(errorMessage ?? "nil")")

        if errorMessage != nil {
            debugLog("🔍 [DEBUG] stopRecording - hiding error panel")
            errorMessage = nil
            floatingPanel?.hide()
            return
        }

        guard isRecording else {
            debugLog("🔍 [DEBUG] stopRecording guard failed - not recording")
            return
        }
        isRecording = false

        if useSpeechAnalyzer {
            if #available(macOS 26.0, *), let service = speechAnalyzerService as? SpeechAnalyzerService {
                waitingForFinalResult = true
                debugLog("🎙️ Recording stopped - waiting for SpeechAnalyzer final result")
                floatingPanel?.hide()
                service.stopRecording()
                NotificationCenter.default.post(name: .recordingStateChanged, object: nil)

                finalResultTimer = DispatchWorkItem { [weak self] in
                    guard let self, self.waitingForFinalResult else { return }
                    debugLog("⚠️ SpeechAnalyzer timeout - no final result received")
                    self.waitingForFinalResult = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: finalResultTimer!)
                return
            }
        }

        if useChromeSpeech {
            chromeSpeechService?.stopRecording()
        } else {
            speechService?.stopRecording()
        }
        debugLog("🎙️ Recording stopped")
        NotificationCenter.default.post(name: .recordingStateChanged, object: nil)

        sfSpeechResult = currentTranscription
        let fallbackResult = addLocalPunctuation(sfSpeechResult)
        debugLog("📝 Speech result: '\(fallbackResult)'")

        if fallbackResult.isEmpty {
            debugLog("⚠️ No speech detected, skipping")
            floatingPanel?.hide()
            clearActiveServiceAudioBuffers()
            return
        }

        let audioData = getRecordedAudioDataFromActiveService()
        floatingPanel?.hide()
        addToHistory(fallbackResult, audioData: audioData)
        performPaste(fallbackResult)
        clearActiveServiceAudioBuffers()
    }

    private func handleFinalResult(_ text: String) {
        guard waitingForFinalResult else { return }
        debugLog("✅ Final result received: '\(text)'")
        finalResultTimer?.cancel()
        waitingForFinalResult = false

        let processedText = addLocalPunctuation(text)
        if processedText.isEmpty {
            debugLog("⚠️ Final result empty after processing, skipping")
            floatingPanel?.hide()
            return
        }

        let audioData = getRecordedAudioDataFromActiveService()

        if fillerSettings.useSmartFillerDetection && fillerSettings.removeFillers {
            let ambiguous = fillerSettings.ambiguousFillers
            let hasAmbiguousWords = ambiguous.contains { processedText.contains($0) }

            if hasAmbiguousWords {
                let textToProcess = processedText
                Task {
                    let detectedFillers = await FillerDetectionService.detectFillers(
                        in: textToProcess,
                        ambiguousWords: ambiguous
                    )
                    var result = textToProcess
                    for filler in detectedFillers {
                        result = result.replacingOccurrences(of: filler, with: "")
                    }
                    result = self.cleanupOrphanedParticles(result)
                    let finalText = result.replacingOccurrences(of: "  ", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    await MainActor.run {
                        if !finalText.isEmpty {
                            self.addToHistory(finalText, audioData: audioData)
                            self.performPaste(finalText)
                        }
                    }
                }
                return
            }
        }

        addToHistory(processedText, audioData: audioData)
        performPaste(processedText)
    }

    private func cleanupOrphanedParticles(_ text: String) -> String {
        var result = text
        let orphanedParticlePatterns = [
            "^ね、", "^よ、", "^さ、", "^な、",
            "^ね。", "^よ。", "^さ。", "^な。"
        ]
        for pattern in orphanedParticlePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addLocalPunctuation(_ text: String, isFinal: Bool = true) -> String {
        let originalText = text
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }
        debugLog("🔤 [PUNCT] Input: '\(originalText)'")

        if fillerSettings.removeFillers {
            let fillers = fillerSettings.allEnabledFillers
            for filler in fillers {
                result = result.replacingOccurrences(of: filler, with: "")
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            result = result.replacingOccurrences(of: "  ", with: " ")
            guard !result.isEmpty else { return result }
        }

        let punctuations = ["。", "、", "？", "！", "?", "!", ".", ","]
        for punct in punctuations {
            result = result.replacingOccurrences(of: " \(punct)", with: punct)
            result = result.replacingOccurrences(of: "　\(punct)", with: punct)
        }

        let builtInDictionary = [
            ("クロードコード", "Claude Code"),
            ("ロードコード", "Claude Code"),
            ("ロードコ", "Claude Code"),
            ("ラングラー", "Wrangler"),
            ("クロード", "Claude"),
            ("スーパーベース", "Supabase"),
            ("スパベース", "Supabase"),
            ("グロック", "Grok"),
            ("ジェイソン", "JSON"),
        ]
        for (reading, writing) in builtInDictionary {
            result = result.replacingOccurrences(of: reading, with: writing)
        }

        for entry in dictionaryEntries where entry.isEnabled {
            result = result.replacingOccurrences(of: entry.reading, with: entry.writing)
        }

        let lastChars = String(result.suffix(min(10, result.count)))
        let containsLatin = lastChars.unicodeScalars.contains { $0.isASCII && $0.properties.isAlphabetic }
        if !containsLatin {
            for suffixLen in (2...4).reversed() {
                guard result.count > suffixLen * 2 else { continue }
                let suffix = String(result.suffix(suffixLen))
                let beforeSuffix = String(result.dropLast(suffixLen))
                if beforeSuffix.hasSuffix(suffix) {
                    continue
                }
                for checkLen in (suffixLen + 1)...(suffixLen + 3) {
                    guard beforeSuffix.count >= checkLen else { continue }
                    let candidate = String(beforeSuffix.suffix(checkLen))
                    if candidate.hasPrefix(suffix) {
                        result = beforeSuffix
                        break
                    }
                }
            }
        }

        let midSentenceBreakers = [
            "ありがとうございます", "すみません",
            "こんにちは", "こんばんは", "おはようございます", "お疲れ様です", "お疲れさまです"
        ]

        let sentenceEndings = ["ました", "ません", "でした"]
        for ending in sentenceEndings {
            var searchStart = result.startIndex
            while let range = result.range(of: ending, range: searchStart..<result.endIndex) {
                let afterEnd = range.upperBound
                if afterEnd < result.endIndex {
                    let nextChar = result[afterEnd]
                    let isNextPunctuation = nextChar == "。" || nextChar == "、" || nextChar == "？" || nextChar == "！" || nextChar == "か" || nextChar == "が" || nextChar == "け" || nextChar == "ね" || nextChar == "よ"
                    let suffixAfter = String(result[afterEnd...])
                    let isContinuation = suffixAfter.hasPrefix("でした") || suffixAfter.hasPrefix("っけ") || suffixAfter.hasPrefix("よね") || suffixAfter.hasPrefix("けど") || suffixAfter.hasPrefix("が")
                    if !isNextPunctuation && !isContinuation {
                        result.insert("。", at: afterEnd)
                    }
                }
                searchStart = result.index(after: range.lowerBound)
                if searchStart >= result.endIndex { break }
            }
        }

        let transitionWords = ["とりあえず", "ただ", "でも", "しかし", "ちなみに", "あと", "それから", "それで"]
        for word in transitionWords {
            var offset = 0
            while offset < result.count {
                guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                      let range = result.range(of: word, range: startIdx..<result.endIndex) else { break }
                if range.lowerBound > result.startIndex {
                    let prevIndex = result.index(before: range.lowerBound)
                    let prevChar = result[prevIndex]
                    if word == "ただ" && (prevChar == "い" || prevChar == "わ" || prevChar == "ま") {
                        offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
                        continue
                    }
                    if word == "でも" {
                        if prevChar == "な" || prevChar == "何" || prevChar == "誰" || prevChar == "ど" || prevChar == "い" {
                            offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
                            continue
                        }
                        let sentenceEndPatterns = ["ました", "ません", "です", "ます", "だった", "でした", "ない"]
                        var hasSentenceEnd = false
                        for pattern in sentenceEndPatterns {
                            if result.distance(from: result.startIndex, to: range.lowerBound) >= pattern.count {
                                let patternStart = result.index(range.lowerBound, offsetBy: -pattern.count)
                                let preceding = String(result[patternStart..<range.lowerBound])
                                if preceding == pattern {
                                    hasSentenceEnd = true
                                    break
                                }
                            }
                        }
                        if !hasSentenceEnd {
                            offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
                            continue
                        }
                    }
                    if word == "あと" && (prevChar >= "0" && prevChar <= "9" || prevChar == "分" || prevChar == "時" || prevChar == "日" || prevChar == "年") {
                        offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
                        continue
                    }
                    // 「では」の後に続く場合は句点を挿入しない
                    if result.distance(from: result.startIndex, to: range.lowerBound) >= 2 {
                        let twoBack = result.index(range.lowerBound, offsetBy: -2)
                        let preceding = String(result[twoBack..<range.lowerBound])
                        if preceding == "では" {
                            offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
                            continue
                        }
                    }
                    if prevChar != "。" && prevChar != "、" && prevChar != "？" && prevChar != "！" {
                        result.insert("。", at: range.lowerBound)
                        offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count + 1
                        continue
                    }
                }
                offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
            }
        }
        for phrase in midSentenceBreakers.sorted(by: { $0.count > $1.count }) {
            var offset = 0
            while offset < result.count {
                guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                      let range = result.range(of: phrase, range: startIdx..<result.endIndex) else { break }
                var insertedBefore = false
                if range.lowerBound > result.startIndex {
                    let prevIndex = result.index(before: range.lowerBound)
                    let prevChar = result[prevIndex]
                    if prevChar != "。" && prevChar != "、" && prevChar != "？" && prevChar != "！" {
                        result.insert("。", at: range.lowerBound)
                        insertedBefore = true
                    }
                }
                let newUpperBound = result.index(range.lowerBound, offsetBy: phrase.count + (insertedBefore ? 1 : 0))
                if newUpperBound < result.endIndex {
                    let nextChar = result[newUpperBound]
                    if nextChar != "。" && nextChar != "、" && nextChar != "？" && nextChar != "！" {
                        result.insert("。", at: newUpperBound)
                    }
                }
                offset = result.distance(from: result.startIndex, to: range.lowerBound) + phrase.count + (insertedBefore ? 2 : 1)
            }
        }

        let politeEndingsForMid = ["お願いいたします", "お願いします", "くださいませ", "ください", "でございます", "思います"]
        for phrase in politeEndingsForMid {
            var offset = 0
            while offset < result.count {
                guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                      let range = result.range(of: phrase, range: startIdx..<result.endIndex) else { break }
                let afterEnd = range.upperBound
                if afterEnd < result.endIndex {
                    let nextChar = result[afterEnd]
                    if nextChar != "。" && nextChar != "、" && nextChar != "？" && nextChar != "！" && nextChar != "よ" && nextChar != "ね" && nextChar != "か" && nextChar != "が" && nextChar != "け" {
                        result.insert("。", at: afterEnd)
                        offset = result.distance(from: result.startIndex, to: afterEnd) + 1
                        continue
                    }
                }
                offset = result.distance(from: result.startIndex, to: range.lowerBound) + phrase.count
            }
        }

        let questionEndings = ["ですかね", "ますかね", "ですよね", "ますよね", "でしょうか", "ましょうか", "ですか", "ますか"]
        for ending in questionEndings {
            var offset = 0
            while offset < result.count {
                guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                      let range = result.range(of: ending, range: startIdx..<result.endIndex) else { break }
                let afterEnd = range.upperBound
                if afterEnd < result.endIndex {
                    let nextChar = result[afterEnd]
                    if (ending == "ですか" || ending == "ますか") && (nextChar == "ね" || nextChar == "よ") {
                        offset = result.distance(from: result.startIndex, to: range.lowerBound) + ending.count
                        continue
                    }
                    if nextChar != "。" && nextChar != "、" && nextChar != "？" && nextChar != "！" {
                        result.insert("？", at: afterEnd)
                        offset = result.distance(from: result.startIndex, to: afterEnd) + 1
                        continue
                    }
                } else if afterEnd == result.endIndex {
                    result.append("？")
                    break
                }
                offset = result.distance(from: result.startIndex, to: range.lowerBound) + ending.count
            }
        }

        let commaAfterConjunctions = ["けど", "けれど", "けれども", "だけど", "ですが", "ですけど"]
        for conj in commaAfterConjunctions.sorted(by: { $0.count > $1.count }) {
            var offset = 0
            while offset < result.count {
                guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                      let range = result.range(of: conj, range: startIdx..<result.endIndex) else { break }
                if range.upperBound < result.endIndex {
                    let nextChar = result[range.upperBound]
                    if nextChar != "。" && nextChar != "、" && nextChar != "？" && nextChar != "！" {
                        result.insert("、", at: range.upperBound)
                    }
                }
                offset = result.distance(from: result.startIndex, to: range.lowerBound) + conj.count + 1
            }
        }

        let startersOnlyAtBeginning = ["はい", "いいえ", "うん", "ええ", "そうですね", "なるほど", "おはよう"]
        for starter in startersOnlyAtBeginning {
            if result.hasPrefix(starter) && result.count > starter.count {
                let afterStarter = result.dropFirst(starter.count)
                if let first = afterStarter.first, first != "。" && first != "、" {
                    result = starter + "。" + String(afterStarter)
                }
            }
        }

        if !isFinal {
            while result.hasSuffix("。") {
                result = String(result.dropLast())
            }
        }

        if result != originalText.trimmingCharacters(in: .whitespacesAndNewlines) {
            debugLog("🔤 [PUNCT] Output: '\(result)' (changed)")
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
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            debugLog("❌ No text in clipboard")
            completion()
            return
        }

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            debugLog("📱 Frontmost app: \(frontApp.localizedName ?? "unknown") (bundle: \(frontApp.bundleIdentifier ?? "unknown"), PID: \(frontApp.processIdentifier))")
        } else {
            debugLog("📱 Frontmost app: nil")
        }

        if isSpotlightOpen() {
            debugLog("🔍 Spotlight detected - using AXUIElement API")
            setTextToSpotlight(text)
            completion()
            return
        }

        debugLog("🎯 Sending Cmd+V paste via CGEvent")

        let source = CGEventSource(stateID: .privateState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            debugLog("❌ Failed to create CGEvent")
            completion()
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        usleep(50000)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        debugLog("✅ Paste command sent via CGEvent")
        completion()
    }

    private func isSpotlightOpen() -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight")
        guard let spotlightApp = apps.first else { return false }

        let axApp = AXUIElementCreateApplication(spotlightApp.processIdentifier)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows)

        if result == .success, let windowArray = windows as? [AXUIElement] {
            let isOpen = !windowArray.isEmpty
            if isOpen {
                debugLog("🔍 Spotlight windows found: \(windowArray.count)")
            }
            return isOpen
        }
        return false
    }

    private func setTextToSpotlight(_ text: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight")
        guard let spotlightApp = apps.first else {
            debugLog("❌ Spotlight app not found")
            return
        }

        let axApp = AXUIElementCreateApplication(spotlightApp.processIdentifier)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows)

        guard let windowArray = windows as? [AXUIElement], let window = windowArray.first else {
            debugLog("❌ No Spotlight windows found")
            return
        }

        if let searchField = findSearchField(in: window) {
            let setResult = AXUIElementSetAttributeValue(searchField, kAXValueAttribute as CFString, text as CFTypeRef)
            if setResult == .success {
                debugLog("✅ Text set to Spotlight via AXUIElement")
            } else {
                debugLog("❌ AXUIElement failed (\(setResult.rawValue)), trying CGEvent postToPid")
                sendPasteToSpotlight(pid: spotlightApp.processIdentifier)
            }
        } else {
            debugLog("⚠️ No search field found, trying CGEvent postToPid")
            sendPasteToSpotlight(pid: spotlightApp.processIdentifier)
        }
    }

    private func findSearchField(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 10 { return nil }

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        if let roleStr = role as? String {
            debugLog("🔍 [AX] depth=\(depth) role=\(roleStr)")
            if roleStr == "AXTextField" || roleStr == "AXSearchField" || roleStr == "AXTextArea" {
                return element
            }
        }

        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

        if let childArray = children as? [AXUIElement] {
            for child in childArray {
                if let found = findSearchField(in: child, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    private func sendPasteToSpotlight(pid: pid_t) {
        let source = CGEventSource(stateID: .privateState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            debugLog("❌ Failed to create CGEvent for Spotlight")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.postToPid(pid)
        usleep(50000)
        keyUp.postToPid(pid)

        debugLog("✅ Paste sent to Spotlight PID \(pid) via postToPid")
    }

    func cancelRecording() {
        speechService?.stopRecording()
        isRecording = false
        currentTranscription = ""
        floatingPanel?.hide()
        debugLog("🚫 Recording cancelled")
    }

    @discardableResult
    private func addToHistory(_ text: String, audioData: Data? = nil) -> UUID {
        var audioPath: String? = nil

        if let data = audioData {
            let recordingsDir = getRecordingsDirectory()
            let fileName = "\(UUID().uuidString).wav"
            let filePath = recordingsDir.appendingPathComponent(fileName)

            do {
                try data.write(to: filePath)
                audioPath = filePath.path
                debugLog("🎵 Audio saved: \(filePath.path)")
            } catch {
                debugLog("❌ Failed to save audio: \(error)")
            }
        }

        let record = TranscriptionRecord(text: text, timestamp: Date(), audioPath: audioPath)
        history.insert(record, at: 0)
        if history.count > 20 {
            if let removed = history.last, let path = removed.audioPath {
                try? FileManager.default.removeItem(atPath: path)
                debugLog("🗑️ Old audio removed: \(path)")
            }
            history.removeLast()
        }
        saveHistory()
        debugLog("📚 Added to history: '\(text)' (id: \(record.id))")
        return record.id
    }

    private func getRecordingsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recordingsDir = appSupport.appendingPathComponent("NiceVoice/recordings")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        return recordingsDir
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

    func addToBenchmark(_ record: TranscriptionRecord, expectedText: String) -> Bool {
        guard let audioPath = record.audioPath,
              FileManager.default.fileExists(atPath: audioPath) else {
            debugLog("❌ No audio file for benchmark")
            return false
        }

        let projectRoot = getProjectRoot()
        let benchmarkDir = projectRoot.appendingPathComponent("benchmark-audio")
        let manifestPath = benchmarkDir.appendingPathComponent("manifest.json")

        let id = "user_\(record.id.uuidString.prefix(8).lowercased())"
        let destFileName = "\(id).wav"
        let destPath = benchmarkDir.appendingPathComponent(destFileName)

        do {
            try FileManager.default.copyItem(atPath: audioPath, toPath: destPath.path)
            debugLog("🎵 Audio copied to benchmark: \(destPath.path)")
        } catch {
            debugLog("❌ Failed to copy audio: \(error)")
            return false
        }

        struct TestCase: Codable {
            let id: String
            let text: String
            let audioPath: String
        }

        var testCases: [TestCase] = []
        if let data = try? Data(contentsOf: manifestPath),
           let existing = try? JSONDecoder().decode([TestCase].self, from: data) {
            testCases = existing
        }

        let newCase = TestCase(id: id, text: expectedText, audioPath: "benchmark-audio/\(destFileName)")
        testCases.append(newCase)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(testCases)
            try data.write(to: manifestPath)
            debugLog("✅ Added to benchmark: \(id)")
            return true
        } catch {
            debugLog("❌ Failed to update manifest: \(error)")
            return false
        }
    }

    private func getProjectRoot() -> URL {
        var url = URL(fileURLWithPath: #file)
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private func getRecordedAudioDataFromActiveService() -> Data? {
        if useSpeechAnalyzer {
            if #available(macOS 26.0, *), let service = speechAnalyzerService as? SpeechAnalyzerService {
                return service.getRecordedAudioData()
            }
        }
        return speechService?.getRecordedAudioData()
    }

    private func clearActiveServiceAudioBuffers() {
        if useSpeechAnalyzer {
            if #available(macOS 26.0, *), let service = speechAnalyzerService as? SpeechAnalyzerService {
                service.clearAudioBuffers()
            }
        }
        speechService?.clearAudioBuffers()
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

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func saveUsageStats() {
        save(usageStats, forKey: UserDefaultsKey.usageStats)
    }

    private func loadUsageStats() {
        if let stats: UsageStats = load(forKey: UserDefaultsKey.usageStats) {
            usageStats = stats
            usageStats.resetTodayIfNeeded()
        }
    }

    private func saveDictionary() {
        save(dictionaryEntries, forKey: UserDefaultsKey.dictionary)
    }

    private func loadDictionary() {
        if let entries: [DictionaryEntry] = load(forKey: UserDefaultsKey.dictionary) {
            dictionaryEntries = entries
            deduplicateDictionary()
            sortDictionary()
        }
    }

    private func saveFillerSettings() {
        save(fillerSettings, forKey: UserDefaultsKey.fillerSettings)
    }

    private func loadFillerSettings() {
        if var settings: FillerSettings = load(forKey: UserDefaultsKey.fillerSettings) {
            var needsSave = false

            let fillersToMigrate: Set<String> = ["なんか", "まあ", "まぁ", "やっぱり", "やっぱ"]
            let migratedFillers = settings.enabledPresets.intersection(fillersToMigrate)
            if !migratedFillers.isEmpty {
                settings.enabledPresets.subtract(fillersToMigrate)
                settings.ambiguousFillers.formUnion(fillersToMigrate)
                debugLog("🔄 Migrated fillers to ambiguous: \(migratedFillers)")
                needsSave = true
            }

            let requiredAmbiguous: Set<String> = [
                "あの", "その", "ちょっと",
                "なんか", "まあ", "まぁ",
                "こう", "ほら",
                "やっぱり", "やっぱ"
            ]
            let missingAmbiguous = requiredAmbiguous.subtracting(settings.ambiguousFillers)
            if !missingAmbiguous.isEmpty {
                settings.ambiguousFillers.formUnion(missingAmbiguous)
                debugLog("🔄 Added missing ambiguous fillers: \(missingAmbiguous)")
                needsSave = true
            }

            if needsSave {
                save(settings, forKey: UserDefaultsKey.fillerSettings)
            }
            fillerSettings = settings
        }
    }

    private func saveHistory() {
        save(history, forKey: UserDefaultsKey.history)
        debugLog("💾 History saved (\(history.count) items)")
    }

    private func loadHistory() {
        if let records: [TranscriptionRecord] = load(forKey: UserDefaultsKey.history) {
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
    private let onRecognitionError: ((String) -> Void)?
    private var lastTranscription = ""

    private var savedText = ""
    private var lastRecognizedText = ""

    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var recordingFormat: AVAudioFormat?

    private var lastVoiceTime = Date()
    private let silenceThreshold: Float = 0.01
    private let silenceDuration: TimeInterval = 0.8
    private var confirmedOnSilence = false

    init(
        onTranscription: @escaping (String, Bool) -> Void,
        onRealtimeInput: @escaping (String, String) -> Void,
        onRecognitionError: ((String) -> Void)? = nil
    ) {
        self.onTranscription = onTranscription
        self.onRealtimeInput = onRealtimeInput
        self.onRecognitionError = onRecognitionError
    }

    func startRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        lastTranscription = ""
        savedText = ""
        lastRecognizedText = ""
        lastVoiceTime = Date()
        confirmedOnSilence = false
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
            guard let self else { return }
            recognitionRequest.append(buffer)
            if let copy = self.copyBuffer(buffer) {
                self.audioBuffers.append(copy)
            }

            let rms = self.calculateRMS(buffer)
            let now = Date()
            if rms > self.silenceThreshold {
                self.lastVoiceTime = now
                self.confirmedOnSilence = false
            } else {
                let elapsed = now.timeIntervalSince(self.lastVoiceTime)
                if elapsed >= self.silenceDuration && !self.lastRecognizedText.isEmpty && !self.confirmedOnSilence {
                    self.savedText = self.lastRecognizedText
                    self.confirmedOnSilence = true
                    debugLog("🔇 [VAD] Confirmed on silence: '\(self.savedText)'")
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        debugLog("🔍 [DEBUG] Starting recognition task")
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let error {
                debugLog("🔍 [DEBUG] Recognition error: \(error)")
                let nsError = error as NSError
                if nsError.domain == "kLSRErrorDomain" && nsError.code == 201 {
                    self.onRecognitionError?("音声認識が無効です: システム設定で Siri を有効にするか、Chrome を起動してください")
                }
            }
            if let result {
                let currentText = result.bestTranscription.formattedString
                let oldText = self.lastTranscription
                debugLog("🔍 [DEBUG] Recognition: current='\(currentText)', saved='\(self.savedText)', isFinal=\(result.isFinal)")

                self.lastRecognizedText = currentText

                let displayText: String
                if self.savedText.isEmpty {
                    displayText = currentText
                    debugLog("🔍 [MERGE] savedText empty, using currentText")
                } else {
                    // 句読点・空白を除去して比較（SFSpeechRecognizerが句読点を付けたり外したりするため）
                    let savedNormalized = self.savedText.filter { !$0.isPunctuation && !$0.isWhitespace }
                    let currentNormalized = currentText.filter { !$0.isPunctuation && !$0.isWhitespace }

                    let commonLen = self.commonPrefixLength(savedNormalized, currentNormalized)
                    let threshold = Int(Double(savedNormalized.count) * 0.7)
                    debugLog("🔍 [MERGE] savedText='\(self.savedText)' (\(self.savedText.count)), currentText='\(currentText)' (\(currentText.count)), normalized: saved='\(savedNormalized)' current='\(currentNormalized)', commonLen=\(commonLen), threshold=\(threshold)")

                    let isShortFragment = savedNormalized.count <= 5
                    let isLikelyCorrection = isShortFragment && currentNormalized.count >= savedNormalized.count * 2 && commonLen < 2

                    // savedText の正規化版が currentText の正規化版に含まれているか（修正判定）
                    let savedContainedInCurrent = currentNormalized.contains(savedNormalized) || savedNormalized.hasPrefix(String(currentNormalized.prefix(savedNormalized.count)))

                    // currentText の方が長い、または同程度の長さで共通部分がある場合は修正と判定
                    // SFSpeechRecognizer は全体を再認識するので、より長い結果の方が正確
                    let currentIsLongerOrSimilar = currentNormalized.count >= savedNormalized.count
                    let hasSignificantOverlap = commonLen >= min(savedNormalized.count, currentNormalized.count) / 3

                    if isLikelyCorrection {
                        displayText = currentText
                        debugLog("🔍 [MERGE] Treating as correction (short fragment replaced)")
                    } else if commonLen >= threshold || savedContainedInCurrent {
                        displayText = currentText
                        debugLog("🔍 [MERGE] Using currentText (continuation or correction)")
                    } else if currentIsLongerOrSimilar && hasSignificantOverlap {
                        displayText = currentText
                        debugLog("🔍 [MERGE] Using currentText (longer/similar with overlap)")
                    } else {
                        displayText = self.savedText + " " + currentText
                        debugLog("🔍 [MERGE] Concatenating: '\(displayText)'")
                    }
                }

                self.lastTranscription = displayText
                self.onTranscription(displayText, result.isFinal)
                self.onRealtimeInput(oldText, displayText)
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

    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        let data = channelData[0]
        for i in 0..<frameLength {
            let sample = data[i]
            sum += sample * sample
        }
        return sqrt(sum / Float(frameLength))
    }

    private func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var count = 0
        for (c1, c2) in zip(a, b) {
            if c1 == c2 { count += 1 } else { break }
        }
        return count
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
                debugLog("📝 Chrome result: '\(text)' (final: \(isFinal))")
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

enum ShortcutKey: String, CaseIterable {
    case fn = "fn"
    case leftShift = "leftShift"
    case rightShift = "rightShift"
    case leftControl = "leftControl"
    case rightControl = "rightControl"
    case leftOption = "leftOption"
    case rightOption = "rightOption"
    case leftCommand = "leftCommand"
    case rightCommand = "rightCommand"

    var displayName: String {
        switch self {
        case .fn: return "fn"
        case .leftShift: return "左 Shift"
        case .rightShift: return "右 Shift"
        case .leftControl: return "左 Control"
        case .rightControl: return "右 Control"
        case .leftOption: return "左 Option"
        case .rightOption: return "右 Option"
        case .leftCommand: return "左 Command"
        case .rightCommand: return "右 Command"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .fn: return 63
        case .leftShift: return 56
        case .rightShift: return 60
        case .leftControl: return 59
        case .rightControl: return 62
        case .leftOption: return 58
        case .rightOption: return 61
        case .leftCommand: return 55
        case .rightCommand: return 54
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .leftShift, .rightShift: return .shift
        case .leftControl, .rightControl: return .control
        case .leftOption, .rightOption: return .option
        case .leftCommand, .rightCommand: return .command
        }
    }
}

@available(macOS 26.0, *)
final class SpeechAnalyzerService {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var isRunning = false
    private var transcriptionTask: Task<Void, Never>?
    private var analyzerTask: Task<Void, Error>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var recordingFormat: AVAudioFormat?

    private let onTranscription: (String, Bool) -> Void
    private let onError: (String) -> Void
    private let onStatusChange: ((String) -> Void)?
    private let onAudioLevel: ((Float) -> Void)?

    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    init(
        onTranscription: @escaping (String, Bool) -> Void,
        onError: @escaping (String) -> Void,
        onStatusChange: ((String) -> Void)? = nil,
        onAudioLevel: ((Float) -> Void)? = nil
    ) {
        self.onTranscription = onTranscription
        self.onError = onError
        self.onStatusChange = onStatusChange
        self.onAudioLevel = onAudioLevel
    }

    func start() async {
        let locale = Locale(identifier: "ja-JP")
        let tempTranscriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        do {
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [tempTranscriber]) {
                onStatusChange?("音声認識モデルをダウンロード中...")
                try await downloader.downloadAndInstall()
            }
        } catch {
            debugLog("❌ Model download failed: \(error)")
            onError("モデルのダウンロードに失敗: \(error.localizedDescription)")
            return
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [tempTranscriber])
        onStatusChange?("準備完了")
        debugLog("✅ SpeechAnalyzer initialized with Japanese locale")
        if let format = analyzerFormat {
            debugLog("🔊 Analyzer format: \(format.sampleRate)Hz, \(format.channelCount)ch")
        }
    }

    func startRecording() {
        guard !isRunning else { return }
        guard let analyzerFormat else {
            onError("SpeechAnalyzer が初期化されていません")
            return
        }

        isRunning = true
        audioBuffers = []

        let locale = Locale(identifier: "ja-JP")
        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        guard let transcriber else {
            onError("SpeechTranscriber の作成に失敗しました")
            isRunning = false
            return
        }
        analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzer else {
            onError("SpeechAnalyzer の作成に失敗しました")
            isRunning = false
            return
        }
        debugLog("🔍 [DEBUG] Created new SpeechTranscriber and SpeechAnalyzer")

        audioEngine = AVAudioEngine()

        guard let audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        recordingFormat = inputFormat
        debugLog("🔊 Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        if inputFormat.sampleRate != analyzerFormat.sampleRate || inputFormat.channelCount != analyzerFormat.channelCount {
            audioConverter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
            debugLog("🔄 Audio converter created (format mismatch)")
        } else {
            debugLog("✅ No audio conversion needed")
        }

        let inputStream = AsyncStream<AnalyzerInput> { continuation in
            self.inputContinuation = continuation
        }

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            var accumulated = ""
            debugLog("🔍 [DEBUG] Transcription task started, waiting for results...")

            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    debugLog("🔍 [DEBUG] SpeechAnalyzer result: '\(text)' (final: \(isFinal))")

                    if isFinal {
                        accumulated += text
                    }

                    let outputText = isFinal ? accumulated : text
                    await MainActor.run {
                        self.onTranscription(outputText, isFinal)
                    }
                }
                debugLog("🔍 [DEBUG] Transcription loop ended normally")
            } catch {
                await MainActor.run {
                    debugLog("❌ Transcription error: \(error)")
                    self.onError("音声認識エラー: \(error.localizedDescription)")
                }
            }
        }

        analyzerTask = Task {
            try await analyzer.start(inputSequence: inputStream)
        }

        var bufferCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isRunning else { return }
            bufferCount += 1
            if bufferCount % 50 == 1 {
                debugLog("🔊 [DEBUG] Audio buffer #\(bufferCount), frames: \(buffer.frameLength)")
            }

            if let copy = self.copyBuffer(buffer) {
                self.audioBuffers.append(copy)
            }

            if let channelData = buffer.floatChannelData {
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameLength {
                    let sample = channelData[0][i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(frameLength))
                let level = min(1.0, rms * 5)
                DispatchQueue.main.async {
                    self.onAudioLevel?(level)
                }
            }

            if let converter = self.audioConverter, let targetFormat = self.analyzerFormat {
                let ratio = targetFormat.sampleRate / inputFormat.sampleRate
                let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
                    if bufferCount == 1 {
                        debugLog("❌ [DEBUG] Failed to create output buffer")
                    }
                    return
                }

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if status == .error {
                    if bufferCount == 1 {
                        debugLog("❌ [DEBUG] Conversion error: \(error?.localizedDescription ?? "unknown")")
                    }
                    return
                }

                if bufferCount == 1 {
                    debugLog("🔊 [DEBUG] Converted buffer: \(convertedBuffer.frameLength) frames, format: \(convertedBuffer.format)")
                }
                self.inputContinuation?.yield(AnalyzerInput(buffer: convertedBuffer))
            } else {
                self.inputContinuation?.yield(AnalyzerInput(buffer: buffer))
            }
        }

        usleep(100000)

        do {
            try audioEngine.start()
            debugLog("🎙️ SpeechAnalyzer recording started")
        } catch {
            debugLog("❌ Audio engine failed to start: \(error)")
            onError("オーディオエンジンの起動に失敗しました")
            isRunning = false
        }
    }

    func stopRecording() {
        guard isRunning else { return }
        isRunning = false

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        inputContinuation?.finish()
        inputContinuation = nil

        Task {
            debugLog("🔍 [DEBUG] Calling finalizeAndFinishThroughEndOfInput...")
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            debugLog("🔍 [DEBUG] finalizeAndFinishThroughEndOfInput completed")

            try? await Task.sleep(for: .milliseconds(500))

            transcriptionTask?.cancel()
            transcriptionTask = nil
            analyzerTask?.cancel()
            analyzerTask = nil
        }

        debugLog("🎙️ SpeechAnalyzer recording stopped")
    }

    func stop() {
        stopRecording()
        analyzer = nil
        transcriber = nil
        audioConverter = nil
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
            debugLog("❌ No audio buffers to convert (SpeechAnalyzer)")
            return nil
        }

        let totalFrames = audioBuffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else {
            debugLog("❌ Audio buffers are empty (SpeechAnalyzer)")
            return nil
        }

        debugLog("🎵 Converting \(audioBuffers.count) buffers (\(totalFrames) frames) to WAV (SpeechAnalyzer)")

        let wavHeader = createWAVHeader(
            sampleRate: UInt32(format.sampleRate),
            channels: UInt16(format.channelCount),
            totalFrames: UInt32(totalFrames)
        )

        var audioData = Data()
        audioData.append(wavHeader)

        for buffer in audioBuffers {
            if let floatData = buffer.floatChannelData {
                for frame in 0..<Int(buffer.frameLength) {
                    for channel in 0..<Int(format.channelCount) {
                        let sample = floatData[channel][frame]
                        let clipped = max(-1.0, min(1.0, sample))
                        var intSample = Int16(clipped * Float(Int16.max))
                        audioData.append(Data(bytes: &intSample, count: 2))
                    }
                }
            }
        }

        debugLog("🎵 WAV data created: \(audioData.count) bytes (SpeechAnalyzer)")
        return audioData
    }

    private func createWAVHeader(sampleRate: UInt32, channels: UInt16, totalFrames: UInt32) -> Data {
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = totalFrames * UInt32(channels) * UInt32(bitsPerSample / 8)
        let fileSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        header.append(contentsOf: "data".utf8)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        return header
    }

    func clearAudioBuffers() {
        audioBuffers = []
    }
}

final class KeyMonitor {
    private var monitor: Any?
    private var isKeyPressed = false
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void
    private var shortcutKey: ShortcutKey

    init(shortcutKey: ShortcutKey = .fn, onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.shortcutKey = shortcutKey
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        startMonitoring()
    }

    func updateShortcutKey(_ newKey: ShortcutKey) {
        guard newKey != shortcutKey else { return }
        shortcutKey = newKey
        isKeyPressed = false
        stopMonitoring()
        startMonitoring()
        debugLog("🔄 Shortcut key changed to: \(newKey.displayName)")
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func startMonitoring() {
        debugLog("🔍 [DEBUG] KeyMonitor startMonitoring called for: \(shortcutKey.displayName)")
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let keyPressed = self.isShortcutKeyPressed(event: event)

            if keyPressed && !self.isKeyPressed {
                debugLog("🔍 [DEBUG] \(self.shortcutKey.displayName) key DOWN detected")
                self.isKeyPressed = true
                DispatchQueue.main.async {
                    debugLog("🔍 [DEBUG] Calling onKeyDown callback")
                    self.onKeyDown()
                }
            } else if !keyPressed && self.isKeyPressed {
                debugLog("🔍 [DEBUG] \(self.shortcutKey.displayName) key UP detected")
                self.isKeyPressed = false
                DispatchQueue.main.async {
                    debugLog("🔍 [DEBUG] Calling onKeyUp callback")
                    self.onKeyUp()
                }
            }
        }

        if monitor == nil {
            debugLog("⚠️ アクセシビリティ権限が必要です - monitor is nil")
        } else {
            debugLog("✅ KeyMonitor started successfully for: \(shortcutKey.displayName)")
        }
    }

    private func isShortcutKeyPressed(event: NSEvent) -> Bool {
        let hasModifier = event.modifierFlags.contains(shortcutKey.modifierFlag)
        if shortcutKey == .fn {
            return hasModifier
        }
        return hasModifier && event.keyCode == shortcutKey.keyCode
    }

    deinit {
        stopMonitoring()
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
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 40),
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
        let panelWidth: CGFloat = 80
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.minY + 30

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

    private var isError: Bool {
        appState.errorMessage != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let error = appState.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            } else {
                EqualizerView(level: appState.audioLevels.last ?? 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.7), in: Capsule())
    }
}

struct EqualizerView: View {
    let level: Float
    private let barCount = 10
    @State private var barHeights: [CGFloat] = Array(repeating: 2, count: 10)

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.5), .cyan, .cyan.opacity(0.5)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 2.5, height: barHeights[index])
                    .animation(.easeOut(duration: 0.06), value: barHeights[index])
            }
        }
        .frame(height: 24, alignment: .center)
        .onChange(of: level) { _, newLevel in
            updateBars(level: newLevel)
        }
        .onAppear {
            updateBars(level: level)
        }
    }

    private func updateBars(level: Float) {
        for i in 0..<barCount {
            let randomFactor = Float.random(in: 0.5...1.5)
            let height = CGFloat(level * randomFactor * 40) + 2
            barHeights[i] = min(24, max(2, height))
        }
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
    @State private var showBenchmarkSheet = false
    @State private var benchmarkRecord: TranscriptionRecord?
    @State private var expectedText = ""

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
                            onCopy: { appState.copyHistoryItem(record.text) },
                            onAddToBenchmark: { rec in
                                benchmarkRecord = rec
                                expectedText = rec.text
                                showBenchmarkSheet = true
                            }
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
        .sheet(isPresented: $showBenchmarkSheet) {
            BenchmarkAddSheet(
                recognizedText: benchmarkRecord?.text ?? "",
                expectedText: $expectedText,
                onAdd: {
                    if let record = benchmarkRecord {
                        _ = appState.addToBenchmark(record, expectedText: expectedText)
                    }
                    showBenchmarkSheet = false
                },
                onCancel: {
                    showBenchmarkSheet = false
                }
            )
        }
    }
}

struct BenchmarkAddSheet: View {
    let recognizedText: String
    @Binding var expectedText: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("ベンチマークに追加")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("認識結果:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(recognizedText)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("正解テキスト:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $expectedText)
                    .frame(height: 80)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }

            HStack {
                Button("キャンセル", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("追加", action: onAdd)
                    .keyboardShortcut(.defaultAction)
                    .disabled(expectedText.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

struct RecentTranscriptionRow: View {
    let record: TranscriptionRecord
    let isHovered: Bool
    let onCopy: () -> Void
    var onAddToBenchmark: ((TranscriptionRecord) -> Void)? = nil
    @StateObject private var audioPlayer = AudioPlayerManager()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if record.hasAudio {
                    if let path = record.audioPath {
                        audioPlayer.toggle(url: URL(fileURLWithPath: path), id: record.id)
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(record.hasAudio ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: record.hasAudio ? (audioPlayer.isPlaying ? "stop.fill" : "play.fill") : "text.bubble")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(record.hasAudio ? .blue : .secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!record.hasAudio)

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
        .contextMenu {
            Button {
                onCopy()
            } label: {
                Label("コピー", systemImage: "doc.on.doc")
            }

            if record.hasAudio {
                Button {
                    if let path = record.audioPath {
                        audioPlayer.toggle(url: URL(fileURLWithPath: path), id: record.id)
                    }
                } label: {
                    Label(audioPlayer.isPlaying ? "停止" : "再生", systemImage: audioPlayer.isPlaying ? "stop.fill" : "play.fill")
                }
            }

            if record.hasAudio, let onAdd = onAddToBenchmark {
                Button {
                    onAdd(record)
                } label: {
                    Label("ベンチマークに追加", systemImage: "chart.bar.doc.horizontal")
                }
            }
        }
    }
}

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentPlayingId: UUID?
    private var player: AVAudioPlayer?

    func play(url: URL, id: UUID) {
        stop()
        guard FileManager.default.fileExists(atPath: url.path) else {
            debugLog("🔊 Audio file not found: \(url.path)")
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            if player?.play() == true {
                isPlaying = true
                currentPlayingId = id
            }
        } catch {
            debugLog("🔊 Playback error: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        isPlaying = false
        currentPlayingId = nil
    }

    func toggle(url: URL, id: UUID) {
        if currentPlayingId == id && isPlaying {
            stop()
        } else {
            play(url: url, id: id)
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentPlayingId = nil
        }
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

struct AnimatedWaveformView: View {
    @State private var animating = false
    let barCount = 5
    let barWidth: CGFloat = 2
    let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.blue)
                    .frame(width: barWidth, height: animating ? CGFloat.random(in: 4...14) : 6)
                    .animation(
                        .easeInOut(duration: 0.3)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

struct ModernHistoryRowView: View {
    let record: TranscriptionRecord
    var appState: AppState
    @ObservedObject var audioPlayer: AudioPlayerManager
    @State private var isHovered = false
    @State private var showCopiedFeedback = false
    @State private var isTapped = false

    private var isPlaying: Bool {
        audioPlayer.currentPlayingId == record.id && audioPlayer.isPlaying
    }

    private func handleAudioTap() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            isTapped = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isTapped = false
            }
        }

        guard let path = record.audioPath else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            debugLog("🎵 Audio file not found: \(path)")
            return
        }
        audioPlayer.toggle(url: url, id: record.id)
    }

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
                    .fill(Color.blue.opacity(isPlaying ? 0.25 : (isTapped ? 0.2 : 0.1)))
                    .frame(width: 40, height: 40)
                if isPlaying {
                    AnimatedWaveformView()
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(record.hasAudio ? .blue : .blue.opacity(0.3))
                }
            }
            .scaleEffect(isTapped ? 0.9 : 1.0)
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture()
                    .onEnded { _ in
                        handleAudioTap()
                    }
            )
            .help(record.hasAudio ? (isPlaying ? "停止" : "再生") : "音声なし")

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
    @StateObject private var audioPlayer = AudioPlayerManager()
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
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredHistory) { record in
                            ModernHistoryRowView(record: record, appState: appState, audioPlayer: audioPlayer)
                                .padding(.horizontal, 20)
                                .contextMenu {
                                    Button {
                                        appState.copyHistoryItem(record.text)
                                    } label: {
                                        Label("コピー", systemImage: "doc.on.doc")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            appState.removeHistoryItem(record)
                                        }
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
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

struct ShortcutKeyButton: View {
    let key: ShortcutKey
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .medium))
                Text(key.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var iconName: String {
        switch key {
        case .fn: return "fn"
        case .leftShift, .rightShift: return "shift"
        case .leftControl, .rightControl: return "control"
        case .leftOption, .rightOption: return "option"
        case .leftCommand, .rightCommand: return "command"
        }
    }
}

struct SettingsContentView: View {
    var appState: AppState
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("shortcutKey") private var shortcutKeyRaw = ShortcutKey.fn.rawValue
    @State private var fillerSettings: FillerSettings
    @State private var newFiller = ""
    @State private var animateContent = false

    private var selectedShortcutKey: ShortcutKey {
        ShortcutKey(rawValue: shortcutKeyRaw) ?? .fn
    }

    private let presetFillers = ["えー", "あー", "うーん", "まあ", "なんか", "やっぱり"]

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

                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ショートカットキー")
                            .font(.body)
                        Text("録音を開始・停止するキー")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            ForEach(ShortcutKey.allCases, id: \.self) { key in
                                ShortcutKeyButton(
                                    key: key,
                                    isSelected: selectedShortcutKey == key,
                                    action: {
                                        shortcutKeyRaw = key.rawValue
                                        appState.keyMonitor?.updateShortcutKey(key)
                                    }
                                )
                            }
                        }
                    }
                }
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 10)

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

                                Divider()
                                    .padding(.vertical, 8)

                                SettingsToggleRow(
                                    title: "AI でフィラーを識別",
                                    description: "「あの」「その」など文脈依存のフィラーを Claude Haiku 4.5 で判定します",
                                    isOn: $fillerSettings.useSmartFillerDetection
                                )
                                .onChange(of: fillerSettings.useSmartFillerDetection) { _, _ in
                                    appState.updateFillerSettings(fillerSettings)
                                }
                            }
                        }
                    }
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 10)

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

final class FillerDetectionService {
    private static let configDirectory: URL = {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NiceVoice")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }()

    private static let configPath: URL = {
        configDirectory.appendingPathComponent("config.json")
    }()

    private struct Config: Codable {
        var anthropicAPIKey: String?
    }

    static func getAPIKey() -> String? {
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return nil
        }
        return config.anthropicAPIKey
    }

    static func setupAPIKey(from devVarsPath: String) {
        guard let content = try? String(contentsOfFile: devVarsPath, encoding: .utf8) else {
            debugLog("⚠️ .dev.vars not found at \(devVarsPath)")
            return
        }

        var anthropicKey: String?
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0] == "ANTHROPIC_API_KEY" {
                anthropicKey = String(parts[1])
                break
            }
        }

        guard let key = anthropicKey else {
            debugLog("⚠️ ANTHROPIC_API_KEY not found in .dev.vars")
            return
        }

        let config = Config(anthropicAPIKey: key)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configPath)
            debugLog("✅ Anthropic API key configured")
        }
    }

    static func detectFillers(in text: String, ambiguousWords: Set<String>) async -> [String] {
        guard let apiKey = getAPIKey(), !apiKey.isEmpty else {
            debugLog("⚠️ Anthropic API key not configured")
            return []
        }

        let wordsInText = ambiguousWords.filter { text.contains($0) }
        guard !wordsInText.isEmpty else {
            return []
        }

        let targetWords = wordsInText.sorted().joined(separator: "、")
        let prompt = """
        以下の単語がフィラー（言い淀み）かどうか判定してください。

        【検査対象】
        \(targetWords)

        【判定基準】
        - フィラー: 話し言葉で無意識に挿入される言葉
          例: 「登録していて、あの支払いも」の「あの」（特定の対象を指していない）
          例: 「なんか、えーと」「あの、その」
        - 非フィラー: 特定の対象を指す指示詞として使われている
          例: 「あの人が来た」「その本を読んだ」「なんかいい感じ」

        【ヒント】
        - 読点（、）の直後に来る「あの」「その」はフィラーの可能性が高い
        - 「あの＋名詞」の形でも、文脈上特定の対象を指していなければフィラー

        【入力】
        \(text)

        【出力形式】
        検査対象の中でフィラーと判定したものだけをカンマ区切りで出力。説明不要。
        フィラーがなければ: なし
        """

        do {
            let fillers = try await callClaudeAPI(prompt: prompt, apiKey: apiKey)
            return fillers.filter { wordsInText.contains($0) }
        } catch {
            debugLog("❌ Filler detection error: \(error)")
            return []
        }
    }

    private static func callClaudeAPI(prompt: String, apiKey: String) async throws -> [String] {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 5

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 100,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "FillerDetection", code: 1, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw NSError(domain: "FillerDetection", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if text.trimmingCharacters(in: .whitespacesAndNewlines) == "なし" {
            return []
        }

        let fillers = text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        debugLog("🔍 Smart filler detection: \(fillers)")
        return fillers
    }
}
