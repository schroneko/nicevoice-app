import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

final class TextInsertionController {
    private var capturedTextElement: AXUIElement?
    private var insertionPointLocation: Int = 0
    private var inlinePreviewLength: Int = 0
    private var inlinePreviewActive: Bool = false
    private var inlinePreviewVerified = false
    private var useKeyboardPreview = false
    private var keyboardPreviewText = ""
    private var currentAXPreviewText = ""

    static func clipboardRestoreDelay() -> TimeInterval {
        Constants.Timing.pastePostDelaySeconds
    }

    static func shouldRestoreClipboard(
        previousContents: String?,
        currentContents: String?,
        pastedText: String
    ) -> Bool {
        guard previousContents != nil else { return false }
        return currentContents == pastedText
    }

    func captureFocusedTarget() -> (hasTextInputTarget: Bool, spotlightOpen: Bool) {
        capturedTextElement = nil
        inlinePreviewLength = 0
        inlinePreviewActive = false
        let spotlightOpen = isSpotlightOpen()

        guard let context = FocusedElementInspector.focusedTextInputContext() else {
            if FocusedElementInspector.focusedElementUsesKeyboardPreviewFallback() {
                switchToKeyboardPreview("")
                debugLog("🔍 [InlinePreview] Using keyboard preview fallback")
            } else {
                debugLog("🔍 [InlinePreview] Focused element does not accept text input")
            }
            return (hasTextInputTarget: useKeyboardPreview, spotlightOpen: spotlightOpen)
        }

        guard let rangeRef = context.selectedTextRange else {
            debugLog("🔍 [InlinePreview] Could not get selected text range")
            return (hasTextInputTarget: false, spotlightOpen: spotlightOpen)
        }

        var range = CFRange(location: 0, length: 0)
        AXValueGetValue(rangeRef, .cfRange, &range)

        capturedTextElement = context.element
        insertionPointLocation = range.location + range.length
        inlinePreviewActive = true
        debugLog("🔍 [InlinePreview] Captured text element (role: \(context.snapshot.role ?? "unknown"), cursor: \(insertionPointLocation))")
        return (hasTextInputTarget: true, spotlightOpen: spotlightOpen)
    }

    @discardableResult
    func updatePreview(_ text: String) -> Bool {
        if useKeyboardPreview {
            updateKeyboardPreview(text)
            return true
        }

        guard inlinePreviewActive, let element = capturedTextElement else { return false }

        let nsText = text as NSString
        let newLength = nsText.length
        let oldNSText = currentAXPreviewText as NSString
        let commonPrefixStr = currentAXPreviewText.commonPrefix(with: text)
        let commonPrefixLen = (commonPrefixStr as NSString).length

        if commonPrefixLen == oldNSText.length && newLength > oldNSText.length {
            let suffix = nsText.substring(from: commonPrefixLen)
            var cursorRange = CFRange(location: insertionPointLocation + inlinePreviewLength, length: 0)
            guard let cursorRangeValue = AXValueCreate(.cfRange, &cursorRange) else { return false }

            let setRangeResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, cursorRangeValue)
            guard setRangeResult == .success else {
                debugLog("🔍 [InlinePreview] AX append cursor failed, switching to keyboard mode")
                switchToKeyboardPreview(text)
                return true
            }

            let setTextResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, suffix as CFTypeRef)
            guard setTextResult == .success else {
                debugLog("🔍 [InlinePreview] AX append text failed, switching to keyboard mode")
                switchToKeyboardPreview(text)
                return true
            }

            inlinePreviewLength = newLength
            currentAXPreviewText = text
        } else if text != currentAXPreviewText {
            var range = CFRange(location: insertionPointLocation, length: inlinePreviewLength)
            guard let rangeValue = AXValueCreate(.cfRange, &range) else { return false }

            let setRangeResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
            guard setRangeResult == .success else {
                debugLog("🔍 [InlinePreview] AX set range failed, switching to keyboard mode")
                switchToKeyboardPreview(text)
                return true
            }

            let setTextResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            guard setTextResult == .success else {
                debugLog("🔍 [InlinePreview] AX set text failed, switching to keyboard mode")
                switchToKeyboardPreview(text)
                return true
            }

            inlinePreviewLength = newLength
            currentAXPreviewText = text
        }

        if !inlinePreviewVerified && newLength > 0 {
            var verifyRange = CFRange(location: insertionPointLocation, length: newLength)
            if let verifyRangeValue = AXValueCreate(.cfRange, &verifyRange) {
                var readText: CFTypeRef?
                let readResult = AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXStringForRangeParameterizedAttribute as CFString,
                    verifyRangeValue,
                    &readText
                )
                if readResult == .success, let readBack = readText as? String, readBack == text {
                    inlinePreviewVerified = true
                    debugLog("🔍 [InlinePreview] Verified: AX text insertion confirmed")
                } else {
                    debugLog("🔍 [InlinePreview] AX verification failed, switching to keyboard mode")
                    undoAXInsert(element: element, length: newLength)
                    switchToKeyboardPreview(text)
                    return true
                }
            }
        }

        return true
    }

    func finalizePreview(_ text: String) -> Bool {
        if useKeyboardPreview {
            if keyboardPreviewText != text {
                updateKeyboardPreview(text)
            }
            resetPreviewState()
            debugLog("✅ [InlinePreview] Finalized in place via keyboard preview")
            return true
        }

        if inlinePreviewActive, let element = capturedTextElement {
            if currentAXPreviewText != text {
                _ = updatePreview(text)
            }

            if useKeyboardPreview {
                if keyboardPreviewText != text {
                    updateKeyboardPreview(text)
                }
                resetPreviewState()
                debugLog("✅ [InlinePreview] Finalized in place after keyboard fallback")
                return true
            }

            if currentAXPreviewText == text {
                debugLog("✅ [InlinePreview] Finalized in place via AX: \(text.count) chars")
                resetPreviewState()
                return true
            }

            var range = CFRange(location: insertionPointLocation, length: inlinePreviewLength)
            if let rangeValue = AXValueCreate(.cfRange, &range) {
                let setRangeResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
                if setRangeResult == .success {
                    let setTextResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
                    if setTextResult == .success {
                        debugLog("✅ [InlinePreview] Finalized via AX (full replace): \(text.count) chars")
                        resetPreviewState()
                        return true
                    }
                }
            }
        }

        resetPreviewState()
        return false
    }

    func cancelPreview() {
        if useKeyboardPreview {
            updateKeyboardPreview("")
            debugLog("🚫 [InlinePreview] Keyboard preview cancelled")
            resetPreviewState()
            return
        }
        guard inlinePreviewActive, capturedTextElement != nil else {
            resetPreviewState()
            return
        }
        updatePreview("")
        debugLog("🚫 [InlinePreview] AX preview cancelled")
        resetPreviewState()
    }

    private func undoAXInsert(element: AXUIElement, length: Int) {
        var range = CFRange(location: insertionPointLocation, length: length)
        if let rangeValue = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
            AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, "" as CFTypeRef)
        }
        inlinePreviewLength = 0
        inlinePreviewActive = false
        capturedTextElement = nil
    }

    private func switchToKeyboardPreview(_ text: String) {
        inlinePreviewActive = false
        useKeyboardPreview = true
        keyboardPreviewText = ""
        updateKeyboardPreview(text)
        debugLog("🔍 [InlinePreview] Keyboard preview mode activated")
    }

    private func selectPreviewRange(length: Int) -> Bool {
        guard length > 0, let element = capturedTextElement else { return false }
        var range = CFRange(location: insertionPointLocation, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success
    }

    private func updateKeyboardPreview(_ text: String) {
        let oldText = keyboardPreviewText
        let commonPrefix = oldText.commonPrefix(with: text)
        let charsToDelete = oldText.count - commonPrefix.count
        let newSuffix = String(text.dropFirst(commonPrefix.count))
        let oldLength = (oldText as NSString).length

        let source = CGEventSource(stateID: .privateState)

        if charsToDelete > 0, selectPreviewRange(length: oldLength) {
            if text.isEmpty {
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: false) {
                    keyDown.post(tap: .cgAnnotatedSessionEventTap)
                    keyUp.post(tap: .cgAnnotatedSessionEventTap)
                }
            } else {
                typeUnicodeString(text, source: source)
            }
            keyboardPreviewText = text
            return
        }

        for _ in 0..<charsToDelete {
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: false) {
                keyDown.post(tap: .cgAnnotatedSessionEventTap)
                keyUp.post(tap: .cgAnnotatedSessionEventTap)
            }
        }

        if !newSuffix.isEmpty {
            typeUnicodeString(newSuffix, source: source)
        }

        keyboardPreviewText = text
    }

    private func typeUnicodeString(_ text: String, source: CGEventSource?) {
        let utf16 = Array(text.utf16)
        let chunkSize = 20

        var start = 0
        while start < utf16.count {
            var end = min(start + chunkSize, utf16.count)
            if end < utf16.count && UTF16.isLeadSurrogate(utf16[end - 1]) {
                end -= 1
            }
            if end <= start { break }
            var chunk = Array(utf16[start..<end])
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                keyDown.post(tap: .cgAnnotatedSessionEventTap)
            }
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                keyUp.post(tap: .cgAnnotatedSessionEventTap)
            }
            start = end
        }
    }

    private func resetPreviewState() {
        capturedTextElement = nil
        insertionPointLocation = 0
        inlinePreviewLength = 0
        inlinePreviewActive = false
        inlinePreviewVerified = false
        useKeyboardPreview = false
        keyboardPreviewText = ""
        currentAXPreviewText = ""
    }

    func paste(_ text: String) {
        let pasteboard = NSPasteboard.general

        let previousContents = pasteboard.string(forType: .string)
        debugLog("📋 Saving previous clipboard: \(previousContents?.count ?? 0) chars")

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        debugLog("📋 Set clipboard to: \(text.count) chars")

        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.pastePreDelaySeconds) { [weak self] in
            self?.simulatePaste {
                let restoreDelay = Self.clipboardRestoreDelay()
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                    let currentContents = pasteboard.string(forType: .string)
                    guard Self.shouldRestoreClipboard(
                        previousContents: previousContents,
                        currentContents: currentContents,
                        pastedText: text
                    ) else {
                        debugLog("📋 Skipped clipboard restore: current clipboard changed before restore window elapsed")
                        return
                    }

                    if let prev = previousContents {
                        pasteboard.clearContents()
                        pasteboard.setString(prev, forType: .string)
                        debugLog("📋 Restored previous clipboard: \(prev.count) chars")
                    }
                }
            }
        }
    }

    private func simulatePaste(completion: @escaping () -> Void) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            debugLog("❌ No text in clipboard")
            completion()
            return
        }

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            debugLog("📱 Frontmost app: \(frontApp.localizedName ?? "unknown") (bundle: \(frontApp.bundleIdentifier ?? "unknown"), PID: \(frontApp.processIdentifier))")
        } else {
            debugLog("📱 Frontmost app: nil")
        }

        if isSpotlightOpen() {
            debugLog("🔍 Spotlight detected - using AXUIElement API")
            setTextToSpotlight(text)
            completion()
            return
        }

        debugLog("🎯 Sending Cmd+V paste via CGEvent")

        let source = CGEventSource(stateID: .privateState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            debugLog("❌ Failed to create CGEvent")
            completion()
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        usleep(Constants.Timing.keyEventDelayMicroseconds)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        debugLog("✅ Paste command sent via CGEvent")
        completion()
    }

    private func isSpotlightOpen() -> Bool {
        guard let spotlightApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight").first else {
            return false
        }

        let axApp = AXUIElementCreateApplication(spotlightApp.processIdentifier)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows) == .success,
              let windowArray = windows as? [AXUIElement],
              !windowArray.isEmpty else {
            return false
        }

        debugLog("🔍 Spotlight windows found: \(windowArray.count)")
        return true
    }

    private func setTextToSpotlight(_ text: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight")
        guard let spotlightApp = apps.first else {
            debugLog("❌ Spotlight app not found")
            return
        }

        let axApp = AXUIElementCreateApplication(spotlightApp.processIdentifier)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows)

        guard let windowArray = windows as? [AXUIElement], let window = windowArray.first else {
            debugLog("❌ No Spotlight windows found")
            return
        }

        if let searchField = findSearchField(in: window) {
            let setResult = AXUIElementSetAttributeValue(searchField, kAXValueAttribute as CFString, text as CFTypeRef)
            if setResult == .success {
                debugLog("✅ Text set to Spotlight via AXUIElement")
            } else {
                debugLog("❌ AXUIElement failed (\(setResult.rawValue)), trying CGEvent postToPid")
                sendPasteToSpotlight(pid: spotlightApp.processIdentifier)
            }
        } else {
            debugLog("⚠️ No search field found, trying CGEvent postToPid")
            sendPasteToSpotlight(pid: spotlightApp.processIdentifier)
        }
    }

    private func findSearchField(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > Constants.UI.maxAXTreeSearchDepth { return nil }

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        if let roleStr = role as? String {
            debugLog("🔍 [AX] depth=\(depth) role=\(roleStr)")
            if roleStr == "AXTextField" || roleStr == "AXSearchField" || roleStr == "AXTextArea" {
                return element
            }
        }

        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

        if let childArray = children as? [AXUIElement] {
            for child in childArray {
                if let found = findSearchField(in: child, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    private func sendPasteToSpotlight(pid: pid_t) {
        let source = CGEventSource(stateID: .privateState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            debugLog("❌ Failed to create CGEvent for Spotlight")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.postToPid(pid)
        usleep(Constants.Timing.keyEventDelayMicroseconds)
        keyUp.postToPid(pid)

        debugLog("✅ Paste sent to Spotlight PID \(pid) via postToPid")
    }
}
