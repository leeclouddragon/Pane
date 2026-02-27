import SwiftUI

/// iTerm2-style title bar: traffic lights → thread tab.
struct TitleBarView: View {
    var body: some View {
        HStack(spacing: 0) {
            // Traffic light zone
            Color.clear.frame(width: 78, height: 1)

            // Thread tab
            ThreadTab(title: "New Thread", isActive: true)

            Spacer()
        }
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Tab

struct ThreadTab: View {
    let title: String
    let isActive: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // Close button on hover
            Group {
                if isHovered {
                    Button(action: {}) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .background(.quaternary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
            }

            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isActive
                ? Color(nsColor: .textBackgroundColor).opacity(0.6)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
    }
}
