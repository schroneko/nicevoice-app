import AppKit
import SwiftUI

enum FloatingPanelStyle: String, CaseIterable, Identifiable {
    case current
    case codexMinimal
    case liquidOrb
    case pillWaveform
    case glassCaption
    case orbitDot
    case frostedBar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .current: return "Current (Capsule)"
        case .codexMinimal: return "Codex Minimal (32px pill)"
        case .liquidOrb: return "Liquid Orb"
        case .pillWaveform: return "Dynamic Pill Waveform"
        case .glassCaption: return "Glass Card + Live Caption"
        case .orbitDot: return "Minimal Orbit Dot"
        case .frostedBar: return "Frosted HUD Bar"
        }
    }

    var subtitle: String {
        switch self {
        case .current: return "既存のカプセル"
        case .codexMinimal: return "Codex.app の global dictation を忠実再現"
        case .liquidOrb: return "中央に呼吸するオーブ"
        case .pillWaveform: return "Dynamic Island 風の波形ピル"
        case .glassCaption: return "ライブキャプション付きガラスカード"
        case .orbitDot: return "ミニマルな同心円ドット"
        case .frostedBar: return "ガラス質の HUD バー"
        }
    }

    func minPanelSize(expanded: Bool) -> NSSize {
        switch self {
        case .codexMinimal:
            return NSSize(width: 64, height: 32)
        case .current, .liquidOrb, .pillWaveform, .glassCaption, .orbitDot, .frostedBar:
            return expanded
                ? NSSize(
                    width: Constants.UI.floatingPanelExpandedWidth,
                    height: Constants.UI.floatingPanelExpandedHeight
                )
                : NSSize(
                    width: Constants.UI.floatingPanelWidth,
                    height: Constants.UI.floatingPanelHeight
                )
        }
    }
}

struct CurrentStyleView: View {
    var appState: AppState

    var body: some View {
        if appState.errorMessage != nil {
            ErrorIndicatorView(message: appState.errorMessage ?? "")
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else if appState.isShowingFinalizationPanel {
            FinalizingIndicatorView(previewText: appState.floatingPanelPreviewText)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            RecordingIndicatorView(
                currentLevel: { appState.audioLevels.last ?? 0 },
                startDate: appState.recordingStartDate
            )
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

struct CodexMinimalStyleView: View {
    var appState: AppState

    var body: some View {
        if appState.errorMessage != nil {
            CodexMinimalErrorView(
                message: appState.errorMessage ?? "",
                onRetry: { appState.dismissFloatingPanelError() },
                onDismiss: { appState.dismissFloatingPanelError() }
            )
        } else if appState.isShowingFinalizationPanel {
            CodexMinimalTranscribingView()
        } else {
            CodexMinimalListeningView(allLevels: { appState.audioLevels })
        }
    }
}

private let codexPillHeight: CGFloat = 32
private let codexBarWidth: CGFloat = 5.76
private let codexBarSpacing: CGFloat = 3.36
private let codexCanvasWidth: CGFloat = 48
private let codexCanvasHeight: CGFloat = 16

private struct CodexBackgroundEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct CodexPillBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(height: codexPillHeight)
            .background(alignment: .center) {
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                    .background {
                        CodexBackgroundEffect()
                            .clipShape(Capsule(style: .continuous))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                Color(nsColor: .separatorColor).opacity(0.8),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
            }
    }
}

private extension View {
    func codexPill() -> some View { modifier(CodexPillBackground()) }
}

private struct CodexMinimalListeningView: View {
    let allLevels: () -> [Float]

    var body: some View {
        HStack(spacing: 0) {
            CodexCompactWaveform(allLevels: allLevels)
                .frame(width: codexCanvasWidth, height: codexCanvasHeight)
        }
        .padding(.horizontal, 8)
        .frame(width: 64)
        .codexPill()
    }
}

private struct CodexMinimalTranscribingView: View {
    @State private var rotation = 0.0

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(
                    Color(nsColor: .secondaryLabelColor),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
        }
        .padding(.horizontal, 8)
        .frame(width: 64)
        .codexPill()
    }
}

private struct CodexMinimalErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: .systemRed))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 252, alignment: .leading)
                .fixedSize(horizontal: false, vertical: false)

            CodexIconButton(systemImage: "arrow.clockwise", action: onRetry)
            CodexIconButton(systemImage: "xmark", action: onDismiss)
        }
        .padding(.horizontal, 8)
        .fixedSize(horizontal: true, vertical: false)
        .codexPill()
    }
}

private struct CodexIconButton: View {
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovered
                    ? Color(nsColor: .labelColor)
                    : Color(nsColor: .secondaryLabelColor))
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(isHovered
                            ? Color(nsColor: .quaternaryLabelColor)
                            : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

@Observable
final class CodexCompactWaveformState {
    var bars: [CGFloat] = [3, 3, 3, 3]
    var barOpacities: [Double] = [0.5, 0.5, 0.5, 0.5]

    private var smoothedAmplitude: Double = 0
    private var phase: Double = 0
    private var barAmplitudes: [Double] = [0.0025, 0.0025, 0.0025, 0.0025]
    private var timer: Timer?
    private var levelProvider: (() -> [Float])?

    private let attack: Double = 0.36
    private let release: Double = 0.10
    private let amplitudeClip: Double = 0.085
    private let noiseFloor: Double = 0.02
    private let maxRms: Double = 0.5
    private let phaseIncrement: Double = 0.05
    private let barLerp: Double = 0.5
    private let canvasHalfHeight: Double = 8
    private let silentLevel: Double = 0.0025
    private let frameInterval: TimeInterval = 1.0 / 24.0

    func start(levelProvider: @escaping () -> [Float]) {
        self.levelProvider = levelProvider
        smoothedAmplitude = 0
        phase = 0
        barAmplitudes = [silentLevel, silentLevel, silentLevel, silentLevel]
        bars = [3, 3, 3, 3]
        barOpacities = [0.5, 0.5, 0.5, 0.5]

        timer?.invalidate()
        let t = Timer(timeInterval: frameInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        levelProvider = nil
    }

    deinit {
        timer?.invalidate()
    }

    private func tick() {
        guard let levels = levelProvider?(), !levels.isEmpty else { return }
        let latest = Double(levels.last ?? 0)

        let denoised = max(0, latest - noiseFloor)
        let denom = max(0.0001, maxRms - noiseFloor)
        let normalized = pow(min(1, denoised / denom), 0.6) * amplitudeClip
        let coef = normalized > smoothedAmplitude ? attack : release
        smoothedAmplitude = smoothedAmplitude * (1 - coef) + normalized * coef
        phase += phaseIncrement

        let recent = Array(levels.suffix(8))
        let recentCount = recent.count
        let chunkSize = max(1, recentCount / 4)
        let overallRms: Double = {
            guard recentCount > 0 else { return 0 }
            let sum = recent.reduce(0.0) { $0 + Double($1) * Double($1) }
            return sqrt(sum / Double(recentCount))
        }()

        for i in 0..<4 {
            let sineMix = 0.9 + (sin(phase - Double(i) * 0.8) + 1) / 2 * 0.1

            let chunkStart = min(max(0, recentCount - chunkSize), i * chunkSize)
            let chunkEnd = min(recentCount, chunkStart + chunkSize)
            let chunkRms: Double = {
                guard chunkStart < chunkEnd else { return overallRms }
                let slice = recent[chunkStart..<chunkEnd]
                let sum = slice.reduce(0.0) { $0 + Double($1) * Double($1) }
                return sqrt(sum / Double(slice.count))
            }()
            let distortion: Double = overallRms <= silentLevel
                ? 1
                : max(0.86, min(1.14, chunkRms / overallRms))

            let newAmp = min(
                amplitudeClip,
                silentLevel + smoothedAmplitude * sineMix * distortion
            )
            let prev = barAmplitudes[i]
            let smoothed = prev * (1 - barLerp) + newAmp * barLerp
            barAmplitudes[i] = smoothed

            let halfHeight = max(1.5, smoothed * 10 * canvasHalfHeight)
            bars[i] = CGFloat(halfHeight * 2)
            barOpacities[i] = smoothed <= silentLevel + 0.001 ? 0.5 : 0.95
        }
    }
}

private struct CodexCompactWaveform: View {
    let allLevels: () -> [Float]
    @State private var state = CodexCompactWaveformState()

    var body: some View {
        HStack(spacing: codexBarSpacing) {
            ForEach(0..<4, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .labelColor).opacity(state.barOpacities[i]))
                    .frame(width: codexBarWidth, height: state.bars[i])
            }
        }
        .frame(width: codexCanvasWidth, height: codexCanvasHeight, alignment: .center)
        .onAppear { state.start(levelProvider: allLevels) }
        .onDisappear { state.stop() }
    }
}

struct LiquidOrbStyleView: View {
    var appState: AppState

    var body: some View {
        if appState.errorMessage != nil {
            LiquidOrbErrorView(message: appState.errorMessage ?? "")
        } else if appState.isShowingFinalizationPanel {
            LiquidOrbFinalizingView(previewText: appState.floatingPanelPreviewText)
        } else {
            LiquidOrbRecordingView(
                currentLevel: { appState.audioLevels.last ?? 0 },
                startDate: appState.recordingStartDate
            )
        }
    }
}

private struct LiquidOrbRecordingView: View {
    let currentLevel: () -> Float
    let startDate: Date?

    var body: some View {
        VStack(spacing: 6) {
            AudioReactiveOrb(
                currentLevel: currentLevel,
                colors: [.pink, .purple, .indigo]
            )
            .frame(width: 60, height: 60)

            if let startDate {
                RecordingTimerView(startDate: startDate)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .purple.opacity(0.25), radius: 18, y: 8)
        )
    }
}

private struct LiquidOrbFinalizingView: View {
    let previewText: String
    @State private var rotation = 0.0

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.cyan.opacity(0.6), .blue.opacity(0.2), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        .frame(width: 50, height: 50)
                        .blur(radius: 4)

                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.cyan, .blue, .indigo, .cyan],
                                center: .center
                            )
                        )
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(rotation))

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("文章を整え中")
                        .font(.system(size: 12, weight: .semibold))
                    Text("ふんわり整えてるよ")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if !previewText.isEmpty {
                Text(previewText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .blue.opacity(0.2), radius: 16, y: 6)
        )
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

private struct LiquidOrbErrorView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.orange.opacity(0.5), .red.opacity(0.2), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 28
                        )
                    )
                    .frame(width: 44, height: 44)
                    .blur(radius: 3)

                Circle()
                    .fill(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)

                Image(systemName: "exclamationmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("文字起こしできません")
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.orange.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .orange.opacity(0.2), radius: 14, y: 6)
        )
    }
}

private struct AudioReactiveOrb: View {
    let currentLevel: () -> Float
    let colors: [Color]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let level = Double(min(max(currentLevel(), 0), 1))
            let scale = 0.78 + level * 0.5

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [colors[0].opacity(0.7), colors[1].opacity(0.4), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 36
                        )
                    )
                    .scaleEffect(scale * 1.25)
                    .blur(radius: 5)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [colors[0], colors[1], colors[2]],
                            center: UnitPoint(x: 0.35, y: 0.35),
                            startRadius: 2,
                            endRadius: 26
                        )
                    )
                    .scaleEffect(scale)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [colors[0].opacity(0.6), colors[2].opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .scaleEffect(1.08 + level * 0.25)
                    .opacity(0.6)
            }
            .animation(.easeOut(duration: 0.12), value: level)
        }
    }
}

struct PillWaveformStyleView: View {
    var appState: AppState

    var body: some View {
        if appState.errorMessage != nil {
            PillWaveformErrorView(message: appState.errorMessage ?? "")
        } else if appState.isShowingFinalizationPanel {
            PillWaveformFinalizingView(previewText: appState.floatingPanelPreviewText)
        } else {
            PillWaveformRecordingView(
                startDate: appState.recordingStartDate,
                allLevels: { appState.audioLevels }
            )
        }
    }
}

private struct PillWaveformRecordingView: View {
    let startDate: Date?
    let allLevels: () -> [Float]
    @State private var dotPulse: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
                .scaleEffect(dotPulse)
                .shadow(color: .red.opacity(0.7), radius: 3)

            WaveformBars(allLevels: allLevels, barCount: 12, maxHeight: 20)
                .frame(width: 96, height: 20)

            if let startDate {
                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 1, height: 14)

                RecordingTimerView(startDate: startDate)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.72))
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                dotPulse = 1.35
            }
        }
    }
}

private struct PillWaveformFinalizingView: View {
    let previewText: String
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .purple, .pink], startPoint: .leading, endPoint: .trailing)
                    )

                Text("整え中")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.8))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.1))
                    Capsule()
                        .fill(
                            LinearGradient(colors: [.cyan, .purple, .pink], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * 0.4)
                        .offset(x: shimmerOffset * geo.size.width * 0.6)
                }
            }
            .frame(height: 3)

            if !previewText.isEmpty {
                Text(previewText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                shimmerOffset = 1
            }
        }
    }
}

private struct PillWaveformErrorView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("文字起こしできません")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.orange.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
        )
    }
}

private struct WaveformBars: View {
    let allLevels: () -> [Float]
    let barCount: Int
    let maxHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let levels = allLevels()
            let visible = Array(levels.suffix(barCount))
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let level = i < visible.count ? Double(visible[i]) : 0.0
                    let height = max(3, level * Double(maxHeight))
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .purple, .pink],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 3, height: height)
                        .frame(height: maxHeight, alignment: .center)
                }
            }
        }
    }
}

struct GlassCaptionStyleView: View {
    var appState: AppState

    var body: some View {
        if appState.errorMessage != nil {
            GlassCaptionErrorView(message: appState.errorMessage ?? "")
        } else if appState.isShowingFinalizationPanel {
            GlassCaptionFinalizingView(previewText: appState.floatingPanelPreviewText)
        } else {
            GlassCaptionRecordingView(
                startDate: appState.recordingStartDate,
                allLevels: { appState.audioLevels },
                previewText: appState.floatingPanelPreviewText
            )
        }
    }
}

private struct GlassCaptionRecordingView: View {
    let startDate: Date?
    let allLevels: () -> [Float]
    let previewText: String
    @State private var iconPulse: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.red.opacity(0.25))
                        .frame(width: 28, height: 28)
                        .scaleEffect(iconPulse)
                    Circle()
                        .fill(LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("録音中")
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 0)

                if let startDate {
                    RecordingTimerView(startDate: startDate)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }

            GlassWaveformStrip(allLevels: allLevels)
                .frame(height: 22)

            Text(previewText.isEmpty ? "音声をキャプチャしています…" : previewText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(previewText.isEmpty ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Color.primary.opacity(0.85)))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                iconPulse = 1.18
            }
        }
    }
}

private struct GlassCaptionFinalizingView: View {
    let previewText: String
    @State private var rotation = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(rotation))
                }

                Text("文章を整え中")
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 0)

                ProgressView()
                    .controlSize(.small)
                    .tint(.blue)
            }

            if !previewText.isEmpty {
                Text(previewText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.06))
                    )
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .blue.opacity(0.2), radius: 16, y: 6)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

private struct GlassCaptionErrorView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("文字起こしできません")
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.orange.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(color: .orange.opacity(0.2), radius: 14, y: 6)
        )
    }
}

private struct GlassWaveformStrip: View {
    let allLevels: () -> [Float]
    private let barCount = 22

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let levels = allLevels()
            let visible = Array(levels.suffix(barCount))
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let level = i < visible.count ? Double(visible[i]) : 0.0
                        let height = max(2, level * Double(geo.size.height))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.7), .pink],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 3, height: height)
                            .frame(height: geo.size.height, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct OrbitDotStyleView: View {
    var appState: AppState

    var body: some View {
        if appState.errorMessage != nil {
            OrbitDotErrorView(message: appState.errorMessage ?? "")
        } else if appState.isShowingFinalizationPanel {
            OrbitDotFinalizingView()
        } else {
            OrbitDotRecordingView(
                currentLevel: { appState.audioLevels.last ?? 0 },
                startDate: appState.recordingStartDate
            )
        }
    }
}

private struct OrbitDotRecordingView: View {
    let currentLevel: () -> Float
    let startDate: Date?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                OrbitRing(currentLevel: currentLevel, diameter: 64, lineWidth: 1.2)
                OrbitRing(currentLevel: currentLevel, diameter: 48, lineWidth: 1.4)
                AudioReactiveDotCore(currentLevel: currentLevel)
                    .frame(width: 28, height: 28)
            }
            .frame(width: 70, height: 70)

            if let startDate {
                RecordingTimerView(startDate: startDate)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        )
    }
}

private struct OrbitDotFinalizingView: View {
    @State private var rotation = 0.0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        AngularGradient(colors: [.cyan, .blue, .indigo, .clear], center: .center),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(rotation))

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)
                    )
            }

            Text("整え中")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .blue.opacity(0.22), radius: 12, y: 4)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

private struct OrbitDotErrorView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.orange.opacity(0.3), .red.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.orange)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("文字起こしできません")
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.orange.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(color: .orange.opacity(0.2), radius: 12, y: 4)
        )
    }
}

private struct OrbitRing: View {
    let currentLevel: () -> Float
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let level = Double(min(max(currentLevel(), 0), 1))
            let scale = 0.92 + level * 0.22
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.red.opacity(0.55), .pink.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: lineWidth
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(scale)
                .opacity(0.6 + level * 0.35)
                .animation(.easeOut(duration: 0.12), value: level)
        }
    }
}

private struct AudioReactiveDotCore: View {
    let currentLevel: () -> Float

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let level = Double(min(max(currentLevel(), 0), 1))
            let scale = 0.74 + level * 0.45

            ZStack {
                Circle()
                    .fill(.red.opacity(0.35 + level * 0.3))
                    .blur(radius: 5)
                    .scaleEffect(scale * 1.4)

                Circle()
                    .fill(LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .scaleEffect(scale)
            }
            .animation(.easeOut(duration: 0.12), value: level)
        }
    }
}

struct FrostedBarStyleView: View {
    var appState: AppState

    var body: some View {
        if appState.errorMessage != nil {
            FrostedBarErrorView(message: appState.errorMessage ?? "")
        } else if appState.isShowingFinalizationPanel {
            FrostedBarFinalizingView(previewText: appState.floatingPanelPreviewText)
        } else {
            FrostedBarRecordingView(
                startDate: appState.recordingStartDate,
                allLevels: { appState.audioLevels }
            )
        }
    }
}

private struct FrostedBarRecordingView: View {
    let startDate: Date?
    let allLevels: () -> [Float]

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [.red.opacity(0.95), .pink.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                    .shadow(color: .red.opacity(0.35), radius: 4, y: 2)

                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            FrostedWaveform(allLevels: allLevels)
                .frame(width: 200, height: 24)

            Spacer(minLength: 0)

            if let startDate {
                RecordingTimerView(startDate: startDate)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 360)
        .background(frostedBackground(borderColor: .red.opacity(0.35), accentColors: [.red, .pink, .purple, .blue]))
    }
}

private struct FrostedBarFinalizingView: View {
    let previewText: String
    @State private var shimmer: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("文章を整え中")
                        .font(.system(size: 12, weight: .semibold))
                    Text("もうちょっとで終わるよ")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                ProgressView()
                    .controlSize(.small)
                    .tint(.blue)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.18))
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * 0.4)
                        .offset(x: shimmer * geo.size.width * 0.6)
                }
            }
            .frame(height: 3)

            if !previewText.isEmpty {
                Text(previewText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 360, alignment: .leading)
        .background(frostedBackground(borderColor: .blue.opacity(0.35), accentColors: [.cyan, .blue, .purple]))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                shimmer = 1
            }
        }
    }
}

private struct FrostedBarErrorView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("文字起こしできません")
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 360, alignment: .leading)
        .background(frostedBackground(borderColor: .orange.opacity(0.4), accentColors: [.orange, .red]))
    }
}

private func frostedBackground(borderColor: Color, accentColors: [Color]) -> some View {
    ZStack(alignment: .top) {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThickMaterial)

        LinearGradient(colors: accentColors, startPoint: .leading, endPoint: .trailing)
            .frame(height: 1.5)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 16,
                    style: .continuous
                )
            )

        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(borderColor, lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
}

private struct FrostedWaveform: View {
    let allLevels: () -> [Float]
    private let barCount = 28

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let levels = allLevels()
            let visible = Array(levels.suffix(barCount))
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let level = i < visible.count ? Double(visible[i]) : 0.0
                    let height = max(2, level * 24)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cyan.opacity(0.5), .blue, .purple],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 2, height: height)
                        .frame(height: 24, alignment: .center)
                }
            }
        }
    }
}
