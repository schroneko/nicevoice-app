import SwiftUI

struct DeveloperView: View {
    var appState: AppState
    @AppStorage("transcriptionEngine") private var transcriptionEngineRaw = TranscriptionEngine.speechAnalyzer.rawValue
    @State private var apiKeyStatus: APIKeyStatus = .notLoaded
    @State private var sectionAnimations: [Bool] = [false, false]

    private var selectedEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: transcriptionEngineRaw) ?? .speechAnalyzer
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("開発者")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("内部設定 (リリースビルドでは非表示)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                SettingsSection(
                    title: "音声認識エンジン",
                    icon: "waveform",
                    gradientColors: [.red, .orange]
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(TranscriptionEngine.allCases, id: \.self) { engine in
                            DeveloperEngineRow(
                                engine: engine,
                                isSelected: selectedEngine == engine,
                                action: {
                                    transcriptionEngineRaw = engine.rawValue
                                    if engine == .voxtral {
                                        loadAPIKeyAndSetup()
                                    } else {
                                        appState.setupTranscriptionService()
                                        Task {
                                            await appState.reinitializeAfterEngineChange()
                                        }
                                    }
                                }
                            )
                        }
                    }

                    if selectedEngine == .voxtral {
                        SectionDivider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mistral API Key")
                                    .font(.callout)
                                    .fontWeight(.medium)

                                switch apiKeyStatus {
                                case .notLoaded:
                                    Text("未取得")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                case .loading:
                                    Text("1Password から取得中...")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                case .loaded(let key):
                                    Text("\(String(key.prefix(8)))...\(String(key.suffix(4)))")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                case .error(let message):
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            Spacer()

                            Button {
                                loadAPIKeyAndSetup()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "key.fill")
                                    Text("1Password から取得")
                                }
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
                }
                .opacity(sectionAnimations[0] ? 1 : 0)
                .offset(y: sectionAnimations[0] ? 0 : 16)

                SettingsSection(
                    title: "デバッグ情報",
                    icon: "ladybug.fill",
                    gradientColors: [.green, .teal]
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        DebugInfoRow(label: "エンジン", value: selectedEngine.displayName)
                        DebugInfoRow(label: "モデル", value: selectedEngine == .voxtral ? Constants.Voxtral.model : "SpeechAnalyzer (built-in)")
                        DebugInfoRow(label: "ステータス", value: appState.statusMessage)
                        DebugInfoRow(label: "準備状態", value: appState.isReady ? "Ready" : "Not Ready")
                    }
                }
                .opacity(sectionAnimations[1] ? 1 : 0)
                .offset(y: sectionAnimations[1] ? 0 : 16)

                Spacer(minLength: 20)
            }
            .padding(32)
        }
        .onAppear {
            for index in 0..<sectionAnimations.count {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.1 + 0.1)) {
                    sectionAnimations[index] = true
                }
            }
            if selectedEngine == .voxtral && apiKeyStatus.isNotLoaded {
                loadAPIKeyAndSetup()
            }
        }
    }

    private func loadAPIKeyAndSetup() {
        apiKeyStatus = .loading
        Task {
            let key = await fetchMistralAPIKey()
            await MainActor.run {
                if let key {
                    apiKeyStatus = .loaded(key)
                    appState.setMistralAPIKey(key)
                    appState.setupTranscriptionService()
                    Task {
                        await appState.reinitializeAfterEngineChange()
                    }
                } else {
                    apiKeyStatus = .error("1Password から取得できませんでした")
                }
            }
        }
    }

    private func fetchMistralAPIKey() async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/op")
            process.arguments = ["item", "get", "MISTRAL_API_KEY", "--fields", "credential", "--reveal"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !output.isEmpty {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } else {
                    debugLog("❌ op CLI failed with status: \(process.terminationStatus)")
                    continuation.resume(returning: nil)
                }
            } catch {
                debugLog("❌ Failed to run op CLI: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
}

enum APIKeyStatus {
    case notLoaded
    case loading
    case loaded(String)
    case error(String)

    var isNotLoaded: Bool {
        if case .notLoaded = self { return true }
        return false
    }
}

struct DeveloperEngineRow: View {
    let engine: TranscriptionEngine
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    private let selectedGradient = LinearGradient(
        colors: [.red, .orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? AnyShapeStyle(selectedGradient.opacity(0.2)) : AnyShapeStyle(Color.secondary.opacity(0.1)))
                        .frame(width: 36, height: 36)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? .orange : .secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(engine.displayName)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(engine.engineDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(selectedGradient.opacity(0.08)) : AnyShapeStyle(isHovered ? Color.secondary.opacity(0.06) : Color.clear))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? AnyShapeStyle(selectedGradient.opacity(0.3)) : AnyShapeStyle(Color.clear),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct DebugInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
