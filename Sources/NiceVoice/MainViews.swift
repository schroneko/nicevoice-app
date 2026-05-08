import SwiftUI

enum PreferencesTab: String {
    case general
    case dictionary
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
            TabView(selection: $selectedTab) {
                SettingsContentView(appState: appState)
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }
                    .tag(PreferencesTab.general)

                DictionaryView(appState: appState)
                    .tabItem {
                        Label("Dictionary", systemImage: "character.book.closed")
                    }
                    .tag(PreferencesTab.dictionary)
            }
            .frame(minWidth: 680, minHeight: 560)
            .background(Color(nsColor: .windowBackgroundColor))
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
