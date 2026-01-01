import AppKit

final class KeyMonitor {
    private var monitor: Any?
    private var isKeyPressed = false
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void
    private var shortcutKey: ShortcutKey

    init(shortcutKey: ShortcutKey = .fn, onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.shortcutKey = shortcutKey
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        startMonitoring()
    }

    func updateShortcutKey(_ newKey: ShortcutKey) {
        guard newKey != shortcutKey else { return }
        shortcutKey = newKey
        isKeyPressed = false
        stopMonitoring()
        startMonitoring()
        debugLog("🔄 Shortcut key changed to: \(newKey.displayName)")
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func startMonitoring() {
        debugLog("🔍 [DEBUG] KeyMonitor startMonitoring called for: \(shortcutKey.displayName)")
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let keyPressed = self.isShortcutKeyPressed(event: event)

            if keyPressed && !self.isKeyPressed {
                debugLog("🔍 [DEBUG] \(self.shortcutKey.displayName) key DOWN detected")
                self.isKeyPressed = true
                DispatchQueue.main.async {
                    debugLog("🔍 [DEBUG] Calling onKeyDown callback")
                    self.onKeyDown()
                }
            } else if !keyPressed && self.isKeyPressed {
                debugLog("🔍 [DEBUG] \(self.shortcutKey.displayName) key UP detected")
                self.isKeyPressed = false
                DispatchQueue.main.async {
                    debugLog("🔍 [DEBUG] Calling onKeyUp callback")
                    self.onKeyUp()
                }
            }
        }

        if monitor == nil {
            debugLog("⚠️ アクセシビリティ権限が必要です - monitor is nil")
        } else {
            debugLog("✅ KeyMonitor started successfully for: \(shortcutKey.displayName)")
        }
    }

    private func isShortcutKeyPressed(event: NSEvent) -> Bool {
        let hasModifier = event.modifierFlags.contains(shortcutKey.modifierFlag)
        if shortcutKey == .fn {
            return hasModifier
        }
        return hasModifier && event.keyCode == shortcutKey.keyCode
    }

    deinit {
        stopMonitoring()
    }
}
