import ApplicationServices

struct FocusedElementSnapshot: Equatable {
    let role: String?
    let editable: Bool?
    let enabled: Bool?
    let hasSelectedTextRange: Bool
    let size: CGSize?
}

struct FocusedTextInputContext {
    let element: AXUIElement
    let snapshot: FocusedElementSnapshot
    let selectedTextRange: AXValue?
}

private enum FocusedInputTarget {
    case direct(FocusedTextInputContext)
    case keyboardFallback
    case none
}

enum FocusedElementInspector {
    private static let singleLineTextInputRoles: Set<String> = [
        "AXTextField",
        "AXSearchField",
        "AXComboBox"
    ]
    private static let multiLineTextInputRoles: Set<String> = [
        "AXTextArea",
        "AXWebArea"
    ]
    private static let keyboardFallbackRoles: Set<String> = [
        "AXTextField",
        "AXSearchField",
        "AXComboBox",
        "AXTextArea",
        "AXWebArea"
    ]
    private static let editableAttribute = "AXEditable"

    static func acceptsTextInput(_ snapshot: FocusedElementSnapshot) -> Bool {
        guard snapshot.enabled != false else { return false }
        guard isVisible(snapshot) else { return false }
        guard let role = snapshot.role else { return false }
        if singleLineTextInputRoles.contains(role) {
            if snapshot.editable == false { return false }
            return snapshot.hasSelectedTextRange || snapshot.editable == true
        }
        if multiLineTextInputRoles.contains(role) {
            return snapshot.editable == true
        }
        return snapshot.editable == true && snapshot.hasSelectedTextRange
    }

    static func focusedElementAcceptsTextInput() -> Bool {
        focusedTextInputContext() != nil
    }

    static func focusedElementAllowsLongPressShortcut() -> Bool {
        switch focusedInputTarget() {
        case .direct, .keyboardFallback:
            return true
        case .none:
            return false
        }
    }

    static func focusedElementUsesKeyboardPreviewFallback() -> Bool {
        if case .keyboardFallback = focusedInputTarget() {
            return true
        }
        return false
    }

    static func focusedTextInputContext() -> FocusedTextInputContext? {
        if case let .direct(context) = focusedInputTarget() {
            return context
        }
        return nil
    }

    static func allowsLongPressShortcut(_ snapshot: FocusedElementSnapshot) -> Bool {
        acceptsTextInput(snapshot) || allowsKeyboardPreviewFallback(snapshot)
    }

    static func allowsKeyboardPreviewFallback(_ snapshot: FocusedElementSnapshot) -> Bool {
        guard snapshot.enabled != false else { return false }
        guard isVisible(snapshot) else { return false }
        guard let role = snapshot.role else { return false }
        return keyboardFallbackRoles.contains(role)
    }

    private static func focusedInputTarget() -> FocusedInputTarget {
        guard let focusedElement = focusedElement() else { return .none }

        var currentElement: AXUIElement? = focusedElement
        var depth = 0

        while let element = currentElement, depth <= Constants.UI.maxAXTreeSearchDepth {
            let snapshot = snapshot(for: element)
            if acceptsTextInput(snapshot) {
                return .direct(
                    FocusedTextInputContext(
                        element: element,
                        snapshot: snapshot,
                        selectedTextRange: selectedTextRange(for: element)
                    )
                )
            }
            if allowsKeyboardPreviewFallback(snapshot) {
                return .keyboardFallback
            }
            currentElement = parent(of: element)
            depth += 1
        }

        return .none
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let focusedElement else { return nil }
        return (focusedElement as! AXUIElement)
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var parent: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent)
        guard result == .success, let parent else { return nil }
        return (parent as! AXUIElement)
    }

    private static func snapshot(for element: AXUIElement) -> FocusedElementSnapshot {
        FocusedElementSnapshot(
            role: stringAttribute(kAXRoleAttribute, on: element),
            editable: boolAttribute(editableAttribute, on: element),
            enabled: boolAttribute(kAXEnabledAttribute, on: element),
            hasSelectedTextRange: selectedTextRange(for: element) != nil,
            size: sizeAttribute(on: element)
        )
    }

    private static func isVisible(_ snapshot: FocusedElementSnapshot) -> Bool {
        guard let size = snapshot.size else { return false }
        return size.width > 1 && size.height > 1
    }

    private static func stringAttribute(_ attribute: String, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ attribute: String, on element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? Bool
    }

    private static func selectedTextRange(for element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return (value as! AXValue)
    }

    private static func sizeAttribute(on element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value)
        guard result == .success, let value else { return nil }
        let axValue = (value as! AXValue)
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
