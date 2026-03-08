import SwiftUI

enum NavigationPage: String, CaseIterable {
    case transcription
    case history
    case dictionary
    case account
    case settings
    case developer

    var localizedName: String {
        switch self {
        case .transcription: return String(localized: "文字起こし")
        case .history: return String(localized: "履歴")
        case .dictionary: return String(localized: "辞書")
        case .account: return String(localized: "アカウント")
        case .settings: return String(localized: "設定")
        case .developer: return String(localized: "開発者")
        }
    }

    var icon: String {
        switch self {
        case .transcription: return "waveform.badge.mic"
        case .history: return "clock.fill"
        case .dictionary: return "character.book.closed.fill"
        case .account: return "person.crop.circle.fill"
        case .settings: return "gearshape.fill"
        case .developer: return "hammer.fill"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .transcription:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .history:
            return LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dictionary:
            return LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .account:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .settings:
            return LinearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .developer:
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    static var visiblePages: [NavigationPage] {
        let basePages: [NavigationPage] = [
            .transcription,
            .history,
            .dictionary,
            .account,
            .settings
        ]
        return AppFeatureFlags.isDeveloperToolsEnabled()
            ? basePages + [.developer]
            : basePages
    }
}

struct MainWindowView: View {
    var appState: AppState
    @State private var selectedPage: NavigationPage = .settings
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
                    ForEach(NavigationPage.visiblePages, id: \.self) { page in
                        SidebarItem(
                            page: page,
                            isSelected: selectedPage == page,
                            isHovered: hoveredPage == page
                        ) {
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
                    case .transcription:
                        if AuthManager.shared.canUseApp {
                            BatchTranscriptionView(appState: appState)
                        } else {
                            AuthRequiredView {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedPage = .account
                                }
                            }
                        }
                    case .history:
                        HistoryContentView(appState: appState)
                    case .dictionary:
                        DictionaryView(appState: appState)
                    case .account:
                        AccountContentView()
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
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: 24, height: 24)

            Text(page.localizedName)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page.localizedName)
        .accessibilityAddTraits(.isButton)
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }
}

struct AuthRequiredView: View {
    var onNavigateToAccount: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text("サブスクリプションが必要です")
                    .font(.title2.weight(.semibold))

                Text("この機能を使用するにはログインしてください")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                onNavigateToAccount()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                    Text("アカウントページへ")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
