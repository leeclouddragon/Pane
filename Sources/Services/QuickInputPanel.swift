import AppKit
import SwiftUI

// MARK: - State bridge

@Observable
final class QuickInputState {
    enum Mode {
        case compact
        case expanded(ConversationState, PaneState)
    }
    var mode: Mode = .compact
    var compactText = ""

    var isExpanded: Bool {
        if case .expanded = mode { return true }
        return false
    }

    var conversation: ConversationState? {
        if case .expanded(let c, _) = mode { return c }
        return nil
    }
}

// MARK: - Panel controller

/// Global quick-input floating panel, summoned via Option+Space.
/// Compact mode: Spotlight-style input bar.
/// Expanded mode: floating conversation pane reusing ConversationView.
final class QuickInputPanel: NSObject {
    private var panel: NSPanel?
    private weak var paneState: PaneState?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private let state = QuickInputState()
    /// Dedicated PaneState for the floating pane (isolated from main window tree).
    private var floatingPaneState: PaneState?
    private let settings: AppSettings = {
        let s = AppSettings()
        s.widthMode = .compact
        return s
    }()

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
        panel.minSize = NSSize(width: 360, height: 56)
        panel.maxSize = NSSize(width: 800, height: 900)

        let rootView = QuickInputRootView(
            state: state,
            settings: settings,
            onCompactSubmit: { [weak self] text in self?.expandToPane(text: text) },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let hosting = NSHostingView(rootView: rootView)
        // Prevent SwiftUI content size changes from resizing the window
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
        guard let panel else { return }
        if !state.isExpanded {
            // Compact: disable resize, center on screen
            panel.styleMask.remove(.resizable)
            panel.setFrame(compactFrame(), display: true)
        } else {
            // Expanded: enable resize
            panel.styleMask.insert(.resizable)
            if panel.frame.height < 200 {
                panel.setFrame(expandedFrame(), display: true)
            }
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        // Restore focus to main window
        if let mainWindow = NSApp.windows.first(where: { $0 !== panel && $0.canBecomeKey }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Expand to floating pane

    private func expandToPane(text: String) {
        guard let paneState else { return }

        // Create conversation with same provider config as main window
        let conv = ConversationState()
        conv.providerState = paneState.providerState
        conv.activeProviderID = paneState.providerState.activeProviderID
        if let focused = paneState.activeConversation {
            conv.workingDirectory = focused.workingDirectory
        }

        // Dedicated PaneState so ConversationView.isFocusedPane works
        let ps = PaneState(providerState: paneState.providerState)
        ps.focusedConversation = conv
        self.floatingPaneState = ps

        // Send message first (so ConversationView enters conversationLayout)
        conv.send(text)

        // Switch mode — SwiftUI will reactively update the view
        state.compactText = ""
        state.mode = .expanded(conv, ps)

        // Resize panel to expanded size
        guard let panel else { return }
        panel.styleMask.insert(.resizable)
        let target = expandedFrame()
        panel.setFrame(target, display: true, animate: true)
    }

    // MARK: - Reset to compact

    private func reset() {
        // Stop any running process
        if let conv = state.conversation {
            conv.stop()
        }
        floatingPaneState = nil
        state.mode = .compact

        guard let panel else { return }
        panel.styleMask.remove(.resizable)
        let target = compactFrame()
        panel.setFrame(target, display: true, animate: true)
    }

    // MARK: - Frame calculations

    private func compactFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let w: CGFloat = 600
        let h: CGFloat = 56
        let x = screen.frame.midX - w / 2
        let y = screen.frame.maxY - screen.frame.height / 3
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func expandedFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let w: CGFloat = 500
        let h: CGFloat = 620
        // Position: keep horizontal center, drop down from compact position
        let x = screen.frame.midX - w / 2
        let y = screen.frame.maxY - screen.frame.height / 3 - h + 56
        return NSRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Root view (mode switch)

private struct QuickInputRootView: View {
    @Bindable var state: QuickInputState
    let settings: AppSettings
    var onCompactSubmit: (String) -> Void
    var onDismiss: () -> Void

    var body: some View {
        Group {
            switch state.mode {
            case .compact:
                QuickInputBar(
                    text: $state.compactText,
                    onSubmit: onCompactSubmit,
                    onDismiss: onDismiss
                )
            case .expanded(let conversation, let paneState):
                FloatingPaneView(conversation: conversation)
                    .environment(paneState)
                    .environment(settings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Floating pane (expanded mode)

private struct FloatingPaneView: View {
    @Bindable var conversation: ConversationState

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
    }
}

// MARK: - Compact input bar

private struct QuickInputBar: View {
    @Binding var text: String
    var onSubmit: (String) -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)

            QuickInputTextField(
                text: $text,
                onCommit: submitAction,
                onEscape: onDismiss
            )

            Button(action: submitAction) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.secondary.opacity(0.3)
                            : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .padding(8)
    }

    private func submitAction() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
    }
}

// MARK: - NSTextField wrapper (compact mode input)

private struct QuickInputTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 14)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Ask anything..."
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        // Only auto-focus when the panel is the key window (not just visible).
        // Prevents stealing focus from the main window on unrelated SwiftUI updates.
        DispatchQueue.main.async {
            guard let window = field.window,
                  window.isKeyWindow,
                  window.firstResponder !== field.currentEditor()
            else { return }
            window.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickInputTextField
        init(_ parent: QuickInputTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                      doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }
    }
}
