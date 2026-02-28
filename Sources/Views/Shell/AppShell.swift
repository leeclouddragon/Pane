import SwiftUI

/// Root view. Tab bar + pane tree (with composer + status bar inside each pane).
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                PaneTabBar()
            }
        }
        .background(paneShortcuts)
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

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { paneState.closeFocusedPane() }
            }) { EmptyView() }
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

    private func focusPane(at index: Int) {
        let conversations = paneState.allConversations
        guard index < conversations.count else { return }
        paneState.focusedConversation = conversations[index]
    }
}

// MARK: - Terminal-style tab bar

/// Tab bar shown in the toolbar: one tab per pane + a "+" button.
struct PaneTabBar: View {
    @Environment(PaneState.self) private var paneState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(paneState.allConversations.enumerated()), id: \.element.id) { _, conv in
                tabItem(conv)
            }

            // "+" button
            Button(action: { paneState.newThread() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Thread")
        }
    }

    private func tabItem(_ conv: ConversationState) -> some View {
        let isActive = conv === paneState.focusedConversation

        return Button(action: { paneState.focusedConversation = conv }) {
            Text(tabTitle(conv))
                .font(.system(size: 11))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    isActive
                        ? RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary.opacity(0.5))
                        : nil
                )
        }
        .buttonStyle(.plain)
    }

    private func tabTitle(_ conv: ConversationState) -> String {
        let title = conv.displayTitle
        if title.isEmpty || title == conv.title {
            return conv.title.isEmpty ? "New Thread" : conv.title
        }
        return title
    }
}
