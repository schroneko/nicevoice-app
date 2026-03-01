import AppKit

enum ShortcutKey: String, CaseIterable {
    case fn = "fn"
    case leftShift = "leftShift"
    case rightShift = "rightShift"
    case leftControl = "leftControl"
    case rightControl = "rightControl"
    case leftOption = "leftOption"
    case rightOption = "rightOption"
    case leftCommand = "leftCommand"
    case rightCommand = "rightCommand"

    var displayName: String {
        switch self {
        case .fn: return "fn"
        case .leftShift: return String(localized: "左 Shift")
        case .rightShift: return String(localized: "右 Shift")
        case .leftControl: return String(localized: "左 Control")
        case .rightControl: return String(localized: "右 Control")
        case .leftOption: return String(localized: "左 Option")
        case .rightOption: return String(localized: "右 Option")
        case .leftCommand: return String(localized: "左 Command")
        case .rightCommand: return String(localized: "右 Command")
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .fn: return 63
        case .leftShift: return 56
        case .rightShift: return 60
        case .leftControl: return 59
        case .rightControl: return 62
        case .leftOption: return 58
        case .rightOption: return 61
        case .leftCommand: return 55
        case .rightCommand: return 54
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .leftShift, .rightShift: return .shift
        case .leftControl, .rightControl: return .control
        case .leftOption, .rightOption: return .option
        case .leftCommand, .rightCommand: return .command
        }
    }

    var deviceDependentFlag: UInt {
        switch self {
        case .fn: return 0
        case .leftShift: return 0x00000002
        case .rightShift: return 0x00000004
        case .leftControl: return 0x00000001
        case .rightControl: return 0x00002000
        case .leftOption: return 0x00000020
        case .rightOption: return 0x00000040
        case .leftCommand: return 0x00000008
        case .rightCommand: return 0x00000010
        }
    }
}

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
        if shortcutKey == .fn {
            return event.modifierFlags.contains(.function)
        }
        return event.modifierFlags.rawValue & shortcutKey.deviceDependentFlag != 0
    }

    deinit {
        stopMonitoring()
    }
}
