import SwiftUI
import AVFoundation
import ApplicationServices
import Speech

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case accessibility
    case modelDownload
    case howToUse
    case complete
}

struct OnboardingGradientBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [animate ? 0.6 : 0.4, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    .purple.opacity(0.15), .indigo.opacity(0.1), .blue.opacity(0.12),
                    .purple.opacity(0.08), .indigo.opacity(0.15), .cyan.opacity(0.1),
                    .indigo.opacity(0.1), .blue.opacity(0.08), .purple.opacity(0.12)
                ]
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
        }
    }
}

struct GradientIcon: View {
    let systemName: String
    let size: CGFloat
    let colors: [Color]

    init(systemName: String, size: CGFloat = 64, colors: [Color] = [.purple, .indigo]) {
        self.systemName = systemName
        self.size = size
        self.colors = colors
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

struct GradientText: View {
    let text: LocalizedStringKey
    let font: Font
    let colors: [Color]

    init(_ text: LocalizedStringKey, font: Font = .largeTitle, colors: [Color] = [.purple, .indigo]) {
        self.text = text
        self.font = font
        self.colors = colors
    }

    var body: some View {
        Text(text)
            .font(font)
            .fontWeight(.bold)
            .foregroundStyle(
                LinearGradient(
                    colors: colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

struct GradientButton: View {
    let title: LocalizedStringKey
    let icon: String?
    let colors: [Color]
    let action: () -> Void

    init(_ title: LocalizedStringKey, icon: String? = nil, colors: [Color] = [.purple, .indigo], action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.colors = colors
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 200, height: 44)
            .background(
                LinearGradient(
                    colors: colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: colors.first?.opacity(0.3) ?? .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct GradientCircleBackground: View {
    let colors: [Color]
    let size: CGFloat
    @State private var pulsate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors.first?.opacity(0.3) ?? .clear, colors.last?.opacity(0.1) ?? .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)
                .scaleEffect(pulsate ? 1.05 : 1.0)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: colors.map { $0.opacity(0.5) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulsate = true
            }
        }
    }
}

struct ConfettiPiece: View {
    let color: Color
    let size: CGFloat
    let rotation: Double
    let offset: CGSize
    let delay: Double

    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: size, height: size * 2)
            .rotationEffect(.degrees(animate ? rotation + 360 : rotation))
            .offset(x: offset.width, y: animate ? offset.height + 200 : offset.height - 100)
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 3).delay(delay)) {
                    animate = true
                }
            }
    }
}

struct ConfettiView: View {
    let colors: [Color] = [.purple, .indigo, .blue, .cyan, .green, .orange, .pink]

    var body: some View {
        ZStack {
            ForEach(0..<30, id: \.self) { i in
                ConfettiPiece(
                    color: colors[i % colors.count],
                    size: CGFloat.random(in: 4...8),
                    rotation: Double.random(in: 0...360),
                    offset: CGSize(
                        width: CGFloat.random(in: -200...200),
                        height: CGFloat.random(in: -50...50)
                    ),
                    delay: Double(i) * 0.05
                )
            }
        }
    }
}

struct AnimatedArrow: View {
    @State private var bounce = false

    var body: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 28))
            .foregroundStyle(
                LinearGradient(
                    colors: [.purple.opacity(0.6), .indigo.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .offset(y: bounce ? 4 : -4)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    bounce = true
                }
            }
    }
}

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep: OnboardingStep = .welcome
    @State private var animateContent = false
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    @State private var showConfetti = false
    @State private var modelReady = false
    @State private var modelDownloadError = false
    private let defaultShortcutKey: ShortcutKey = .fn

    var body: some View {
        ZStack {
            OnboardingGradientBackground()

            VStack(spacing: 0) {
                stepIndicator
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.2), .indigo.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)

                Group {
                    switch currentStep {
                    case .welcome:
                        welcomeStep
                    case .microphone:
                        microphoneStep
                    case .accessibility:
                        accessibilityStep
                    case .modelDownload:
                        modelDownloadStep
                    case .howToUse:
                        howToUseStep
                    case .complete:
                        completeStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 20)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.2), .indigo.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)

                navigationButtons
                    .padding(24)
            }

            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            checkPermissions()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                animateContent = true
            }
        }
        .onChange(of: currentStep) { _, newStep in
            animateContent = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                animateContent = true
            }
            if newStep == .complete {
                showConfetti = true
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 12) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 0) {
                    ZStack {
                        if step.rawValue < currentStep.rawValue {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .indigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else if step.rawValue == currentStep.rawValue {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .indigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 24, height: 24)
                            Circle()
                                .fill(.white)
                                .frame(width: 8, height: 8)
                        } else {
                            Circle()
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                                .frame(width: 24, height: 24)
                        }
                    }

                    if step.rawValue < OnboardingStep.allCases.count - 1 {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue
                                  ? LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
                                  : LinearGradient(colors: [.secondary.opacity(0.3), .secondary.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: 40, height: 2)
                    }
                }
                .animation(.spring(response: 0.3), value: currentStep)
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.purple.opacity(0.2), .indigo.opacity(0.05)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                GradientIcon(systemName: "mic.badge.plus", size: 56)
                    .symbolEffect(.pulse)
            }

            VStack(spacing: 14) {
                GradientText("NiceVoice へようこそ")

                Text("話すだけでテキストを入力できるようになります")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 14) {
                ModernFeatureCard(
                    icon: "waveform",
                    colors: [.blue, .cyan],
                    title: "音声認識",
                    description: "高精度なリアルタイム音声認識"
                )
                ModernFeatureCard(
                    icon: "text.badge.checkmark",
                    colors: [.green, .mint],
                    title: "自動整形",
                    description: "句読点の自動挿入とフィラー除去"
                )
                ModernFeatureCard(
                    icon: "keyboard",
                    colors: [.orange, .yellow],
                    title: "即座にペースト",
                    description: "どこでもテキストを入力可能"
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(32)
    }

    private var microphoneStep: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                GradientCircleBackground(
                    colors: microphoneGranted ? [.green, .mint] : [.orange, .yellow],
                    size: 140
                )

                GradientIcon(
                    systemName: microphoneGranted ? "mic.fill" : "mic.slash",
                    size: 52,
                    colors: microphoneGranted ? [.green, .mint] : [.orange, .yellow]
                )
                .symbolEffect(.bounce, value: microphoneGranted)
            }

            VStack(spacing: 14) {
                GradientText("マイクへのアクセス", font: .title, colors: [.orange, .yellow])

                Text("音声入力にはマイクへのアクセスが必要です")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if microphoneGranted {
                SuccessBadge(text: "マイクのアクセスが許可されました")
                    .transition(.scale.combined(with: .opacity))
            } else {
                GradientButton("マイクを許可する", icon: "mic", colors: [.orange, .yellow]) {
                    requestMicrophonePermission()
                }
            }

            Spacer()
        }
        .padding(32)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: microphoneGranted)
    }

    private var accessibilityStep: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                GradientCircleBackground(
                    colors: accessibilityGranted ? [.green, .mint] : [.purple, .indigo],
                    size: 140
                )

                GradientIcon(
                    systemName: accessibilityGranted ? "hand.raised.fill" : "hand.raised.slash",
                    size: 52,
                    colors: accessibilityGranted ? [.green, .mint] : [.purple, .indigo]
                )
                .symbolEffect(.bounce, value: accessibilityGranted)
            }

            VStack(spacing: 14) {
                GradientText("アクセシビリティ", font: .title)

                Text("ショートカットキーの検知とテキスト入力に必要です")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if accessibilityGranted {
                SuccessBadge(text: "アクセシビリティが許可されました")
                    .transition(.scale.combined(with: .opacity))
            } else {
                VStack(spacing: 18) {
                    GradientButton("設定を開く", icon: "gear") {
                        openAccessibilitySettings()
                    }

                    ModernAccessibilityInstructions()
                }
            }

            Spacer()
        }
        .padding(32)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: accessibilityGranted)
        .onAppear {
            startAccessibilityPolling()
        }
    }

    @ViewBuilder
    private var modelDownloadStep: some View {
        if #available(macOS 26.0, *) {
            modelDownloadStepContent
        } else {
            Text("macOS 26.0 以降が必要です")
        }
    }

    @available(macOS 26.0, *)
    private var modelDownloadStepContent: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                GradientCircleBackground(
                    colors: modelReady ? [.green, .mint] : [.blue, .cyan],
                    size: 140
                )

                GradientIcon(
                    systemName: modelReady ? "checkmark.circle.fill" : "arrow.down.circle",
                    size: 52,
                    colors: modelReady ? [.green, .mint] : [.blue, .cyan]
                )
                .symbolEffect(.bounce, value: modelReady)
            }

            VStack(spacing: 14) {
                GradientText("音声認識モデルの準備", font: .title, colors: [.blue, .cyan])

                Text("高精度な文字起こしのためにモデルをダウンロードします")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if modelReady {
                SuccessBadge(text: "モデルの準備が完了しました")
                    .transition(.scale.combined(with: .opacity))
            } else if modelDownloadError {
                GradientButton("スキップ", icon: "forward.fill", colors: [.orange, .yellow]) {
                    withAnimation {
                        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                            currentStep = nextStep
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("ダウンロード中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(32)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: modelReady)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: modelDownloadError)
        .onAppear {
            downloadSpeechModels()
        }
    }

    private func downloadSpeechModels() {
        guard #available(macOS 26.0, *) else { return }
        Task {
            await downloadSpeechModelsAsync()
        }
    }

    @available(macOS 26.0, *)
    private func downloadSpeechModelsAsync() async {
        var transcribers: [SpeechTranscriber] = []
        for language in SupportedLanguage.allCases {
            let transcriber = SpeechTranscriber(
                locale: language.locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            transcribers.append(transcriber)
        }

        do {
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: transcribers) {
                try await downloader.downloadAndInstall()
            }
            await MainActor.run {
                modelReady = true
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        withAnimation {
                            if currentStep == .modelDownload {
                                if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                                    currentStep = nextStep
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                modelDownloadError = true
            }
        }
    }

    private var howToUseStep: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 14) {
                GradientText("使い方", font: .title)

                Text("シンプルな操作で音声入力")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                ModernUsageStep(
                    step: 1,
                    icon: defaultShortcutKey.iconName,
                    title: "\(defaultShortcutKey.displayName) キーを押す",
                    description: "録音が開始されます",
                    colors: [.purple, .indigo]
                )

                AnimatedArrow()

                ModernUsageStep(
                    step: 2,
                    icon: "waveform",
                    title: "話す",
                    description: "マイクに向かって話してください",
                    colors: [.blue, .cyan]
                )

                AnimatedArrow()

                ModernUsageStep(
                    step: 3,
                    icon: "keyboard",
                    title: "キーを離す",
                    description: "テキストが自動でペーストされます",
                    colors: [.green, .mint]
                )
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding(32)
    }

    private var completeStep: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.green.opacity(0.3 - Double(i) * 0.1), .mint.opacity(0.2 - Double(i) * 0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 140 + CGFloat(i) * 30, height: 140 + CGFloat(i) * 30)
                }

                GradientCircleBackground(colors: [.green, .mint], size: 140)

                GradientIcon(
                    systemName: "checkmark.circle.fill",
                    size: 64,
                    colors: [.green, .mint]
                )
                .symbolEffect(.bounce)
            }

            VStack(spacing: 14) {
                GradientText("準備完了", colors: [.green, .mint])

                Text("NiceVoice を使い始める準備ができました")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: defaultShortcutKey.iconName)
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("\(defaultShortcutKey.displayName) キーを押して録音開始")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.1), .indigo.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.3), .indigo.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )

                Text("設定からショートカットキーを変更できます")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(32)
    }

    private var navigationButtons: some View {
        HStack {
            if currentStep != .welcome {
                Button {
                    withAnimation {
                        if let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                            currentStep = prevStep
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("戻る")
                        Text("←")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.leftArrow, modifiers: [])
            }

            Spacer()

            Button {
                skipOnboarding()
            } label: {
                HStack(spacing: 6) {
                    Text("スキップ")
                    Text("esc")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .keyboardShortcut(.cancelAction)

            if currentStep == .complete {
                Button {
                    completeOnboarding()
                } label: {
                    HStack(spacing: 8) {
                        Text("始める")
                        Text("⏎")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .green.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    withAnimation {
                        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                            currentStep = nextStep
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("次へ")
                        Text("→")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(currentStep == .modelDownload && !modelReady && !modelDownloadError)
            }
        }
    }

    private func checkPermissions() {
        Task {
            microphoneGranted = await checkMicrophonePermission()
        }
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func checkMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        default:
            return false
        }
    }

    private func requestMicrophonePermission() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                microphoneGranted = granted
            }
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAccessibilityPolling() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let granted = AXIsProcessTrusted()
            if granted != accessibilityGranted {
                accessibilityGranted = granted
            }
            if granted || currentStep != .accessibility {
                timer.invalidate()
            }
        }
    }

    private func skipOnboarding() {
        completeOnboarding()
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isPresented = false
    }
}

struct ModernFeatureCard: View {
    let icon: String
    let colors: [Color]
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colors.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colors.map { $0.opacity(isHovered ? 0.4 : 0.2) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: colors.first?.opacity(0.1) ?? .clear, radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SuccessBadge: View {
    let text: LocalizedStringKey
    @State private var animate = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(animate ? 1.0 : 0.5)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.green.opacity(0.1), .mint.opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.green.opacity(0.3), .mint.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                animate = true
            }
        }
    }
}

struct ModernAccessibilityInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("設定方法")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            VStack(alignment: .leading, spacing: 10) {
                ModernInstructionStep(number: 1, text: "システム設定が開きます", color: .purple)
                ModernInstructionStep(number: 2, text: "「NiceVoice」を探してチェック", color: .indigo)
                ModernInstructionStep(number: 3, text: "パスワードを入力して許可", color: .blue)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.purple.opacity(0.2), .indigo.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

struct ModernInstructionStep: View {
    let number: Int
    let text: LocalizedStringKey
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.2), color.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)

                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }

            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct ModernUsageStep: View {
    let step: Int
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let colors: [Color]

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colors.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: colors.map { $0.opacity(0.4) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colors.map { $0.opacity(isHovered ? 0.4 : 0.2) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: colors.first?.opacity(0.1) ?? .clear, radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

extension ShortcutKey {
    var iconName: String {
        switch self {
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
