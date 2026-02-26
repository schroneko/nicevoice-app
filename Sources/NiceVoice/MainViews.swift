import SwiftUI

enum NavigationPage: String, CaseIterable {
    case overview
    case transcription
    case history
    case dictionary
    case plan
    case settings
    case developer

    var localizedName: String {
        switch self {
        case .overview: return String(localized: "概要")
        case .transcription: return String(localized: "文字起こし")
        case .history: return String(localized: "履歴")
        case .dictionary: return String(localized: "辞書")
        case .plan: return String(localized: "プラン")
        case .settings: return String(localized: "設定")
        case .developer: return String(localized: "開発者")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.bar.fill"
        case .transcription: return "waveform.badge.mic"
        case .history: return "clock.fill"
        case .dictionary: return "character.book.closed.fill"
        case .plan: return "creditcard.fill"
        case .settings: return "gearshape.fill"
        case .developer: return "hammer.fill"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .overview:
            return LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .transcription:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .history:
            return LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dictionary:
            return LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .plan:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .settings:
            return LinearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .developer:
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct MainWindowView: View {
    var appState: AppState
    @State private var selectedPage: NavigationPage = .overview
    @State private var showOnboarding: Bool
    @State private var hoveredPage: NavigationPage?

    init(appState: AppState) {
        self.appState = appState
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        _showOnboarding = State(initialValue: !hasCompleted)
    }

    var body: some View {
        if showOnboarding {
            OnboardingView(isPresented: $showOnboarding)
                .frame(minWidth: 560, minHeight: 720)
        } else {
            NavigationSplitView {
                VStack(spacing: 8) {
                    ForEach(NavigationPage.allCases, id: \.self) { page in
                        SidebarItem(
                            page: page,
                            isSelected: selectedPage == page,
                            isHovered: hoveredPage == page
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedPage = page
                            }
                        }
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredPage = hovering ? page : nil
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            } detail: {
                ZStack {
                    MeshGradientBackground()

                    switch selectedPage {
                    case .overview:
                        OverviewView(appState: appState)
                    case .transcription:
                        BatchTranscriptionView(appState: appState)
                    case .history:
                        HistoryContentView(appState: appState)
                    case .dictionary:
                        DictionaryView(appState: appState)
                    case .plan:
                        PlanContentView()
                    case .settings:
                        SettingsContentView(appState: appState)
                    case .developer:
                        DeveloperView(appState: appState)
                    }
                }
            }
            .frame(minWidth: 750, minHeight: 550)
        }
    }
}

struct SidebarItem: View {
    let page: NavigationPage
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: 24, height: 24)

            Text(page.localizedName)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : .primary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(page.gradient)
                    .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
            }
        }
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }
}

struct MeshGradientBackground: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                .purple.opacity(0.05), .indigo.opacity(0.03), .blue.opacity(0.05),
                .indigo.opacity(0.03), .clear, .purple.opacity(0.03),
                .blue.opacity(0.05), .purple.opacity(0.03), .indigo.opacity(0.05)
            ]
        )
        .ignoresSafeArea()
    }
}

struct OverviewView: View {
    var appState: AppState
    @State private var cardAnimationStates: [Bool] = [false, false, false, false]

    private var estimatedCost: Double {
        Double(appState.usageStats.totalTokensUsed) * 0.0000005
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("概要")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .indigo, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("音声認識の使用状況")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(isReady: appState.isReady, isRecording: appState.isRecording)
                }
                .opacity(cardAnimationStates[0] ? 1 : 0)
                .offset(y: cardAnimationStates[0] ? 0 : 15)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ], spacing: 20) {
                    StatCard(
                        title: String(localized: "今日の変換"),
                        value: "\(appState.usageStats.todayConversions)",
                        subtitle: String(localized: "\(appState.usageStats.todayCharacters) 文字"),
                        icon: "waveform",
                        color: .blue,
                        secondaryColor: .cyan
                    )
                    .opacity(cardAnimationStates[1] ? 1 : 0)
                    .offset(y: cardAnimationStates[1] ? 0 : 20)

                    StatCard(
                        title: String(localized: "累計変換"),
                        value: "\(appState.usageStats.totalConversions)",
                        subtitle: String(localized: "\(appState.usageStats.totalCharacters) 文字"),
                        icon: "chart.line.uptrend.xyaxis",
                        color: .green,
                        secondaryColor: .teal
                    )
                    .opacity(cardAnimationStates[1] ? 1 : 0)
                    .offset(y: cardAnimationStates[1] ? 0 : 20)

                    StatCard(
                        title: String(localized: "推定コスト"),
                        value: String(format: "$%.4f", estimatedCost),
                        subtitle: String(format: String(localized: "約 %.1f 円"), estimatedCost * 150),
                        icon: "yensign.circle",
                        color: .orange,
                        secondaryColor: .pink
                    )
                    .opacity(cardAnimationStates[1] ? 1 : 0)
                    .offset(y: cardAnimationStates[1] ? 0 : 20)
                }

                RecentTranscriptionsCard(appState: appState)
                    .opacity(cardAnimationStates[2] ? 1 : 0)
                    .offset(y: cardAnimationStates[2] ? 0 : 20)

                Spacer()
            }
            .padding(32)
        }
        .onAppear {
            animateCardsSequentially()
        }
    }

    private func animateCardsSequentially() {
        let delays: [Double] = [0.1, 0.2, 0.35, 0.5]
        for (index, delay) in delays.enumerated() {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(delay)) {
                cardAnimationStates[index] = true
            }
        }
    }
}

struct StatusBadge: View {
    let isReady: Bool
    let isRecording: Bool

    @State private var pulseAnimation = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(statusColor.opacity(0.3))
                        .frame(width: 16, height: 16)
                        .scaleEffect(pulseAnimation ? 1.5 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.6)
                }
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.5), radius: 4)
            }
            .frame(width: 16, height: 16)

            Text(statusText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .stroke(statusColor.opacity(0.3), lineWidth: 1)
                }
                .shadow(color: statusColor.opacity(0.2), radius: 8, y: 4)
        }
        .onAppear {
            if isRecording {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    pulseAnimation = true
                }
            }
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    pulseAnimation = true
                }
            } else {
                pulseAnimation = false
            }
        }
    }

    private var statusColor: Color {
        if isRecording { return .red }
        if isReady { return .green }
        return .orange
    }

    private var statusText: String {
        if isRecording { return String(localized: "録音中") }
        if isReady { return String(localized: "準備完了") }
        return String(localized: "初期化中")
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    var secondaryColor: Color? = nil
    var trend: Double? = nil

    @State private var isHovered = false

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [color, secondaryColor ?? color.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(gradient.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(gradient)
                }

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if let trend = trend {
                    HStack(spacing: 3) {
                        Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.weight(.bold))
                        Text("\(abs(Int(trend)))%")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(trend >= 0 ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill((trend >= 0 ? Color.green : Color.red).opacity(0.12))
                    }
                }
            }

            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: color.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 16 : 10, y: isHovered ? 6 : 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(isHovered ? 0.4 : 0.2), (secondaryColor ?? color).opacity(isHovered ? 0.2 : 0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
