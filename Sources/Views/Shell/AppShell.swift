import SwiftUI

/// Root view. System toolbar + pane tree (with composer + status bar inside each pane).
struct AppShell: View {
    @Environment(PaneState.self) private var paneState
    @Environment(AppSettings.self) private var settings
    @State private var showHistory = false

    var body: some View {
        GeometryReader { geo in
            let zoom = settings.zoomLevel
            PaneContainer(node: paneState.root)
                .frame(width: geo.size.width / zoom, height: geo.size.height / zoom)
                .scaleEffect(zoom, anchor: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: { showHistory.toggle() }) {
                        ClockIconView(size: 14)
                            .foregroundStyle(.secondary)
                    }
                    .help("Recent Sessions")

                    Button(action: { paneState.newThread() }) {
                        ComposeIconView(size: 14)
                            .foregroundStyle(.secondary)
                    }
                    .help("New Thread")
                }

                ToolbarItem(placement: .principal) {
                    if let conv = paneState.activeConversation {
                        Text(conv.displayTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
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
