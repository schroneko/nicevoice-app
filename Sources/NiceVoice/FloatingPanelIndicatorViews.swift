import SwiftUI

struct FloatingPanelView: View {
    var appState: AppState
    @State private var isVisible = false
    @AppStorage("floatingPanelStyle") private var floatingPanelStyleRaw = FloatingPanelStyle.current.rawValue

    var body: some View {
        let style = FloatingPanelStyle(rawValue: floatingPanelStyleRaw) ?? .current
        Group {
            switch style {
            case .current:
                CurrentStyleView(appState: appState)
            case .codexMinimal:
                CodexMinimalStyleView(appState: appState)
            case .liquidOrb:
                LiquidOrbStyleView(appState: appState)
            case .pillWaveform:
                PillWaveformStyleView(appState: appState)
            case .glassCaption:
                GlassCaptionStyleView(appState: appState)
            case .orbitDot:
                OrbitDotStyleView(appState: appState)
            case .frostedBar:
                FrostedBarStyleView(appState: appState)
            }
        }
        .scaleEffect(isVisible ? 1 : 0.6)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
}

struct FinalizingIndicatorView: View {
    let previewText: String
    @State private var animateHighlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.18), .cyan.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                        .scaleEffect(animateHighlight ? 1.08 : 0.92)

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("文章を整え中")
                        .font(.system(size: 13, weight: .semibold))
                    Text("句読点と話し言葉をなめらかに整えています")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ProgressView()
                    .controlSize(.small)
                    .tint(.blue)
            }

            if !previewText.isEmpty {
                Text(previewText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
        }
        .frame(maxWidth: Constants.UI.floatingPanelExpandedWidth, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                animateHighlight = true
            }
        }
    }
}

struct RecordingIndicatorView: View {
    let currentLevel: () -> Float
    let startDate: Date?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)

            BrailleMeterView(currentLevel: currentLevel)

            if let startDate {
                RecordingTimerView(startDate: startDate)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct RecordingTimerView: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1)) { timeline in
            let elapsed = Int(timeline.date.timeIntervalSince(startDate))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            Text(String(format: "%d:%02d", minutes, seconds))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

final class BrailleMeterState {
    private var history: [Character]
    private var noiseEma: Double = 0.02
    private var env: Double = 0.0

    init() {
        history = Array(
            repeating: Constants.BrailleMeter.symbols[0],
            count: Constants.BrailleMeter.historyLength
        )
    }

    func nextText(level: Float) -> String {
        let symbols = Constants.BrailleMeter.symbols
        let latestPeak = Double(level)

        if latestPeak > env {
            env = Constants.BrailleMeter.attack * latestPeak
                + (1.0 - Constants.BrailleMeter.attack) * env
        } else {
            env = Constants.BrailleMeter.release * latestPeak
                + (1.0 - Constants.BrailleMeter.release) * env
        }

        let rmsApprox = env * 0.7
        noiseEma = (1.0 - Constants.BrailleMeter.alphaNoiseFloor) * noiseEma
            + Constants.BrailleMeter.alphaNoiseFloor * rmsApprox
        let refLevel = max(noiseEma, 0.01)
        let fastSignal = 0.8 * latestPeak + 0.2 * env
        let raw = max(fastSignal / (refLevel * 2.0), 0.0)
        let k = 1.6
        let compressed = min(log1p(raw) / log1p(k), 1.0)
        let maxIdx = Double(symbols.count - 1)
        let idx = Int(min(max((compressed * maxIdx).rounded(), 0), maxIdx))

        history.removeFirst()
        history.append(symbols[idx])

        return String(history)
    }
}

struct BrailleMeterView: View {
    let currentLevel: () -> Float
    @State private var state = BrailleMeterState()

    var body: some View {
        TimelineView(.periodic(from: .now, by: Constants.BrailleMeter.updateInterval)) { _ in
            Text(state.nextText(level: currentLevel()))
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(.red.opacity(0.85))
        }
    }
}

struct ErrorIndicatorView: View {
    let message: String
    @State private var isPulsing = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14, weight: .semibold))
                .scaleEffect(isPulsing ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("文字起こしできません")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: Constants.UI.floatingPanelExpandedWidth, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            isPulsing = true
        }
    }
}
