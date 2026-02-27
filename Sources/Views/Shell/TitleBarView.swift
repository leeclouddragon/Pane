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
                    RecentIcon()
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Recent Sessions")

                Button(action: { paneState.newThread() }) {
                    ComposeIcon()
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Thread")
            }

            // Session name (focused pane)
            if let conv = paneState.activeConversation {
                Text(conv.displayTitle)
                    .font(.system(size: 12))
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

// MARK: - Custom Icons

/// Overlapping rounded rectangles — "recent sessions" icon.
private struct RecentIcon: View {
    var body: some View {
        Canvas { context, size in
            let lw: CGFloat = 1.0
            let r: CGFloat = 2.5
            let w = size.width
            let h = size.height

            // Back card (offset up-left)
            let backRect = CGRect(
                x: w * 0.18, y: h * 0.22,
                width: w * 0.48, height: w * 0.38
            )
            let backPath = Path(roundedRect: backRect, cornerRadius: r)
            context.stroke(backPath, with: .color(.secondary.opacity(0.5)), lineWidth: lw)

            // Front card (offset down-right)
            let frontRect = CGRect(
                x: w * 0.34, y: h * 0.38,
                width: w * 0.48, height: w * 0.38
            )
            let frontPath = Path(roundedRect: frontRect, cornerRadius: r)
            context.stroke(frontPath, with: .color(.secondary), lineWidth: lw)
        }
    }
}

/// Rounded rectangle with a pen stroke — "new thread / compose" icon.
private struct ComposeIcon: View {
    var body: some View {
        Canvas { context, size in
            let lw: CGFloat = 1.0
            let r: CGFloat = 2.5
            let w = size.width
            let h = size.height

            // Document body
            let docRect = CGRect(
                x: w * 0.22, y: h * 0.28,
                width: w * 0.46, height: w * 0.46
            )
            let docPath = Path(roundedRect: docRect, cornerRadius: r)
            context.stroke(docPath, with: .color(.secondary), lineWidth: lw)

            // Pen stroke (diagonal line from top-right going up-right)
            var penPath = Path()
            let penBase = CGPoint(x: w * 0.56, y: h * 0.42)
            let penTip = CGPoint(x: w * 0.78, y: h * 0.20)
            penPath.move(to: penBase)
            penPath.addLine(to: penTip)
            context.stroke(penPath, with: .color(.secondary), style: StrokeStyle(lineWidth: lw, lineCap: .round))

            // Small pen nib tick
            var nibPath = Path()
            nibPath.move(to: CGPoint(x: penTip.x - 2, y: penTip.y - 1))
            nibPath.addLine(to: penTip)
            nibPath.addLine(to: CGPoint(x: penTip.x + 1, y: penTip.y + 2))
            context.stroke(nibPath, with: .color(.secondary), style: StrokeStyle(lineWidth: lw * 0.8, lineCap: .round))
        }
    }
}
