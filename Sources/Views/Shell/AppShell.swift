import SwiftUI

/// Root view. System title bar + tab bar + pane tree.
struct AppShell: View {
    @Environment(PaneState.self) private var paneState
    @Environment(AppSettings.self) private var settings

    var body: some View {
        GeometryReader { geo in
            let zoom = settings.zoomLevel
            PaneContainer(node: paneState.root)
                .frame(width: geo.size.width / zoom, height: geo.size.height / zoom)
                .scaleEffect(zoom, anchor: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(windowTitle)
        .background(paneShortcuts)
    }

    private var windowTitle: String {
        let title = paneState.activeConversation?.displayTitle ?? ""
        return title.isEmpty ? "Pane" : title
    }

    /// Hidden buttons that register keyboard shortcuts.
    private var paneShortcuts: some View {
        Group {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { paneState.splitFocusedHorizontal() }
            }) { EmptyView() }
                .keyboardShortcut("d", modifiers: .command)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { paneState.splitFocusedVertical() }
            }) { EmptyView() }
                .keyboardShortcut("d", modifiers: [.command, .shift])

            Button(action: closeFocusedPaneOrWindow) { EmptyView() }
                .keyboardShortcut("w", modifiers: .command)

            Button(action: { focusPane(at: 0) }) { EmptyView() }
                .keyboardShortcut("1", modifiers: .command)
            Button(action: { focusPane(at: 1) }) { EmptyView() }
                .keyboardShortcut("2", modifiers: .command)
            Button(action: { focusPane(at: 2) }) { EmptyView() }
                .keyboardShortcut("3", modifiers: .command)
            Button(action: { focusPane(at: 3) }) { EmptyView() }
                .keyboardShortcut("4", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func closeFocusedPaneOrWindow() {
        if paneState.paneCount > 1 {
            withAnimation(.easeInOut(duration: 0.2)) { paneState.closeFocusedPane() }
        } else {
            NSApp.keyWindow?.close()
        }
    }

    private func focusPane(at index: Int) {
        let conversations = paneState.allConversations
        guard index < conversations.count else { return }
        paneState.focusedConversation = conversations[index]
    }
}

