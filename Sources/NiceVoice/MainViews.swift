import SwiftUI

enum NavigationPage: String, CaseIterable {
    case overview = "概要"
    case transcription = "文字起こし"
    case history = "履歴"
    case dictionary = "辞書"
    case settings = "設定"

    var icon: String {
        switch self {
        case .overview: return "chart.bar"
        case .transcription: return "waveform.and.mic"
        case .history: return "clock"
        case .dictionary: return "book"
        case .settings: return "gearshape"
        }
    }
}

struct MainWindowView: View {
    var appState: AppState
    @State private var selectedPage: NavigationPage = .overview
    @State private var showOnboarding: Bool

    init(appState: AppState) {
        self.appState = appState
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        _showOnboarding = State(initialValue: !hasCompleted)
    }

    var body: some View {
        NavigationSplitView {
            List(NavigationPage.allCases, id: \.self, selection: $selectedPage) { page in
                Label(page.rawValue, systemImage: page.icon)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        } detail: {
            switch selectedPage {
            case .overview:
                OverviewView(appState: appState)
            case .transcription:
                BatchTranscriptionView(appState: appState)
            case .history:
                HistoryContentView(appState: appState)
            case .dictionary:
                DictionaryView(appState: appState)
            case .settings:
                SettingsContentView(appState: appState)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }
}

struct OverviewView: View {
    var appState: AppState
    @State private var animateCards = false

    private var estimatedCost: Double {
        Double(appState.usageStats.totalTokensUsed) * 0.0000005
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("概要")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("音声認識の使用状況")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(isReady: appState.isReady, isRecording: appState.isRecording)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    StatCard(
                        title: "今日の変換",
                        value: "\(appState.usageStats.todayConversions)",
                        subtitle: "\(appState.usageStats.todayCharacters) 文字",
                        icon: "waveform",
                        color: .blue
                    )
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 20)

                    StatCard(
                        title: "累計変換",
                        value: "\(appState.usageStats.totalConversions)",
                        subtitle: "\(appState.usageStats.totalCharacters) 文字",
                        icon: "chart.line.uptrend.xyaxis",
                        color: .green
                    )
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 20)

                    StatCard(
                        title: "推定コスト",
                        value: String(format: "$%.4f", estimatedCost),
                        subtitle: String(format: "約 %.1f 円", estimatedCost * 150),
                        icon: "yensign.circle",
                        color: .orange
                    )
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 20)
                }

                RecentTranscriptionsCard(appState: appState)
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 20)

                Spacer()
            }
            .padding(28)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                animateCards = true
            }
        }
    }
}

struct StatusBadge: View {
    let isReady: Bool
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.1))
        .cornerRadius(20)
    }

    private var statusColor: Color {
        if isRecording { return .red }
        if isReady { return .green }
        return .orange
    }

    private var statusText: String {
        if isRecording { return "録音中" }
        if isReady { return "準備完了" }
        return "初期化中"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    var trend: Double? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                if let trend = trend {
                    HStack(spacing: 2) {
                        Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.weight(.bold))
                        Text("\(abs(Int(trend)))%")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(trend >= 0 ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background((trend >= 0 ? Color.green : Color.red).opacity(0.1))
                    .cornerRadius(6)
                }
            }

            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 12 : 8, y: isHovered ? 4 : 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
