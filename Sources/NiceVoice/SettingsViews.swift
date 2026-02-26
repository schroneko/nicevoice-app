import SwiftUI
import AVFoundation
import AppKit

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
    @State private var sectionAnimations: [Bool] = [false, false, false, false]

    private var selectedShortcutKey: ShortcutKey {
        ShortcutKey(rawValue: shortcutKeyRaw) ?? .fn
    }

    init(appState: AppState) {
        self.appState = appState
        _fillerSettings = State(initialValue: appState.fillerSettings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("設定")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("アプリの動作をカスタマイズ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                SettingsSection(
                    title: "権限",
                    icon: "lock.shield.fill",
                    gradientColors: [.green, .teal]
                ) {
                    PermissionStatusView()
                }
                .opacity(sectionAnimations[0] ? 1 : 0)
                .offset(y: sectionAnimations[0] ? 0 : 16)

                SettingsSection(
                    title: "一般",
                    icon: "gearshape.fill",
                    gradientColors: [.gray, .gray.opacity(0.7)]
                ) {
                    SettingsToggleRow(
                        title: "メニューバーに常駐する",
                        description: "オフにすると Dock からのみ起動できます",
                        isOn: $showInMenuBar
                    )

                    SectionDivider()

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("ショートカットキー")
                                .font(.callout)
                                .fontWeight(.medium)
                            Text("録音を開始・停止するキー")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
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
                .opacity(sectionAnimations[1] ? 1 : 0)
                .offset(y: sectionAnimations[1] ? 0 : 16)

                SettingsSection(
                    title: "書き起こし調整",
                    icon: "text.alignleft",
                    gradientColors: [.purple, .indigo]
                ) {
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
                }
                .opacity(sectionAnimations[2] ? 1 : 0)
                .offset(y: sectionAnimations[2] ? 0 : 16)

                SettingsSection(
                    title: "フィラー除去",
                    icon: "text.badge.minus",
                    gradientColors: [.orange, .pink]
                ) {
                    SettingsToggleRow(
                        title: "フィラーを除去する",
                        description: "「えー」「あー」などの言葉を自動で除去します",
                        isOn: $fillerSettings.removeFillers
                    )
                    .onChange(of: fillerSettings.removeFillers) { _, _ in
                        appState.updateFillerSettings(fillerSettings)
                    }
                }
                .opacity(sectionAnimations[3] ? 1 : 0)
                .offset(y: sectionAnimations[3] ? 0 : 16)

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

struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let gradientColors: [Color]
    @ViewBuilder let content: Content
    @State private var isHovered = false

    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconGradient)
                        .frame(width: 32, height: 32)
                        .shadow(color: gradientColors[0].opacity(0.3), radius: 4, y: 2)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .padding(.bottom, 18)

            content
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .secondary.opacity(0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.vertical, 10)
    }
}

struct SettingsToggleRow: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
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
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.purple)
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

struct ModernAddButton: View {
    let disabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    private let gradient = LinearGradient(
        colors: [.purple, .indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(disabled ? AnyShapeStyle(Color.secondary.opacity(0.3)) : AnyShapeStyle(gradient))
                }
                .shadow(
                    color: disabled ? .clear : .purple.opacity(isHovered ? 0.4 : 0.2),
                    radius: isHovered ? 8 : 4,
                    y: isHovered ? 4 : 2
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .scaleEffect(isHovered && !disabled ? 1.05 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
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
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }
}

struct ModernFillerChip: View {
    let text: String
    var isSelected: Bool = true
    var canDelete: Bool = false
    var gradientColors: [Color] = [.purple, .indigo]
    let action: () -> Void

    @State private var isHovered = false

    private var chipGradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(text)
                    .font(.caption)
                    .fontWeight(.semibold)
                if canDelete {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(chipGradient.opacity(0.2)) : AnyShapeStyle(Color.secondary.opacity(0.08)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? AnyShapeStyle(chipGradient.opacity(0.5)) : AnyShapeStyle(Color.clear),
                        lineWidth: 1.5
                    )
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .shadow(
                color: isSelected ? gradientColors[0].opacity(0.15) : .clear,
                radius: 3,
                y: 1
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.06 : 1.0)
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

struct PermissionStatusView: View {
    @State private var microphoneStatus: Bool = false
    @State private var accessibilityStatus: Bool = false

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
                action: { openSystemPreferences("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }
            )
        }
        .onAppear { checkPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermissions()
        }
    }

    private func checkPermissions() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityStatus = AXIsProcessTrusted()
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

struct PlanContentView: View {
    @State private var sectionAnimations: [Bool] = [false]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("プラン")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("ライセンスの管理")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                SettingsSection(
                    title: "ライセンス",
                    icon: "creditcard.fill",
                    gradientColors: [.blue, .cyan]
                ) {
                    PlanStatusView()
                }
                .opacity(sectionAnimations[0] ? 1 : 0)
                .offset(y: sectionAnimations[0] ? 0 : 16)

                Spacer(minLength: 20)
            }
            .padding(32)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                sectionAnimations[0] = true
            }
        }
    }
}

struct PlanStatusView: View {
    private var licenseManager: LicenseManager { LicenseManager.shared }
    private var usageTracker: UsageTracker { UsageTracker.shared }
    @State private var licenseKeyInput = ""
    @State private var isActivating = false
    @State private var activationError: String?
    @State private var activationSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(licenseManager.effectivePlan.displayName)
                            .font(.title3)
                            .fontWeight(.bold)

                        if licenseManager.isTrialActive {
                            Text("トライアル")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }

                    if licenseManager.isTrialActive {
                        Text("残り \(licenseManager.trialDaysRemaining) 日")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let days = licenseManager.licenseInfo?.daysUntilExpiration {
                        Text("次回更新まで \(days) 日")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if licenseManager.subscriptionStatus == .active {
                    Button {
                        Task {
                            try? await licenseManager.manageSubscription()
                        }
                    } label: {
                        Text("プラン管理")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if licenseManager.subscriptionStatus != .active {
                SectionDivider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("ライセンスキー")
                        .font(.callout)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $licenseKeyInput)
                            .textFieldStyle(.plain)
                            .font(.system(.caption, design: .monospaced))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                            .disabled(isActivating)

                        Button {
                            activateLicense()
                        } label: {
                            if isActivating {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 80, height: 32)
                            } else {
                                Text("有効化")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .frame(width: 80, height: 32)
                                    .background(
                                        LinearGradient(
                                            colors: [.purple, .indigo],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
                    }

                    if let error = activationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if activationSuccess {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("ライセンスが有効化されました")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }

            if licenseManager.effectivePlan == .free && !licenseManager.isTrialActive {
                SectionDivider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("今月の使用量")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(usageTracker.creditsUsed) / 300 クレジット")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: usageTracker.usagePercentage > 0.8 ? [.orange, .red] : [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * usageTracker.usagePercentage, height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(usageTracker.daysUntilReset) 日後にリセット")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func activateLicense() {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        isActivating = true
        activationError = nil
        activationSuccess = false

        Task {
            do {
                try await licenseManager.activateWithKey(key)
                await MainActor.run {
                    isActivating = false
                    activationSuccess = true
                    licenseKeyInput = ""
                }
            } catch {
                await MainActor.run {
                    isActivating = false
                    activationError = error.localizedDescription
                }
            }
        }
    }
}


