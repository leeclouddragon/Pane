import SwiftUI

/// Renders a single message. User = right-aligned compact card, Assistant = left-aligned plain text.
struct MessageView: View {
    let message: Message

    var body: some View {
        Group {
            if message.role == .user {
                userBubble
            } else {
                assistantContent
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - User message: compact right-aligned bubble

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(message.blocks) { block in
                ContentBlockView(block: block, compact: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Assistant message: left-aligned plain text

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(message.blocks) { block in
                ContentBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Conditional modifier

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
