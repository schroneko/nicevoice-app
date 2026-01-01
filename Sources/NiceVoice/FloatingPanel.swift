import AppKit
import SwiftUI

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FloatingPanel {
    private var window: NSPanel?
    private weak var appState: AppState?
    private var escMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        setupWindow()
        setupEscapeMonitor()
    }

    private func setupWindow() {
        guard let appState else { return }

        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 40),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.level = .screenSaver

        let hostingView = NSHostingView(rootView: FloatingPanelView(appState: appState))
        panel.contentView = hostingView

        self.window = panel
    }

    private func positionNearCursor() {
        guard let window, let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let panelWidth: CGFloat = 80
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.minY + 30

        debugLog("📍 Position: fixed center-bottom (\(x), \(y)), panelWidth: \(panelWidth)")
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func getCaretPosition() -> NSPoint? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            debugLog("📍 getCaretPosition: Failed to get focused element")
            return nil
        }

        let element = focusedElement as! AXUIElement

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success {
            debugLog("📍 getCaretPosition: Element role = \(roleValue as? String ?? "unknown")")
        }

        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success else {
            debugLog("📍 getCaretPosition: Failed to get selected range")
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRangeValue!, &boundsValue) == .success else {
            debugLog("📍 getCaretPosition: Failed to get bounds for range")
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds) else {
            debugLog("📍 getCaretPosition: Failed to get bounds value")
            return nil
        }

        debugLog("📍 getCaretPosition: Raw bounds = \(bounds)")

        if bounds.width == 0 && bounds.height == 0 {
            debugLog("📍 getCaretPosition: Bounds size is zero, returning nil")
            return nil
        }
        if bounds.origin.x == 0 && bounds.width == 0 {
            debugLog("📍 getCaretPosition: Bounds x=0 and width=0, likely invalid")
            return nil
        }

        guard let screen = NSScreen.main else { return nil }
        let flippedY = screen.frame.height - bounds.origin.y - bounds.height
        debugLog("📍 getCaretPosition: screen.height=\(screen.frame.height), flippedY=\(flippedY)")
        return NSPoint(x: bounds.origin.x, y: flippedY)
    }

    private func getFocusedElementPosition() -> NSPoint? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            debugLog("📍 getFocusedElement: Failed to get focused element")
            return nil
        }

        let element = focusedElement as! AXUIElement

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success {
            debugLog("📍 getFocusedElement: Element role = \(roleValue as? String ?? "unknown")")
        }

        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success else {
            debugLog("📍 getFocusedElement: Failed to get position")
            return nil
        }

        var position = CGPoint.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else {
            debugLog("📍 getFocusedElement: Failed to get position value")
            return nil
        }

        var sizeValue: CFTypeRef?
        var size = CGSize.zero
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }

        debugLog("📍 getFocusedElement: Raw position = \(position), size = \(size)")

        if size.height > 100 {
            debugLog("📍 getFocusedElement: Element too tall (\(size.height)), likely a window/container")
            return nil
        }

        guard let screen = NSScreen.main else { return nil }
        let flippedY = screen.frame.height - position.y - size.height
        debugLog("📍 getFocusedElement: screen.height=\(screen.frame.height), flippedY=\(flippedY)")
        return NSPoint(x: position.x, y: flippedY)
    }

    private func setupEscapeMonitor() {
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    self?.appState?.cancelRecording()
                }
            }
        }
    }

    func show() {
        positionNearCursor()
        window?.orderFrontRegardless()
        if let window {
            debugLog("🪟 Window level: \(window.level.rawValue), isVisible: \(window.isVisible)")
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    deinit {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
        }
    }
}
