import SwiftUI

struct DeveloperView: View {
    var appState: AppState
    @AppStorage("transcriptionEngine") private var transcriptionEngineRaw = TranscriptionEngine.speechAnalyzer.rawValue
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

                    if selectedEngine.requiresLocalServer {
                        SectionDivider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedEngine.serverCommandName ?? "")
                                    .font(.callout)
                                    .fontWeight(.medium)

                                switch appState.modelDownloadStatus {
                                case .notDownloaded:
                                    Text("モデル未ダウンロード (\(selectedEngine.modelSize ?? ""))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                case .downloading(let progress, let message):
                                    VStack(alignment: .leading, spacing: 4) {
                                        ProgressView(value: progress)
                                            .progressViewStyle(.linear)
                                        Text(message)
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                case .downloaded:
                                    switch appState.localServerStatus {
                                    case .stopped:
                                        Text("停止中")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    case .starting(let message):
                                        Text(message)
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    case .running:
                                        Text("起動中")
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
                                }
                            }

                            Spacer()

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
                                    HStack(spacing: 8) {
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
                                            HStack(spacing: 6) {
                                                Image(systemName: "trash.fill")
                                                Text("削除")
                                            }
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                LinearGradient(
                                                    colors: [.gray, .secondary],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .clipShape(Capsule())
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
