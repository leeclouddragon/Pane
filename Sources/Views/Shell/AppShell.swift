import SwiftUI

/// Root view. System title bar + tab bar + pane tree.
struct AppShell: View {
    @Environment(PaneState.self) private var paneState
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            PaneTabBar()
            Divider()
            GeometryReader { geo in
                let zoom = settings.zoomLevel
                PaneContainer(node: paneState.root)
                    .frame(width: geo.size.width / zoom, height: geo.size.height / zoom)
                    .scaleEffect(zoom, anchor: .topLeading)
            }
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

/// Tab bar below the system title bar: one tab per pane + "+" button on the right.
struct PaneTabBar: View {
    @Environment(PaneState.self) private var paneState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(paneState.allConversations.enumerated()), id: \.element.id) { _, conv in
                tabItem(conv)
            }

            Spacer()

            // "+" button (right-aligned, like Terminal)
            Button(action: { paneState.newThread() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Thread")
        }
        .frame(height: 28)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }

    private func tabItem(_ conv: ConversationState) -> some View {
        let isActive = conv === paneState.focusedConversation

        return Button(action: { paneState.focusedConversation = conv }) {
            HStack(spacing: 4) {
                Text("—")
                    .foregroundStyle(.quaternary)
                Text(tabTitle(conv))
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                isActive
                    ? RoundedRectangle(cornerRadius: 5)
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
