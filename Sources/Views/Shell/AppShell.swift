import SwiftUI

/// Root view. Title bar + pane tree (with composer + status bar inside each pane).
struct AppShell: View {
    @Environment(PaneState.self) private var paneState
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            TitleBarView()
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            PaneContainer(node: paneState.root)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(paneShortcuts)
    }

    /// Hidden buttons that register keyboard shortcuts.
    private var paneShortcuts: some View {
        Group {
            // Cmd+D: split horizontal
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { paneState.splitFocusedHorizontal() }
            }) { EmptyView() }
                .keyboardShortcut("d", modifiers: .command)

            // Cmd+Shift+D: split vertical
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { paneState.splitFocusedVertical() }
            }) { EmptyView() }
                .keyboardShortcut("d", modifiers: [.command, .shift])

            // Cmd+W: close pane
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { paneState.closeFocusedPane() }
            }) { EmptyView() }
                .keyboardShortcut("w", modifiers: .command)

            // Cmd+1/2/3/4: focus pane by index
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

    private func focusPane(at index: Int) {
        let conversations = paneState.allConversations
        guard index < conversations.count else { return }
        paneState.focusedConversation = conversations[index]
    }
}
