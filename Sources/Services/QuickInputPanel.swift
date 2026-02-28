import AppKit
import SwiftUI

// MARK: - State bridge

@Observable
final class QuickInputState {
    var isExpanded = false
    var conversation: ConversationState?
    var floatingPaneState: PaneState?
}

// MARK: - Panel controller

/// Global quick-input floating panel, summoned via Option+Space.
/// Compact mode: reuses ComposerView (same as welcome page).
/// Expanded mode: floating conversation pane with ConversationView.
final class QuickInputPanel: NSObject {
    private var panel: NSPanel?
    private weak var paneState: PaneState?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    private let state = QuickInputState()
    private let settings: AppSettings = {
        let s = AppSettings()
        s.widthMode = .compact
        return s
    }()

    // Position memory keys
    private static let savedMidXKey = "QuickInputPanel.midX"
    private static let savedBottomYKey = "QuickInputPanel.bottomY"

    func setup(paneState: PaneState) {
        self.paneState = paneState
        setupPanel()
        registerHotkey()
    }

    // MARK: - Panel setup

    private func setupPanel() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: true
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 360, height: 100)
        panel.maxSize = NSSize(width: 800, height: 900)

        let rootView = QuickInputRootView(
            state: state,
            settings: settings,
            onExpand: { [weak self] in self?.expandToPane() },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        panel.contentView = hosting

        self.panel = panel
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleHotkey(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleHotkey(event) == true { return nil }
            return event
        }
    }

    @discardableResult
    private func handleHotkey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
        else { return false }
        DispatchQueue.main.async { [weak self] in self?.toggle() }
        return true
    }

    // MARK: - Show / Dismiss / Toggle

    func toggle() {
        if panel?.isVisible == true {
            dismiss()
        } else {
            show()
        }
    }

    private func show() {
        guard let panel, let paneState else { return }

        // Always start fresh — new conversation each time
        state.conversation?.stop()

        let conv = ConversationState()
        conv.providerState = paneState.providerState
        conv.activeProviderID = paneState.providerState.activeProviderID
        if let focused = paneState.activeConversation {
            conv.workingDirectory = focused.workingDirectory
        }

        let ps = PaneState(providerState: paneState.providerState)
        ps.focusedConversation = conv

        state.conversation = conv
        state.floatingPaneState = ps
        state.isExpanded = false

        panel.styleMask.remove(.resizable)
        panel.setFrame(compactFrame(), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate()

        installClickOutsideMonitors()
    }

    func dismiss() {
        savePosition()
        removeClickOutsideMonitors()

        panel?.orderOut(nil)

        // Always reset — new session next time
        state.conversation?.stop()
        state.conversation = nil
        state.floatingPaneState = nil
        state.isExpanded = false

        // Restore focus to main window
        if let mainWindow = NSApp.windows.first(where: { $0 !== panel && $0.canBecomeKey }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Expand to floating pane

    private func expandToPane() {
        state.isExpanded = true

        guard let panel else { return }
        panel.styleMask.insert(.resizable)
        let target = expandedFrame()
        panel.setFrame(target, display: true, animate: true)
    }

    // MARK: - Position memory

    private func savePosition() {
        guard let panel else { return }
        UserDefaults.standard.set(Double(panel.frame.midX), forKey: Self.savedMidXKey)
        UserDefaults.standard.set(Double(panel.frame.origin.y), forKey: Self.savedBottomYKey)
    }

    // MARK: - Frame calculations

    private func compactFrame() -> NSRect {
        let w: CGFloat = 600
        let h: CGFloat = 100

        // Restore saved position if available
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.savedMidXKey) != nil {
            let midX = CGFloat(defaults.double(forKey: Self.savedMidXKey))
            let bottomY = CGFloat(defaults.double(forKey: Self.savedBottomYKey))
            return NSRect(x: midX - w / 2, y: bottomY, width: w, height: h)
        }

        // Default: horizontally centered, lower portion of screen
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame
        let x = vis.midX - w / 2
        let y = vis.origin.y + vis.height * 0.3
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func expandedFrame() -> NSRect {
        let w: CGFloat = 500
        let h: CGFloat = 620

        // Expand upward from current panel: keep bottom edge, center horizontally
        if let panel, panel.frame.width > 0 {
            let x = panel.frame.midX - w / 2
            let y = panel.frame.origin.y
            return NSRect(x: x, y: y, width: w, height: h)
        }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame
        return NSRect(x: vis.midX - w / 2, y: vis.origin.y + vis.height * 0.3, width: w, height: h)
    }

    // MARK: - Click outside monitors

    private func installClickOutsideMonitors() {
        // Clicks in other apps → dismiss
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.dismiss() }
        }
        // Clicks within Pane but not on the panel → dismiss
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            if event.window !== panel {
                DispatchQueue.main.async { self.dismiss() }
            }
            return event
        }
    }

    private func removeClickOutsideMonitors() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localClickMonitor { NSEvent.removeMonitor(m); localClickMonitor = nil }
    }
}

// MARK: - Root view (mode switch)

private struct QuickInputRootView: View {
    @Bindable var state: QuickInputState
    let settings: AppSettings
    var onExpand: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        Group {
            if let conversation = state.conversation {
                if state.isExpanded, let ps = state.floatingPaneState {
                    FloatingPaneView(conversation: conversation, onDismiss: onDismiss)
                        .environment(ps)
                        .environment(settings)
                } else {
                    // Compact: reuse ComposerView (same as welcome page)
                    ComposerView(conversation: conversation, isWelcome: true, isFocused: true)
                        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                        .padding(16)
                        .background(EscapeKeyHandler(onEscape: onDismiss))
                        .onChange(of: conversation.messages.count) {
                            if !conversation.messages.isEmpty {
                                onExpand()
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Floating pane (expanded mode)

private struct FloatingPaneView: View {
    @Bindable var conversation: ConversationState
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Thin session name bar (traffic lights handle close)
            Text(conversation.title.isEmpty ? "New Chat" : conversation.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .padding(.leading, 68) // clear traffic light zone

            Divider()

            ConversationView(conversation: conversation)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .background(EscapeKeyHandler(onEscape: onDismiss))
    }
}

// MARK: - Escape key handler

private struct EscapeKeyHandler: NSViewRepresentable {
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlerView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyHandlerView {
            view.onEscape = onEscape
        }
    }

    private class KeyHandlerView: NSView {
        var onEscape: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Esc
                onEscape?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
