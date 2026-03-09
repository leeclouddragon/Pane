import AppKit
import Carbon
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
/// Compact mode: reuses ComposerView (same as welcome page), borderless.
/// Expanded mode: floating conversation pane with system title bar (matches main window).
/// Session persists across dismiss/re-show. Promote button moves conversation to main window.
final class QuickInputPanel: NSObject {
    private var panel: NSPanel?
    private weak var paneState: PaneState?
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var promoteAccessory: NSTitlebarAccessoryViewController?

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
        panel.titlebarSeparatorStyle = .none
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
            onDismiss: { [weak self] in self?.dismiss() },
            onTitleChange: { [weak self] title in self?.panel?.title = title }
        )
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        panel.contentView = hosting

        self.panel = panel
    }

    // MARK: - Hotkey (Carbon RegisterEventHotKey)

    private static let hotkeyID = EventHotKeyID(signature: OSType(0x50414E45), // "PANE"
                                                  id: 1)

    private func registerHotkey() {
        // Carbon global hotkey: Option+Space — works from any app, no Accessibility needed
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let me = Unmanaged<QuickInputPanel>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { me.toggle() }
                return noErr
            },
            1, &eventType, selfPtr, &eventHandlerRef
        )

        let hotkeyID = Self.hotkeyID
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        // Local monitor: Option+Space toggle + Esc/Cmd+W dismiss
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Option+Space toggle (local events aren't caught by Carbon handler)
            if event.keyCode == 49,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option {
                DispatchQueue.main.async { self.toggle() }
                return nil
            }
            guard self.panel?.isVisible == true else { return event }
            // Esc dismisses the panel
            if event.keyCode == 53 {
                DispatchQueue.main.async { self.dismiss() }
                return nil
            }
            // Cmd+W dismisses the panel
            if event.keyCode == 13,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
                DispatchQueue.main.async { self.dismiss() }
                return nil
            }
            return event
        }
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

        if state.isExpanded, state.conversation != nil {
            // Re-show existing expanded conversation
            applyExpandedStyle(panel)
            panel.title = state.conversation?.displayTitle ?? "Pane"
        } else {
            // Fresh compact session
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

            applyCompactStyle(panel)
            panel.setFrame(compactFrame(), display: true)
        }

        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate()

        installClickOutsideMonitors()
    }

    func dismiss() {
        savePosition()
        removeClickOutsideMonitors()

        panel?.orderOut(nil)

        // Compact (no conversation started): clean up
        if !state.isExpanded {
            state.conversation?.stop()
            state.conversation = nil
            state.floatingPaneState = nil
        }

        // Restore focus to main window
        if let mainWindow = NSApp.windows.first(where: { $0 !== panel && $0.canBecomeKey }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Expand to floating pane

    private func expandToPane() {
        state.isExpanded = true

        guard let panel else { return }

        // Switch to native system title bar (matches main Pane window)
        applyExpandedStyle(panel)
        panel.title = state.conversation?.displayTitle ?? "Pane"

        let target = expandedFrame()
        panel.setFrame(target, display: true, animate: true)
    }

    // MARK: - Promote to main window

    @objc private func promoteToMainWindow() {
        guard let conversation = state.conversation, let paneState else { return }

        // Move conversation into the main pane tree
        paneState.adoptConversation(conversation)

        // Clear quick panel state completely
        state.conversation = nil
        state.floatingPaneState = nil
        state.isExpanded = false

        // Hide panel, restore compact style for next use
        savePosition()
        removeClickOutsideMonitors()
        panel?.orderOut(nil)
        if let panel { applyCompactStyle(panel) }

        // Focus main window
        if let mainWindow = NSApp.windows.first(where: { $0 !== panel && $0.canBecomeKey }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Panel style switching

    private func applyCompactStyle(_ panel: NSPanel) {
        panel.styleMask.insert(.fullSizeContentView)
        panel.styleMask.remove(.resizable)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.titlebarSeparatorStyle = .none
        panel.backgroundColor = .clear
        removePromoteButton()
    }

    private func applyExpandedStyle(_ panel: NSPanel) {
        panel.styleMask.remove(.fullSizeContentView)
        panel.styleMask.insert(.resizable)
        panel.titlebarAppearsTransparent = false
        panel.titleVisibility = .visible
        panel.titlebarSeparatorStyle = .none
        panel.backgroundColor = .windowBackgroundColor
        addPromoteButton()
    }

    // MARK: - Titlebar promote button

    private func addPromoteButton() {
        guard let panel, promoteAccessory == nil else { return }
        let vc = NSTitlebarAccessoryViewController()
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 22))
        btn.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                            accessibilityDescription: "Move to main window")
        btn.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        btn.imageScaling = .scaleProportionallyDown
        btn.isBordered = false
        btn.target = self
        btn.action = #selector(promoteToMainWindow)
        vc.view = btn
        vc.layoutAttribute = .trailing
        panel.addTitlebarAccessoryViewController(vc)
        promoteAccessory = vc
    }

    private func removePromoteButton() {
        guard let panel, let vc = promoteAccessory,
              let idx = panel.titlebarAccessoryViewControllers.firstIndex(of: vc)
        else { return }
        panel.removeTitlebarAccessoryViewController(at: idx)
        promoteAccessory = nil
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
    var onTitleChange: (String) -> Void

    var body: some View {
        Group {
            if let conversation = state.conversation {
                if state.isExpanded, let ps = state.floatingPaneState {
                    FloatingPaneView(
                        conversation: conversation,
                        onTitleChange: onTitleChange
                    )
                    .environment(ps)
                    .environment(settings)
                } else {
                    // Compact: reuse ComposerView (same as welcome page)
                    ComposerView(conversation: conversation, isWelcome: true, isFocused: true)
                        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                        .padding(16)
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
    var onTitleChange: (String) -> Void

    var body: some View {
        ConversationView(conversation: conversation)
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: conversation.displayTitle) {
                onTitleChange(panelTitle)
            }
            .onAppear {
                onTitleChange(panelTitle)
            }
    }

    private var panelTitle: String {
        let t = conversation.displayTitle
        return t.isEmpty ? "Pane" : t
    }
}
