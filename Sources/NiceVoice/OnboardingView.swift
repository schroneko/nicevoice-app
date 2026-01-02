import SwiftUI
import AVFoundation
import ApplicationServices

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case accessibility
    case howToUse
    case complete
}

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep: OnboardingStep = .welcome
    @State private var animateContent = false
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    private let defaultShortcutKey: ShortcutKey = .fn

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .microphone:
                    microphoneStep
                case .accessibility:
                    accessibilityStep
                case .howToUse:
                    howToUseStep
                case .complete:
                    completeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 20)

            Divider()

            navigationButtons
                .padding(20)
        }
        .frame(width: 540, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            checkPermissions()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                animateContent = true
            }
        }
        .onChange(of: currentStep) { _, _ in
            animateContent = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                animateContent = true
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentStep)
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mic.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)

            VStack(spacing: 12) {
                Text("NiceVoice へようこそ")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("話すだけでテキストを入力できるようになります")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "waveform", color: .blue, title: "音声認識", description: "高精度なリアルタイム音声認識")
                FeatureRow(icon: "text.badge.checkmark", color: .green, title: "自動整形", description: "句読点の自動挿入とフィラー除去")
                FeatureRow(icon: "keyboard", color: .orange, title: "即座にペースト", description: "どこでもテキストを入力可能")
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding(32)
    }

    private var microphoneStep: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(microphoneGranted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: microphoneGranted ? "mic.fill" : "mic.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(microphoneGranted ? .green : .orange)
            }

            VStack(spacing: 12) {
                Text("マイクへのアクセス")
                    .font(.title)
                    .fontWeight(.bold)

                Text("音声入力にはマイクへのアクセスが必要です")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if microphoneGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("マイクのアクセスが許可されました")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } else {
                Button {
                    requestMicrophonePermission()
                } label: {
                    Label("マイクを許可する", systemImage: "mic")
                        .font(.headline)
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }

            Spacer()
        }
        .padding(32)
    }

    private var accessibilityStep: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(accessibilityGranted ? Color.green.opacity(0.1) : Color.purple.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: accessibilityGranted ? "hand.raised.fill" : "hand.raised.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(accessibilityGranted ? .green : .purple)
            }

            VStack(spacing: 12) {
                Text("アクセシビリティ")
                    .font(.title)
                    .fontWeight(.bold)

                Text("ショートカットキーの検知とテキスト入力に必要です")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if accessibilityGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("アクセシビリティが許可されました")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } else {
                VStack(spacing: 16) {
                    Button {
                        openAccessibilitySettings()
                    } label: {
                        Label("設定を開く", systemImage: "gear")
                            .font(.headline)
                            .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    AccessibilityInstructions()
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .padding(32)
        .onAppear {
            startAccessibilityPolling()
        }
    }

    private var howToUseStep: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Text("使い方")
                    .font(.title)
                    .fontWeight(.bold)

                Text("シンプルな操作で音声入力")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 20) {
                UsageStep(
                    step: 1,
                    icon: defaultShortcutKey.iconName,
                    title: "\(defaultShortcutKey.displayName) キーを押す",
                    description: "録音が開始されます"
                )

                Image(systemName: "arrow.down")
                    .font(.title2)
                    .foregroundStyle(.tertiary)

                UsageStep(
                    step: 2,
                    icon: "waveform",
                    title: "話す",
                    description: "マイクに向かって話してください"
                )

                Image(systemName: "arrow.down")
                    .font(.title2)
                    .foregroundStyle(.tertiary)

                UsageStep(
                    step: 3,
                    icon: "keyboard",
                    title: "キーを離す",
                    description: "テキストが自動でペーストされます"
                )
            }
            .padding(.horizontal, 60)

            Spacer()
        }
        .padding(32)
    }

    private var completeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce)
            }

            VStack(spacing: 12) {
                Text("準備完了")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("NiceVoice を使い始める準備ができました")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: defaultShortcutKey.iconName)
                        .font(.title2)
                    Text("\(defaultShortcutKey.displayName) キーを押して録音開始")
                        .font(.headline)
                }
                .padding()
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(12)

                Text("設定からショートカットキーを変更できます")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 16)

            Spacer()
        }
        .padding(32)
    }

    private var navigationButtons: some View {
        HStack {
            if currentStep != .welcome {
                Button("戻る") {
                    withAnimation {
                        if let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                            currentStep = prevStep
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                skipOnboarding()
            } label: {
                Text("スキップ")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if currentStep == .complete {
                Button("始める") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button("次へ") {
                    withAnimation {
                        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                            currentStep = nextStep
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AccessibilityInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("設定方法")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 8) {
                InstructionStep(number: 1, text: "システム設定が開きます")
                InstructionStep(number: 2, text: "「NiceVoice」を探してチェックを入れる")
                InstructionStep(number: 3, text: "パスワードを入力して許可")
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

struct InstructionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct UsageStep: View {
    let step: Int
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(16)
    }
}

extension ShortcutKey {
    var iconName: String {
        switch self {
        case .fn: return "fn"
        case .leftShift, .rightShift: return "shift"
        case .leftControl, .rightControl: return "control"
        case .leftOption, .rightOption: return "option"
        case .leftCommand, .rightCommand: return "command"
        }
    }
}
