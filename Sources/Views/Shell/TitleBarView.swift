import SwiftUI

/// iTerm2-style title bar: traffic lights + session name + history/new buttons.
struct TitleBarView: View {
    @Environment(PaneState.self) private var paneState
    @State private var showHistory = false

    var body: some View {
        HStack(spacing: 0) {
            // Traffic light zone
            Color.clear.frame(width: 78, height: 1)

            // Left: recent + new thread
            HStack(spacing: 2) {
                Button(action: { showHistory.toggle() }) {
                    ClockIconView(size: 14)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Recent Sessions")

                Button(action: { paneState.newThread() }) {
                    ComposeIconView(size: 14)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Thread")
            }

            // Session name (focused pane)
            if let conv = paneState.activeConversation {
                Text(conv.displayTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 6)
            }

            Spacer()
        }
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

