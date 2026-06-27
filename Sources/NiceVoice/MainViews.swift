import SwiftUI

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case transcription
    case voice
    case about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .transcription: return "Transcription"
        case .voice: return "Voice"
        case .about: return "About"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .transcription: return "text.alignleft"
        case .voice: return "person.wave.2.fill"
        case .about: return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: return .blue
        case .transcription: return .purple
        case .voice: return .teal
        case .about: return .cyan
        }
    }
}

extension Notification.Name {
    static let openPreferencesTab = Notification.Name("openPreferencesTab")
}

struct MainWindowView: View {
    var appState: AppState
    @State private var selectedTab: PreferencesTab = .general
    @State private var showOnboarding: Bool

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
            SettingsWindowView(appState: appState, selectedTab: $selectedTab)
                .frame(minWidth: 780, minHeight: 620)
                .background(SettingsStyle.windowBackground)
            .onReceive(NotificationCenter.default.publisher(for: .openPreferencesTab)) { notification in
                guard let rawValue = notification.object as? String,
                      let tab = PreferencesTab(rawValue: rawValue) else {
                    return
                }
                selectedTab = tab
            }
        }
    }
}

struct SettingsWindowView: View {
    var appState: AppState
    @Binding var selectedTab: PreferencesTab

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarView(selectedTab: $selectedTab)
                .frame(width: 280)

            Rectangle()
                .fill(SettingsStyle.divider)
                .frame(width: 1)

            SettingsContentView(appState: appState, selectedPane: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SettingsSidebarView: View {
    @Binding var selectedTab: PreferencesTab

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(PreferencesTab.allCases) { tab in
                SettingsSidebarRow(tab: tab, isSelected: selectedTab == tab) {
                    selectedTab = tab
                }

                if tab == .voice {
                    Rectangle()
                        .fill(SettingsStyle.divider)
                        .frame(height: 1)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .background(SettingsStyle.sidebarBackground)
    }
}

struct SettingsSidebarRow: View {
    let tab: PreferencesTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.18) : tab.iconColor.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: tab.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : tab.iconColor)
                }

                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.white.opacity(0.06) : Color.clear))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
