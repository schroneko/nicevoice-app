import SwiftUI
import AppKit

extension Notification.Name {
    static let recordingStateChanged = Notification.Name("recordingStateChanged")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    private var advancedTranscriptionWindow: NSWindow?
    private var developerToolsWindow: NSWindow?

    @AppStorage("showInMenuBar") var showInMenuBar = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("✅ NiceVoice started")
        checkAccessibilityPermission()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarSettingChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(recordingStateChanged),
            name: .recordingStateChanged,
            object: nil
        )
    }

    @objc private func recordingStateChanged() {
        updateStatusItemIcon()
    }

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        debugLog("🔐 Accessibility permission: \(trusted)")
    }

    private func setupStatusItem() {
        guard showInMenuBar else {
            statusItem = nil
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Nice Voice")
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        updateStatusItemIcon()
    }

    func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let iconName = appState.isRecording ? "mic.fill" : "mic"
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Nice Voice")
        button.contentTintColor = appState.isRecording ? .systemRed : nil
    }

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        showStatusMenu()
    }

    private func openMainWindow(tab: PreferencesTab = .general) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = preferencesWindow ?? NSApp.windows.first(where: { $0.title == "Preferences" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Preferences"
            window.center()
            window.contentView = NSHostingView(rootView: MainWindowView(appState: appState))
            preferencesWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .openPreferencesTab, object: tab.rawValue)
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: appState.statusMessage, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        addRecentHistoryItems(to: menu)

        menu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(title: String(localized: "Preferences..."), action: #selector(openPreferencesAction), keyEquivalent: ",")
        preferencesItem.keyEquivalentModifierMask = .command
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let advancedItem = NSMenuItem(title: String(localized: "Advanced Transcription..."), action: #selector(openAdvancedTranscriptionAction), keyEquivalent: "a")
        advancedItem.keyEquivalentModifierMask = [.command, .option]
        advancedItem.target = self
        menu.addItem(advancedItem)

        if AppFeatureFlags.isDeveloperToolsEnabled() {
            let developerItem = NSMenuItem(title: String(localized: "Developer Tools..."), action: #selector(openDeveloperToolsAction), keyEquivalent: "i")
            developerItem.keyEquivalentModifierMask = [.command, .option]
            developerItem.target = self
            menu.addItem(developerItem)
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: String(localized: "終了"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func addRecentHistoryItems(to menu: NSMenu) {
        let recentRecords = Array(appState.history.prefix(5))
        if recentRecords.isEmpty {
            let emptyItem = NSMenuItem(title: String(localized: "最近の文字起こしはありません"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        let headerItem = NSMenuItem(title: String(localized: "最近の文字起こし"), action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        for record in recentRecords {
            let item = NSMenuItem(title: menuTitle(for: record), action: #selector(copyRecentHistoryItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = record.text
            menu.addItem(item)
        }
    }

    private func menuTitle(for record: TranscriptionRecord) -> String {
        let text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 36 else { return text }
        return "\(text.prefix(36))..."
    }

    @objc private func copyRecentHistoryItem(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        appState.copyHistoryItem(text)
    }

    @objc private func openPreferencesAction() {
        openMainWindow(tab: .general)
    }

    @objc private func openAdvancedTranscriptionAction() {
        openAdvancedTranscriptionWindow()
    }

    @objc private func openDeveloperToolsAction() {
        openDeveloperToolsWindow()
    }

    private func openAdvancedTranscriptionWindow() {
        showAuxiliaryWindow(
            storedWindow: &advancedTranscriptionWindow,
            title: "Advanced Transcription",
            width: 900,
            height: 640
        ) {
            AnyView(BatchTranscriptionView(appState: appState))
        }
    }

    private func openDeveloperToolsWindow() {
        showAuxiliaryWindow(
            storedWindow: &developerToolsWindow,
            title: "Developer Tools",
            width: 820,
            height: 680
        ) {
            AnyView(DeveloperView(appState: appState))
        }
    }

    private func showAuxiliaryWindow(
        storedWindow: inout NSWindow?,
        title: String,
        width: CGFloat,
        height: CGFloat,
        content: () -> AnyView
    ) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = storedWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.contentView = NSHostingView(rootView: content())
        window.isReleasedWhenClosed = false
        storedWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func menuBarSettingChanged() {
        let newValue = UserDefaults.standard.bool(forKey: "showInMenuBar")
        if newValue && statusItem == nil {
            setupStatusItem()
        } else if !newValue && statusItem != nil {
            NSStatusBar.system.removeStatusItem(statusItem!)
            statusItem = nil
        }
    }
}
