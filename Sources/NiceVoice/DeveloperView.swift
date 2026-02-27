import SwiftUI

struct DeveloperView: View {
    var appState: AppState
    @AppStorage("transcriptionEngine") private var transcriptionEngineRaw = TranscriptionEngine.speechAnalyzer.rawValue
    @State private var sectionAnimations: [Bool] = [false, false, false]

    private var selectedEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: transcriptionEngineRaw) ?? .speechAnalyzer
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("開発者")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
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
                                    appState.setupTranscriptionService()
                                    Task {
                                        await appState.reinitializeAfterEngineChange()
                                    }
                                }
                            )
                        }
                    }
                }
                .opacity(sectionAnimations[0] ? 1 : 0)
                .offset(y: sectionAnimations[0] ? 0 : 16)

                SettingsSection(
                    title: "モデル管理",
                    icon: "arrow.down.doc.fill",
                    gradientColors: [.blue, .purple]
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(TranscriptionEngine.allCases.filter { $0.requiresLocalServer }, id: \.self) { engine in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(engine.displayName)
                                                .font(.callout)
                                                .fontWeight(.medium)
                                            if engine == selectedEngine {
                                                Text("使用中")
                                                    .font(.system(size: 9, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(.orange))
                                            }
                                        }
                                        Text("\(engine.hfModelName ?? "") (\(engine.modelSize ?? ""))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if engine == selectedEngine {
                                        selectedEngineControls
                                    } else {
                                        nonSelectedEngineControls(for: engine)
                                    }
                                }

                                if engine == selectedEngine {
                                    selectedEngineStatus
                                }
                            }

                            if engine != TranscriptionEngine.allCases.filter({ $0.requiresLocalServer }).last {
                                SectionDivider()
                            }
                        }
                    }
                }
                .opacity(sectionAnimations[1] ? 1 : 0)
                .offset(y: sectionAnimations[1] ? 0 : 16)

                SettingsSection(
                    title: "デバッグ情報",
                    icon: "ladybug.fill",
                    gradientColors: [.green, .teal]
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        DebugInfoRow(label: "エンジン", value: selectedEngine.displayName)
                        DebugInfoRow(label: "モデル", value: {
                            switch selectedEngine {
                            case .voxtralLocal: return "voxmlx-serve (local)"
                            case .qwen3ASR: return "qwen3-asr (local)"
                            case .deepgram: return "Deepgram Nova-3 (cloud)"
                            case .speechAnalyzer: return "SpeechAnalyzer (built-in)"
                            }
                        }())
                        DebugInfoRow(label: "ステータス", value: appState.statusMessage)
                        DebugInfoRow(label: "準備状態", value: appState.isReady ? "Ready" : "Not Ready")
                    }
                }
                .opacity(sectionAnimations[2] ? 1 : 0)
                .offset(y: sectionAnimations[2] ? 0 : 16)

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
        }
    }

    @ViewBuilder
    private var selectedEngineControls: some View {
        switch appState.modelDownloadStatus {
        case .notDownloaded:
            Button {
                appState.downloadModel()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("ダウンロード")
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        case .downloading:
            Button {
                appState.cancelModelDownload()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("キャンセル")
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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
        case .downloaded:
            HStack(spacing: 8) {
                if case .running = appState.localServerStatus {
                    Button {
                        appState.localServerManager?.stop()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("停止")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
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
                } else if case .starting = appState.localServerStatus {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        appState.localServerManager?.start()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("起動")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [.green, .teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.deleteModel()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .error:
            Button {
                appState.downloadModel()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text("再試行")
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var selectedEngineStatus: some View {
        switch appState.modelDownloadStatus {
        case .downloading(_, let message):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: appState.modelDownloadStatus == .downloading(progress: 0, message: "") ? 0 : {
                    if case .downloading(let p, _) = appState.modelDownloadStatus { return p }
                    return 0
                }())
                    .progressViewStyle(.linear)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .downloaded:
            switch appState.localServerStatus {
            case .stopped:
                EmptyView()
            case .starting(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .running:
                Text("サーバー起動中")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .error(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func nonSelectedEngineControls(for engine: TranscriptionEngine) -> some View {
        if appState.isModelCached(for: engine) {
            HStack(spacing: 8) {
                Text("ダウンロード済み")
                    .font(.caption)
                    .foregroundStyle(.green)
                Button {
                    appState.deleteModelCache(for: engine)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("未ダウンロード")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
