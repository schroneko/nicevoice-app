import SwiftUI

@main
struct NiceVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    @StateObject private var updateManager = AppUpdateManager.shared

    private var resolvedLocale: Locale {
        let lang = AppLanguage(rawValue: appLanguageRaw) ?? .system
        return lang.locale ?? Locale.current
    }

    var body: some Scene {
        Window("Preferences", id: "main") {
            MainWindowView(appState: appDelegate.appState)
                .environment(\.locale, resolvedLocale)
                .id(appLanguageRaw)
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                if updateManager.isConfigured {
                    Button(updateManager.primaryActionTitle) {
                        updateManager.performPrimaryAction()
                    }
                    .keyboardShortcut("u", modifiers: [.command, .option])
                    .disabled(!updateManager.canPerformPrimaryAction)
                }
            }
        }
    }
}
