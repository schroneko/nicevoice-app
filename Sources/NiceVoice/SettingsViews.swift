import SwiftUI

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
