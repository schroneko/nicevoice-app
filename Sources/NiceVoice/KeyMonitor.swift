import AppKit
import ApplicationServices
import Carbon

enum ShortcutKey: String, CaseIterable {
    case space = "space"
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
        case .space: return "Space"
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
        case .space: return 49
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
        case .space: return []
        case .fn: return .function
        case .leftShift, .rightShift: return .shift
        case .leftControl, .rightControl: return .control
        case .leftOption, .rightOption: return .option
        case .leftCommand, .rightCommand: return .command
        }
    }

    var deviceDependentFlag: UInt {
        switch self {
        case .space: return 0
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

    var usesLongPressBehavior: Bool {
        self == .space
    }

    var longPressDelay: TimeInterval? {
        switch self {
        case .space:
            return 0.45
        default:
            return nil
        }
    }

    var usageDescription: String {
        switch self {
        case .space:
            return String(localized: "Space を長押しして録音")
        default:
            return String(localized: "\(displayName) キーを押して録音")
        }
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
    private var isKeyPressed = false
    private var pendingLongPressWorkItem: DispatchWorkItem?
    private var didTriggerLongPress = false
    private var longPressRoutingState: LongPressRoutingState = .idle
    private let onPressBegan: (() -> Void)?
    private let onPressCancelled: (() -> Void)?
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void
    private var shortcutKey: ShortcutKey

    private static let injectedEventMarker: Int64 = 0x4E565350

    init(
        shortcutKey: ShortcutKey = .fn,
        onPressBegan: (() -> Void)? = nil,
        onPressCancelled: (() -> Void)? = nil,
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) {
        self.shortcutKey = shortcutKey
        self.onPressBegan = onPressBegan
        self.onPressCancelled = onPressCancelled
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        startMonitoring()
    }

    func updateShortcutKey(_ newKey: ShortcutKey) {
        guard newKey != shortcutKey else { return }
        shortcutKey = newKey
        stopMonitoring()
        startMonitoring()
        debugLog("🔄 Shortcut key changed to: \(newKey.displayName)")
    }

    private func stopMonitoring() {
        pendingLongPressWorkItem?.cancel()
        pendingLongPressWorkItem = nil
        isKeyPressed = false
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
    }

    private func startMonitoring() {
        debugLog("🔍 [DEBUG] KeyMonitor startMonitoring called for: \(shortcutKey.displayName)")

        if shortcutKey.usesLongPressBehavior {
            startLongPressMonitoring()
            return
        }

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
        debugLog("✅ Long-press monitor started successfully for: \(shortcutKey.displayName)")
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
