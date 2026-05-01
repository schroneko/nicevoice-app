import AppKit
import ApplicationServices
import Carbon

enum ShortcutKey: String, CaseIterable {
    case space = "space"
    case fn = "fn"
    case custom = "custom"
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
        case .space: return "Space"
        case .fn: return "fn"
        case .custom: return String(localized: "カスタム")
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
        case .space: return 49
        case .fn: return 63
        case .custom: return 0
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

    var deviceDependentFlag: UInt {
        switch self {
        case .space: return 0
        case .fn: return 0
        case .custom: return 0
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

    var usesLongPressBehavior: Bool {
        self == .space
    }

    var usesCustomKeyCombinationBehavior: Bool {
        self == .custom
    }

    var longPressDelay: TimeInterval? {
        switch self {
        case .space:
            return 0.45
        default:
            return nil
        }
    }

    func usageDescription(customShortcut: CustomShortcut) -> String {
        switch self {
        case .space:
            return String(localized: "Space を長押しして録音")
        case .custom:
            return String(localized: "\(customShortcut.displayName) を押して録音")
        default:
            return String(localized: "\(displayName) キーを押して録音")
        }
    }
}

struct CustomShortcut: RawRepresentable, Equatable {
    let keyCode: UInt16
    let modifierFlagsRawValue: UInt
    let keyDisplayName: String

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, keyDisplayName: String) {
        self.keyCode = keyCode
        self.modifierFlagsRawValue = Self.normalizedModifierFlags(modifierFlags).rawValue
        self.keyDisplayName = keyDisplayName
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let keyCode = UInt16(parts[0]),
              let modifierRawValue = UInt(parts[1]) else {
            return nil
        }

        self.keyCode = keyCode
        modifierFlagsRawValue = modifierRawValue
        keyDisplayName = String(parts[2]).removingPercentEncoding ?? String(parts[2])
    }

    var rawValue: String {
        let encodedDisplayName = keyDisplayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyDisplayName
        return "\(keyCode)|\(modifierFlags.rawValue)|\(encodedDisplayName)"
    }

    var modifierFlags: NSEvent.ModifierFlags {
        Self.normalizedModifierFlags(NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue))
    }

    var displayName: String {
        let modifierNames = Self.modifierDisplayNames(for: modifierFlags)
        if modifierNames.isEmpty {
            return keyDisplayName
        }
        return (modifierNames + [keyDisplayName]).joined(separator: " + ")
    }

    var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0
        if modifierFlags.contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if modifierFlags.contains(.option) {
            flags |= UInt32(optionKey)
        }
        if modifierFlags.contains(.control) {
            flags |= UInt32(controlKey)
        }
        if modifierFlags.contains(.shift) {
            flags |= UInt32(shiftKey)
        }
        return flags
    }

    func matches(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        keyCode == self.keyCode && Self.normalizedModifierFlags(modifierFlags) == self.modifierFlags
    }

    func hasRequiredModifiers(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let normalized = Self.normalizedModifierFlags(modifierFlags)
        return normalized.intersection(self.modifierFlags) == self.modifierFlags
    }

    func usesModifierKeyCode(_ keyCode: UInt16) -> Bool {
        Self.modifierKeyCodes(for: modifierFlags).contains(keyCode)
    }

    static let defaultValue = CustomShortcut(
        keyCode: UInt16(kVK_ANSI_M),
        modifierFlags: [.control],
        keyDisplayName: "M"
    )

    static func capture(from event: NSEvent) -> CustomShortcut? {
        let modifiers = normalizedModifierFlags(event.modifierFlags)
        guard !modifiers.isEmpty else { return nil }
        guard !isModifierOnlyKeyCode(event.keyCode) else { return nil }

        let keyDisplayName = displayName(for: event)
        guard !keyDisplayName.isEmpty else { return nil }

        return CustomShortcut(
            keyCode: event.keyCode,
            modifierFlags: modifiers,
            keyDisplayName: keyDisplayName
        )
    }

    static func normalizedModifierFlags(_ modifierFlags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        modifierFlags.intersection([.command, .option, .control, .shift, .function])
    }

    static func modifierDisplayNames(for modifierFlags: NSEvent.ModifierFlags) -> [String] {
        var names: [String] = []
        if modifierFlags.contains(.control) {
            names.append("Ctrl")
        }
        if modifierFlags.contains(.option) {
            names.append("Option")
        }
        if modifierFlags.contains(.shift) {
            names.append("Shift")
        }
        if modifierFlags.contains(.command) {
            names.append("Command")
        }
        if modifierFlags.contains(.function) {
            names.append("Fn")
        }
        return names
    }

    static func modifierKeyCodes(for modifierFlags: NSEvent.ModifierFlags) -> Set<UInt16> {
        var keyCodes: Set<UInt16> = []
        if modifierFlags.contains(.control) {
            keyCodes.formUnion([UInt16(kVK_Control), UInt16(kVK_RightControl)])
        }
        if modifierFlags.contains(.option) {
            keyCodes.formUnion([UInt16(kVK_Option), UInt16(kVK_RightOption)])
        }
        if modifierFlags.contains(.shift) {
            keyCodes.formUnion([UInt16(kVK_Shift), UInt16(kVK_RightShift)])
        }
        if modifierFlags.contains(.command) {
            keyCodes.formUnion([UInt16(kVK_Command), UInt16(kVK_RightCommand)])
        }
        if modifierFlags.contains(.function) {
            keyCodes.insert(63)
        }
        return keyCodes
    }

    static func isModifierOnlyKeyCode(_ keyCode: UInt16) -> Bool {
        modifierOnlyKeyCodes.contains(keyCode)
    }

    private static let modifierOnlyKeyCodes: Set<UInt16> = [
        UInt16(kVK_Shift),
        UInt16(kVK_RightShift),
        UInt16(kVK_Control),
        UInt16(kVK_RightControl),
        UInt16(kVK_Option),
        UInt16(kVK_RightOption),
        UInt16(kVK_Command),
        UInt16(kVK_RightCommand),
        UInt16(kVK_CapsLock),
        63
    ]

    private static func displayName(for event: NSEvent) -> String {
        if let specialName = specialKeyDisplayName(for: event.keyCode) {
            return specialName
        }

        if let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .controlCharacters),
           !characters.isEmpty {
            return characters.uppercased()
        }

        return "Key \(event.keyCode)"
    }

    private static func specialKeyDisplayName(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 71: return "Clear"
        case 76: return "Enter"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "Home"
        case 116: return "Page Up"
        case 117: return "Forward Delete"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "Page Down"
        case 122: return "F1"
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        default: return nil
        }
    }
}

enum ShortcutMonitoringIssue: Equatable {
    case accessibilityPermissionMissing(displayName: String)
    case shortcutConflict(displayName: String, appName: String?)
    case shortcutConflictNeedsAccessibility(displayName: String, appName: String?)

    var title: String {
        switch self {
        case .accessibilityPermissionMissing:
            return String(localized: "アクセシビリティ権限が必要です")
        case .shortcutConflict, .shortcutConflictNeedsAccessibility:
            return String(localized: "ショートカットが競合しています")
        }
    }

    var message: String {
        switch self {
        case .accessibilityPermissionMissing(let displayName):
            return String(localized: "\(displayName) の録音開始は試行しますが、他のアプリへキー入力が渡る可能性があります。NiceVoice にアクセシビリティ権限を許可してください。")
        case .shortcutConflict(let displayName, let appName):
            if let appName {
                return String(localized: "\(displayName) は \(appName) でも使われています。NiceVoice はこのショートカットを優先して処理します。")
            }
            return String(localized: "\(displayName) は他のアプリでも使われている可能性があります。NiceVoice はこのショートカットを優先して処理します。")
        case .shortcutConflictNeedsAccessibility(let displayName, let appName):
            if let appName {
                return String(localized: "\(displayName) は \(appName) でも使われています。NiceVoice を優先するにはアクセシビリティ権限を許可してください。")
            }
            return String(localized: "\(displayName) は他のアプリでも使われている可能性があります。NiceVoice を優先するにはアクセシビリティ権限を許可してください。")
        }
    }
}

struct ShortcutConflictCandidate {
    let appName: String
    let keyCode: UInt16
    let carbonModifiers: UInt32
}

enum ShortcutConflictDetector {
    private struct StoredShortcut: Decodable {
        let carbonKeyCode: UInt16
        let carbonModifiers: UInt32
    }

    private static let appDomains: [(domain: String, appName: String)] = [
        ("com.openai.codex", "Codex"),
        ("com.openai.chat", "ChatGPT"),
        ("com.openai.atlas", "Atlas")
    ]

    static func knownConflict(
        for shortcut: CustomShortcut,
        runningBundleIdentifiers: Set<String> = currentRunningBundleIdentifiers()
    ) -> ShortcutConflictCandidate? {
        for appDomain in appDomains {
            guard let defaults = UserDefaults(suiteName: appDomain.domain) else { continue }
            for value in defaults.dictionaryRepresentation().values {
                guard let rawValue = value as? String,
                      let data = rawValue.data(using: .utf8),
                      let storedShortcut = try? JSONDecoder().decode(StoredShortcut.self, from: data),
                      storedShortcut.carbonKeyCode == shortcut.keyCode,
                      storedShortcut.carbonModifiers == shortcut.carbonModifierFlags else {
                    continue
                }

                return ShortcutConflictCandidate(
                    appName: appDomain.appName,
                    keyCode: storedShortcut.carbonKeyCode,
                    carbonModifiers: storedShortcut.carbonModifiers
                )
            }
        }

        return nil
    }

    private static func currentRunningBundleIdentifiers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

final class KeyMonitor {
    private enum LongPressRoutingState {
        case idle
        case passthrough
        case handling
    }

    private var monitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var customShortcutEventTap: CFMachPort?
    private var customShortcutEventTapSource: CFRunLoopSource?
    private var customShortcutHotKeyRef: EventHotKeyRef?
    private var customShortcutEventHandlerRef: EventHandlerRef?
    private var isKeyPressed = false
    private var isCustomShortcutPressed = false
    private var didConsumeCustomShortcutKeyPress = false
    private var pendingLongPressWorkItem: DispatchWorkItem?
    private var didTriggerLongPress = false
    private var longPressRoutingState: LongPressRoutingState = .idle
    private let onPressBegan: (() -> Void)?
    private let onPressCancelled: (() -> Void)?
    private let onMonitoringIssueChanged: (ShortcutMonitoringIssue?) -> Void
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void
    private var shortcutKey: ShortcutKey
    private var customShortcut: CustomShortcut

    private static let injectedEventMarker: Int64 = 0x4E565350

    init(
        shortcutKey: ShortcutKey = .fn,
        customShortcut: CustomShortcut = .defaultValue,
        onPressBegan: (() -> Void)? = nil,
        onPressCancelled: (() -> Void)? = nil,
        onMonitoringIssueChanged: @escaping (ShortcutMonitoringIssue?) -> Void = { _ in },
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) {
        self.shortcutKey = shortcutKey
        self.customShortcut = customShortcut
        self.onPressBegan = onPressBegan
        self.onPressCancelled = onPressCancelled
        self.onMonitoringIssueChanged = onMonitoringIssueChanged
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        startMonitoring()
    }

    func updateShortcut(shortcutKey newKey: ShortcutKey, customShortcut newCustomShortcut: CustomShortcut) {
        guard newKey != shortcutKey || newCustomShortcut != customShortcut else { return }
        shortcutKey = newKey
        customShortcut = newCustomShortcut
        stopMonitoring()
        startMonitoring()
        debugLog("🔄 Shortcut changed to: \(resolvedDisplayName)")
    }

    private var resolvedDisplayName: String {
        shortcutKey == .custom ? customShortcut.displayName : shortcutKey.displayName
    }

    private func stopMonitoring() {
        pendingLongPressWorkItem?.cancel()
        pendingLongPressWorkItem = nil
        isKeyPressed = false
        isCustomShortcutPressed = false
        didConsumeCustomShortcutKeyPress = false
        didTriggerLongPress = false
        longPressRoutingState = .idle

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            self.eventTapSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let customShortcutEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), customShortcutEventTapSource, .commonModes)
            self.customShortcutEventTapSource = nil
        }

        if let customShortcutEventTap {
            CFMachPortInvalidate(customShortcutEventTap)
            self.customShortcutEventTap = nil
        }

        releaseCustomShortcutReservation()
    }

    private func startMonitoring() {
        debugLog("🔍 [DEBUG] KeyMonitor startMonitoring called for: \(resolvedDisplayName)")

        if shortcutKey.usesLongPressBehavior {
            startLongPressMonitoring()
            return
        }

        if shortcutKey.usesCustomKeyCombinationBehavior {
            startCustomShortcutMonitoring()
            return
        }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let keyPressed = self.isShortcutKeyPressed(event: event)

            if keyPressed && !self.isKeyPressed {
                debugLog("🔍 [DEBUG] \(self.resolvedDisplayName) key DOWN detected")
                self.isKeyPressed = true
                DispatchQueue.main.async {
                    self.onKeyDown()
                }
            } else if !keyPressed && self.isKeyPressed {
                debugLog("🔍 [DEBUG] \(self.resolvedDisplayName) key UP detected")
                self.isKeyPressed = false
                DispatchQueue.main.async {
                    self.onKeyUp()
                }
            }
        }

        if monitor == nil {
            debugLog("⚠️ Accessibility permission is required - monitor is nil")
        } else {
            debugLog("✅ KeyMonitor started successfully for: \(resolvedDisplayName)")
        }
    }

    private func startCustomShortcutMonitoring() {
        var monitoringIssue: ShortcutMonitoringIssue?

        if let conflict = ShortcutConflictDetector.knownConflict(for: customShortcut) {
            debugLog("⚠️ Known shortcut conflict detected for: \(customShortcut.displayName), app=\(conflict.appName)")
            monitoringIssue = .shortcutConflict(displayName: customShortcut.displayName, appName: conflict.appName)
        }

        if !reserveCustomShortcut(), monitoringIssue == nil {
            monitoringIssue = .shortcutConflict(displayName: customShortcut.displayName, appName: nil)
        }

        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleCustomShortcutEvent(type: type, event: event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            debugLog("⚠️ Accessibility permission is required for custom shortcut monitoring")
            if case .shortcutConflict(_, let appName) = monitoringIssue {
                notifyMonitoringIssue(.shortcutConflictNeedsAccessibility(displayName: customShortcut.displayName, appName: appName))
            } else {
                notifyMonitoringIssue(.accessibilityPermissionMissing(displayName: customShortcut.displayName))
            }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        customShortcutEventTap = eventTap
        customShortcutEventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        notifyMonitoringIssue(monitoringIssue)
        debugLog("✅ Custom shortcut monitor started successfully for: \(resolvedDisplayName)")
    }

    private func reserveCustomShortcut() -> Bool {
        releaseCustomShortcutReservation()

        guard installCustomShortcutHotKeyHandler() else {
            return false
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E56534B), id: UInt32(customShortcut.rawValue.hashValue & 0x7fffffff))
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(customShortcut.keyCode),
            customShortcut.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            removeCustomShortcutHotKeyHandler()
            debugLog("⚠️ Custom shortcut conflict detected for: \(customShortcut.displayName), status=\(status)")
            return false
        }

        customShortcutHotKeyRef = hotKeyRef
        return true
    }

    private func installCustomShortcutHotKeyHandler() -> Bool {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userInfo in
                guard let userInfo else { return noErr }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleCustomShortcutHotKeyEvent(event)
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        guard status == noErr, let handlerRef else {
            debugLog("⚠️ Failed to install custom shortcut hotkey handler, status=\(status)")
            return false
        }

        customShortcutEventHandlerRef = handlerRef
        return true
    }

    private func handleCustomShortcutHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard shortcutKey.usesCustomKeyCombinationBehavior, let event else { return noErr }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            guard !isCustomShortcutPressed else { return noErr }
            isCustomShortcutPressed = true
            didConsumeCustomShortcutKeyPress = true
            DispatchQueue.main.async {
                self.onKeyDown()
            }
        case UInt32(kEventHotKeyReleased):
            guard isCustomShortcutPressed || didConsumeCustomShortcutKeyPress else { return noErr }
            isCustomShortcutPressed = false
            didConsumeCustomShortcutKeyPress = false
            DispatchQueue.main.async {
                self.onKeyUp()
            }
        default:
            break
        }

        return noErr
    }

    private func releaseCustomShortcutReservation() {
        if let customShortcutHotKeyRef {
            UnregisterEventHotKey(customShortcutHotKeyRef)
            self.customShortcutHotKeyRef = nil
        }
        removeCustomShortcutHotKeyHandler()
    }

    private func removeCustomShortcutHotKeyHandler() {
        if let customShortcutEventHandlerRef {
            RemoveEventHandler(customShortcutEventHandlerRef)
            self.customShortcutEventHandlerRef = nil
        }
    }

    private func notifyMonitoringIssue(_ issue: ShortcutMonitoringIssue?) {
        DispatchQueue.main.async {
            self.onMonitoringIssueChanged(issue)
        }
    }

    private func startLongPressMonitoring() {
        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleLongPressEvent(type: type, event: event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            debugLog("⚠️ Accessibility permission is required for long-press monitoring")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        debugLog("✅ Long-press monitor started successfully for: \(resolvedDisplayName)")
    }

    private func handleLongPressEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.injectedEventMarker {
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(shortcutKey.keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        if shouldBypassLongPressHandling(flags: flags) {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            return routeLongPressKeyDown(event: event)
        case .keyUp:
            return routeLongPressKeyUp(event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleCustomShortcutEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard shortcutKey.usesCustomKeyCombinationBehavior else {
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let customShortcutEventTap {
                CGEvent.tapEnable(tap: customShortcutEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.injectedEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierFlags = CustomShortcut.normalizedModifierFlags(
            NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        )

        switch type {
        case .keyDown:
            guard customShortcut.matches(keyCode: keyCode, modifierFlags: modifierFlags) else {
                return Unmanaged.passUnretained(event)
            }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard !isRepeat else { return nil }
            guard !isCustomShortcutPressed else { return nil }
            isCustomShortcutPressed = true
            didConsumeCustomShortcutKeyPress = true
            DispatchQueue.main.async {
                self.onKeyDown()
            }
            return nil
        case .keyUp:
            guard keyCode == customShortcut.keyCode else {
                return Unmanaged.passUnretained(event)
            }
            guard didConsumeCustomShortcutKeyPress else {
                return Unmanaged.passUnretained(event)
            }
            if isCustomShortcutPressed {
                isCustomShortcutPressed = false
                DispatchQueue.main.async {
                    self.onKeyUp()
                }
            }
            didConsumeCustomShortcutKeyPress = false
            return nil
        case .flagsChanged:
            guard customShortcut.usesModifierKeyCode(keyCode) else {
                return Unmanaged.passUnretained(event)
            }
            guard isCustomShortcutPressed else {
                return Unmanaged.passUnretained(event)
            }
            guard customShortcut.hasRequiredModifiers(modifierFlags) == false else {
                return Unmanaged.passUnretained(event)
            }
            isCustomShortcutPressed = false
            didConsumeCustomShortcutKeyPress = false
            DispatchQueue.main.async {
                self.onKeyUp()
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func routeLongPressKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        switch longPressRoutingState {
        case .passthrough:
            return Unmanaged.passUnretained(event)
        case .handling:
            return handleLongPressKeyDown(event: event)
        case .idle:
            guard FocusedElementInspector.focusedElementAllowsLongPressShortcut() else {
                longPressRoutingState = .passthrough
                return Unmanaged.passUnretained(event)
            }
            return handleLongPressKeyDown(event: event)
        }
    }

    private func routeLongPressKeyUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        switch longPressRoutingState {
        case .passthrough:
            longPressRoutingState = .idle
            return Unmanaged.passUnretained(event)
        case .handling:
            return handleLongPressKeyUp(event: event)
        case .idle:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleLongPressKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat {
            guard isKeyPressed, !didTriggerLongPress else { return nil }
            pendingLongPressWorkItem?.cancel()
            pendingLongPressWorkItem = nil
            didTriggerLongPress = true
            DispatchQueue.main.async {
                self.onKeyDown()
            }
            return nil
        }

        if isKeyPressed {
            return nil
        }

        longPressRoutingState = .handling
        isKeyPressed = true
        didTriggerLongPress = false

        DispatchQueue.main.async {
            self.onPressBegan?()
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isKeyPressed, self.shortcutKey.usesLongPressBehavior else { return }
            self.didTriggerLongPress = true
            DispatchQueue.main.async {
                self.onKeyDown()
            }
        }

        pendingLongPressWorkItem?.cancel()
        pendingLongPressWorkItem = workItem
        let delay = shortcutKey.longPressDelay ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return nil
    }

    private func handleLongPressKeyUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isKeyPressed else {
            longPressRoutingState = .idle
            return Unmanaged.passUnretained(event)
        }

        isKeyPressed = false
        pendingLongPressWorkItem?.cancel()
        pendingLongPressWorkItem = nil
        longPressRoutingState = .idle

        if didTriggerLongPress {
            didTriggerLongPress = false
            DispatchQueue.main.async {
                self.onKeyUp()
            }
        } else {
            DispatchQueue.main.async {
                self.onPressCancelled?()
            }
            restoreShortPressSpace()
        }

        return nil
    }

    private func shouldBypassLongPressHandling(flags: NSEvent.ModifierFlags) -> Bool {
        let blockedFlags: NSEvent.ModifierFlags = [.command, .control, .option, .shift, .function]
        return !flags.intersection(blockedFlags).isEmpty
    }

    static func currentInputSourceUsesJapanese() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        guard let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return false
        }
        let array = unsafeBitCast(languages, to: NSArray.self)
        let codes = array.compactMap { $0 as? String }
        return inputSourceLanguagesUseJapanese(codes)
    }

    static func inputSourceLanguagesUseJapanese(_ languages: [String]) -> Bool {
        languages.contains { language in
            language == "ja" || language.hasPrefix("ja-")
        }
    }

    private func restoreShortPressSpace() {
        if Self.currentInputSourceUsesJapanese() {
            injectSpaceKeyPress()
            return
        }
        if insertTextViaAccessibility(" ") {
            return
        }
        if insertTextViaUnicode(" ") {
            return
        }
        injectSpaceKeyPress()
    }

    private func insertTextViaAccessibility(_ text: String) -> Bool {
        guard let context = FocusedElementInspector.focusedTextInputContext() else { return false }
        return AXUIElementSetAttributeValue(context.element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    private func insertTextViaUnicode(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else { return false }
        var utf16 = Array(text.utf16)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return false
        }

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        keyDown.setIntegerValueField(.eventSourceUserData, value: Self.injectedEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: Self.injectedEventMarker)
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }

    private func injectSpaceKeyPress() {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcutKey.keyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcutKey.keyCode), keyDown: false) else {
            return
        }

        keyDown.setIntegerValueField(.eventSourceUserData, value: Self.injectedEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: Self.injectedEventMarker)
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
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
