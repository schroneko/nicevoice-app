import AppKit
import SwiftUI

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FloatingPanel {
    private var window: NSPanel?
    private var hostingView: NSHostingView<FloatingPanelView>?
    private weak var appState: AppState?
    private var escMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        setupWindow()
        setupEscapeMonitor()
    }

    private func setupWindow() {
        guard let appState else { return }

        let hostingView = NSHostingView(rootView: FloatingPanelView(appState: appState))
        self.hostingView = hostingView
        let fittingSize = measuredPanelSize()

        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.contentView = hostingView

        self.window = panel
    }

    private func measuredPanelSize() -> NSSize {
        guard let hostingView, let appState else {
            return NSSize(width: Constants.UI.floatingPanelWidth, height: Constants.UI.floatingPanelHeight)
        }

        hostingView.rootView = FloatingPanelView(appState: appState)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let minWidth = appState.errorMessage == nil
            ? Constants.UI.floatingPanelWidth
            : Constants.UI.floatingPanelExpandedWidth
        let minHeight = appState.errorMessage == nil
            ? Constants.UI.floatingPanelHeight
            : Constants.UI.floatingPanelExpandedHeight

        return NSSize(
            width: min(max(fittingSize.width, minWidth), Constants.UI.floatingPanelMaxWidth),
            height: max(fittingSize.height, minHeight)
        )
    }

    private func positionNearCursor() {
        guard let window, let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let panelSize = measuredPanelSize()
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.minY + Constants.UI.floatingPanelBottomOffset

        window.setContentSize(panelSize)

        debugLog("📍 Position: fixed center-bottom (\(x), \(y)), panelWidth: \(panelSize.width)")
        window.setFrameOrigin(NSPoint(x: x, y: y))
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
