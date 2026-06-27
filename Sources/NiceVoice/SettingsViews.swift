import SwiftUI
import AVFoundation
import AppKit
import Carbon

struct ShortcutKeyButton: View {
    let key: ShortcutKey
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    private let selectedGradient = LinearGradient(
        colors: [.purple, .indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .medium))
                Text(key.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(selectedGradient.opacity(0.2)) : AnyShapeStyle(Color.secondary.opacity(isHovered ? 0.12 : 0.06)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? AnyShapeStyle(selectedGradient) : AnyShapeStyle(Color.secondary.opacity(0.15)),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .shadow(
                color: isSelected ? .purple.opacity(0.3) : (isHovered ? .black.opacity(0.08) : .clear),
                radius: isSelected ? 8 : 4,
                y: isSelected ? 4 : 2
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var iconName: String {
        switch key {
        case .space: return "keyboard"
        case .fn: return "fn"
        case .custom: return "keyboard"
        case .leftShift, .rightShift: return "shift"
        case .leftControl, .rightControl: return "control"
        case .leftOption, .rightOption: return "option"
        case .leftCommand, .rightCommand: return "command"
        }
    }
}

enum SettingsStyle {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .controlBackgroundColor)
    static let contentBackground = Color(nsColor: .windowBackgroundColor)
    static let divider = Color.secondary.opacity(0.18)
    static let rowHover = Color.white.opacity(0.05)
}

struct SettingsContentView: View {
    var appState: AppState
    let selectedPane: PreferencesTab
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("shortcutKey") private var shortcutKeyRaw = ShortcutKey.fn.rawValue
    @AppStorage("customShortcut") private var customShortcutRaw = CustomShortcut.defaultValue.rawValue
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    @AppStorage("transcriptionLanguageMode") private var transcriptionLanguageModeRaw = TranscriptionLanguageMode.defaultMode.rawValue
    @State private var fillerSettings: FillerSettings
    @State private var isCapturingCustomShortcut = false
    @State private var captureMonitor: Any?

    private var selectedShortcutKey: ShortcutKey {
        ShortcutKey(rawValue: shortcutKeyRaw) ?? .fn
    }

    private var selectedCustomShortcut: CustomShortcut {
        CustomShortcut(rawValue: customShortcutRaw) ?? .defaultValue
    }

    private var selectedLanguageMode: TranscriptionLanguageMode {
        TranscriptionLanguageMode(rawValue: transcriptionLanguageModeRaw) ?? .defaultMode
    }

    init(appState: AppState, selectedPane: PreferencesTab) {
        self.appState = appState
        self.selectedPane = selectedPane
        _fillerSettings = State(initialValue: appState.fillerSettings)
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 26) {
                    paneContent
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: 620, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.top, 58)
            .padding(.bottom, 30)
        }
        .background(SettingsStyle.contentBackground)
        .onDisappear {
            stopShortcutCapture()
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .general:
            generalPane
        case .transcription:
            transcriptionPane
        case .voice:
            VoiceEnrollmentSection()
        case .about:
            aboutPane
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggleRow(
                title: "メニューバーに常駐する",
                description: "オフにすると Dock からのみ起動できます",
                isOn: $showInMenuBar
            )

            SectionDivider()

            SettingsControlRow(title: "ショートカットキー", description: shortcutDescription) {
                Picker("", selection: $shortcutKeyRaw) {
                    ForEach(ShortcutKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
                .onChange(of: shortcutKeyRaw) { _, newValue in
                    let key = ShortcutKey(rawValue: newValue) ?? .fn
                    appState.updateShortcutSelection(key)
                }
            }

            if let issue = appState.shortcutMonitoringIssue {
                SectionDivider()
                ShortcutIssueBanner(issue: issue)
            }

            if selectedShortcutKey == .custom {
                SectionDivider()

                SettingsControlRow(title: "現在の組み合わせ", description: "modifier + key を押してください。Esc でキャンセルします") {
                    Button(isCapturingCustomShortcut ? "キー入力待ち..." : selectedCustomShortcut.displayName) {
                        if isCapturingCustomShortcut {
                            stopShortcutCapture()
                        } else {
                            startShortcutCapture()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            SectionDivider()

            SettingsControlRow(title: "表示言語", description: "アプリ内の表示言語を選択します") {
                Picker("", selection: $appLanguageRaw) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
                .onChange(of: appLanguageRaw) { _, newValue in
                    let lang = AppLanguage(rawValue: newValue) ?? .system
                    lang.apply()
                }
            }

            SectionDivider()

            PermissionStatusView()

            SectionDivider()

            HistoryManagementSection(appState: appState)
        }
    }

    private var transcriptionPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsControlRow(title: "認識する言語", description: selectedLanguageMode.description) {
                Picker("", selection: $transcriptionLanguageModeRaw) {
                    ForEach(TranscriptionLanguageMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .onChange(of: transcriptionLanguageModeRaw) { _, newValue in
                    appState.transcriptionLanguageMode = TranscriptionLanguageMode(rawValue: newValue) ?? .defaultMode
                    appState.setupTranscriptionService()
                    Task {
                        await appState.reinitializeAfterEngineChange()
                    }
                }
            }

            SectionDivider()

            SettingsToggleRow(
                title: "句読点を自動で付ける",
                description: "。、？を適切な位置に追加して読みやすくします",
                isOn: $fillerSettings.addPunctuation
            )
            .onChange(of: fillerSettings.addPunctuation) { _, _ in
                appState.updateFillerSettings(fillerSettings)
            }

            SectionDivider()

            SettingsToggleRow(
                title: "言い淀み・繰り返しを整理",
                description: "同じ言葉を繰り返した場合に1回にまとめます",
                isOn: $fillerSettings.removeRepetition
            )
            .onChange(of: fillerSettings.removeRepetition) { _, _ in
                appState.updateFillerSettings(fillerSettings)
            }

            SectionDivider()

            SettingsToggleRow(
                title: "フィラーを除去する",
                description: "「えー」「あー」などの言葉を自動で除去します",
                isOn: $fillerSettings.removeFillers
            )
            .onChange(of: fillerSettings.removeFillers) { _, _ in
                appState.updateFillerSettings(fillerSettings)
            }
        }
    }

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            UpdateSettingsContentView()

            SectionDivider()

            BetaAccessContentView()
        }
    }

    private var shortcutDescription: String {
        if selectedShortcutKey.usesLongPressBehavior {
            return "Space は長押しで録音し、短く押すと通常のスペースを入力します"
        }
        if selectedShortcutKey.usesCustomKeyCombinationBehavior {
            return "\(selectedCustomShortcut.displayName) を押している間だけ録音します。このショートカットだけが有効です"
        }
        return "選んだキーを押している間だけ録音します。このショートカットだけが有効です"
    }

    private func startShortcutCapture() {
        stopShortcutCapture()
        isCapturingCustomShortcut = true
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopShortcutCapture()
                return nil
            }

            guard let shortcut = CustomShortcut.capture(from: event) else {
                return nil
            }

            customShortcutRaw = shortcut.rawValue
            shortcutKeyRaw = ShortcutKey.custom.rawValue
            appState.updateCustomShortcut(shortcut)
            appState.updateShortcutSelection(.custom)
            stopShortcutCapture()
            return nil
        }
    }

    private func stopShortcutCapture() {
        isCapturingCustomShortcut = false
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
            self.captureMonitor = nil
        }
    }
}

enum EnrollmentStatus: Equatable {
    case idle
    case recording
    case processing
    case success
    case failed(String)
}

struct HistoryManagementSection: View {
    var appState: AppState
    @State private var showingClearConfirmation = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(appState.history.count) 件の履歴")
                    .font(.callout)
                    .fontWeight(.medium)
                Text("最近の履歴はメニューバーからコピーできます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingClearConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("すべてクリア")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(appState.history.isEmpty ? Color.secondary : Color.red)
            }
            .buttonStyle(.plain)
            .disabled(appState.history.isEmpty)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
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

private final class VoiceCaptureBuffer {
    private let lock = NSLock()
    private var pcmData = Data()

    func reset() {
        lock.lock()
        pcmData.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func append(_ data: Data) {
        lock.lock()
        pcmData.append(data)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let data = pcmData
        lock.unlock()
        return data
    }
}

struct VoiceEnrollmentSection: View {
    @State private var isRecording: Bool = false
    @State private var recordingDuration: Double = 0
    @State private var enrollmentStatus: EnrollmentStatus = .idle
    @State private var audioEngine: AVAudioEngine?
    @State private var recordingTimer: Timer?
    @State private var recordedData: Data?
    @State private var isEnrolled: Bool = SpeakerVerificationService.shared.isEnrolled
    @State private var isReady: Bool = SpeakerVerificationService.shared.isReady
    @State private var isPulseAnimating = false
    @State private var captureBuffer = VoiceCaptureBuffer()

    private var recordingFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEnrolled {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    Text("登録済み")
                        .font(.callout)
                        .fontWeight(.semibold)
                }

                SectionDivider()

                Button("リセット") {
                    SpeakerVerificationService.shared.resetEnrollment()
                    isEnrolled = false
                    enrollmentStatus = .idle
                    recordedData = nil
                    debugLog("SpeakerVerification UI: enrollment reset")
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.red)
            } else {
                Text("以下のテキストを普段どおりの声で読み上げてください。録音後に自動で声紋を登録します。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)

                Text("「今日はとてもいい天気ですね。こんな日は散歩にでも出かけたくなります。最近は忙しくてなかなか外に出られないけれど、たまにはゆっくり過ごしたいものです。」")
                    .font(.callout)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                SectionDivider()

                if !isReady {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("声紋認証を準備中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isRecording {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.2))
                                    .frame(width: 20, height: 20)
                                    .scaleEffect(isPulseAnimating ? 1.8 : 1.0)
                                    .opacity(isPulseAnimating ? 0.2 : 0.7)
                                Circle()
                                    .fill(.red)
                                    .frame(width: 10, height: 10)
                            }
                            .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: isPulseAnimating)

                            Text(formattedRecordingDuration)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .monospacedDigit()

                            Text("録音中")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            stopRecording(shouldEnroll: true)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "stop.fill")
                                    .font(.caption)
                                Text("録音を停止")
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(.white)
                            .frame(height: 38)
                            .padding(.horizontal, 16)
                            .background(
                                LinearGradient(
                                    colors: [.red, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        startRecording()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                                .font(.callout)
                            Text("録音を開始")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(height: 38)
                        .padding(.horizontal, 16)
                        .background(
                            LinearGradient(
                                colors: [.red, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isReady || enrollmentStatus == .processing)
                    .opacity(!isReady || enrollmentStatus == .processing ? 0.6 : 1.0)
                }

                if case .processing = enrollmentStatus {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("声紋を登録中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if case .success = enrollmentStatus {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("声紋の登録が完了しました")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if case let .failed(message) = enrollmentStatus {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .onAppear {
            isEnrolled = SpeakerVerificationService.shared.isEnrolled
            isReady = SpeakerVerificationService.shared.isReady
            if !isReady {
                Task {
                    do {
                        try await SpeakerVerificationService.shared.initialize()
                        await MainActor.run {
                            isReady = true
                            debugLog("SpeakerVerification UI: initialized")
                        }
                    } catch {
                        await MainActor.run {
                            enrollmentStatus = .failed(error.localizedDescription)
                            debugLog("SpeakerVerification UI: initialization failed \(error)")
                        }
                    }
                }
            }
        }
        .onDisappear {
            stopRecording(shouldEnroll: false)
        }
    }

    private var formattedRecordingDuration: String {
        let total = Int(recordingDuration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%01d:%02d", minutes, seconds)
    }

    private func startRecording() {
        guard !isRecording else { return }
        guard isReady else {
            enrollmentStatus = .failed(String(localized: "声紋認証の準備が完了していません"))
            return
        }
        guard MicrophonePermission.hasAvailableInputDevice else {
            enrollmentStatus = .failed(String(localized: "マイクが接続されていません"))
            debugLog("SpeakerVerification UI: no available input device")
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = recordingFormat
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            enrollmentStatus = .failed(String(localized: "音声フォーマットの変換に失敗しました"))
            debugLog("SpeakerVerification UI: converter creation failed")
            return
        }
        let bufferStore = captureBuffer

        captureBuffer.reset()
        recordedData = nil
        recordingDuration = 0
        enrollmentStatus = .recording
        isRecording = true
        isPulseAnimating = true
        startTimer()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
                return
            }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error else {
                if let error {
                    debugLog("SpeakerVerification UI: conversion failed \(error)")
                }
                return
            }

            guard let channelData = convertedBuffer.int16ChannelData else { return }
            let frameLength = Int(convertedBuffer.frameLength)
            let chunkData = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Int16>.size)
            bufferStore.append(chunkData)
        }

        do {
            try engine.start()
            audioEngine = engine
            debugLog("SpeakerVerification UI: recording started")
        } catch {
            inputNode.removeTap(onBus: 0)
            stopTimer()
            isRecording = false
            isPulseAnimating = false
            enrollmentStatus = .failed(String(localized: "録音の開始に失敗しました"))
            debugLog("SpeakerVerification UI: recording start failed \(error)")
        }
    }

    private func stopRecording(shouldEnroll: Bool) {
        guard isRecording else { return }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        stopTimer()
        isRecording = false
        isPulseAnimating = false

        let capturedPCMData = captureBuffer.snapshot()
        captureBuffer.reset()
        debugLog("SpeakerVerification UI: recording stopped duration=\(recordingDuration)")

        guard shouldEnroll else {
            enrollmentStatus = .idle
            return
        }

        guard recordingDuration >= 3 else {
            enrollmentStatus = .failed(String(localized: "3秒以上録音してください"))
            return
        }

        guard !capturedPCMData.isEmpty else {
            enrollmentStatus = .failed(String(localized: "音声データを取得できませんでした"))
            return
        }

        let wavData = createWAVData(from: capturedPCMData, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        recordedData = wavData
        enrollmentStatus = .processing

        Task {
            await enrollRecordedData()
        }
    }

    @MainActor
    private func enrollRecordedData() async {
        guard let recordedData else {
            enrollmentStatus = .failed(String(localized: "音声データがありません"))
            return
        }

        do {
            if !SpeakerVerificationService.shared.isReady {
                try await SpeakerVerificationService.shared.initialize()
                isReady = true
            }

            let success = try await SpeakerVerificationService.shared.enrollFromRecordedData(recordedData, format: recordingFormat)
            if success {
                enrollmentStatus = .success
                isEnrolled = SpeakerVerificationService.shared.isEnrolled
                debugLog("SpeakerVerification UI: enrollment success")
            } else {
                enrollmentStatus = .failed(String(localized: "声紋の登録に失敗しました"))
                debugLog("SpeakerVerification UI: enrollment returned false")
            }
        } catch {
            enrollmentStatus = .failed(error.localizedDescription)
            debugLog("SpeakerVerification UI: enrollment failed \(error)")
        }
    }

    private func startTimer() {
        stopTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func createWAVData(from pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let fileSize: UInt32 = 36 + dataSize

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

        var data = Data()
        data.append(header)
        data.append(pcmData)
        return data
    }
}

struct ShortcutIssueBanner: View {
    let issue: ShortcutMonitoringIssue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let gradientColors: [Color]
    @ViewBuilder let content: Content

    private var accentColor: Color {
        gradientColors.first ?? .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .fontWeight(.semibold)
            }
            .padding(.bottom, 14)

            content
        }
    }
}

struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsStyle.divider)
            .frame(height: 1)
            .padding(.vertical, 12)
    }
}

struct SettingsToggleRow: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? SettingsStyle.rowHover : Color.clear)
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SettingsControlRow<Control: View>: View {
    let title: LocalizedStringKey
    let description: String
    let control: Control
    @State private var isHovered = false

    init(title: LocalizedStringKey, description: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }

            Spacer(minLength: 18)

            control
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? SettingsStyle.rowHover : Color.clear)
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
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

struct PermissionStatusView: View {
    @State private var microphoneStatus: Bool = false
    @State private var accessibilityStatus: Bool = false
    @State private var accessibilityPollingTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionRow(
                title: "マイク",
                description: "音声を録音するために必要",
                isGranted: microphoneStatus,
                action: { openSystemPreferences("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") }
            )

            SectionDivider()

            PermissionRow(
                title: "アクセシビリティ",
                description: "ショートカットキーを監視するために必要",
                isGranted: accessibilityStatus,
                action: { requestAccessibilityPermission() }
            )
        }
        .onAppear { checkPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermissions()
        }
        .onDisappear {
            accessibilityPollingTimer?.invalidate()
            accessibilityPollingTimer = nil
        }
    }

    private func checkPermissions() {
        microphoneStatus = MicrophonePermission.isGranted
        accessibilityStatus = AXIsProcessTrusted()
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityStatus = AXIsProcessTrustedWithOptions(options)
        startAccessibilityPolling()
        openSystemPreferences("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func startAccessibilityPolling() {
        accessibilityPollingTimer?.invalidate()
        accessibilityPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let granted = AXIsProcessTrusted()
            accessibilityStatus = granted
            if granted {
                timer.invalidate()
                accessibilityPollingTimer = nil
            }
        }
    }

    private func openSystemPreferences(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PermissionRow: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let isGranted: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isGranted ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isGranted {
                Button(action: action) {
                    Text("設定を開く")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.06) : Color.clear)
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
