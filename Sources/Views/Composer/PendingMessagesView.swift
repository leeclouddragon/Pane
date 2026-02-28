import SwiftUI

/// Shows queued user messages as cards above the composer while the agent is streaming.
struct PendingMessagesView: View {
    @Bindable var conversation: ConversationState

    var body: some View {
        VStack(spacing: 4) {
            ForEach(conversation.pendingMessages) { pending in
                PendingMessageCard(pending: pending, onEdit: {
                    conversation.draftText = pending.displayText
                    conversation.removePending(id: pending.id)
                }, onDelete: {
                    conversation.removePending(id: pending.id)
                })
            }
        }
    }
}

private struct PendingMessageCard: View {
    let pending: PendingMessage
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Text(pending.displayText)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Edit message")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove queued message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
        )
    }
}
