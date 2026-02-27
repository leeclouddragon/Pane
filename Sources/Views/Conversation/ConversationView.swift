import SwiftUI

/// A complete conversation pane.
/// Welcome state: centered composer with folder/provider + session history.
/// Active state: message scroll + composer + status bar at bottom.
struct ConversationView: View {
    @Bindable var conversation: ConversationState
    @Environment(AppSettings.self) private var settings
    @State private var recentSessions: [SessionEntry] = []
    @State private var sessionsLoaded = false

    var body: some View {
        if conversation.messages.isEmpty {
            welcomeLayout
        } else {
            conversationLayout
        }
    }

    // MARK: - Welcome layout

    private var welcomeLayout: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Logo
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(.quaternary.opacity(0.4))
                            .frame(width: 56, height: 56)
                        Image(systemName: "terminal")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.secondary)
                    }

                    Text("Pane")
                        .font(.system(size: 18, weight: .semibold))
                }

                // Composer
                ComposerView(conversation: conversation, isWelcome: true)
                    .frame(maxWidth: min(contentMaxWidth, 600))

                // Recent sessions
                if !recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Recent")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)

                        ForEach(recentSessions) { session in
                            Button(action: { resumeSession(session) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "text.bubble")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 16)

                                    Text(session.firstMessage)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(shortPath(session.cwd))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.quaternary)
                                        .lineLimit(1)

                                    Text(relativeDate(session.modifiedDate))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.quaternary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: min(contentMaxWidth, 600))
                }
            }

            Spacer()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            guard !sessionsLoaded else { return }
            sessionsLoaded = true
            DispatchQueue.global(qos: .userInitiated).async {
                let result = SessionHistory.scan(limit: 8)
                DispatchQueue.main.async {
                    recentSessions = result
                }
            }
        }
    }

    // MARK: - Conversation layout

    private var conversationLayout: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(conversation.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                    }
                    .frame(maxWidth: contentMaxWidth, alignment: .center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: conversation.messages.count) {
                    if let last = conversation.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            VStack(spacing: 6) {
                ComposerView(conversation: conversation)

                StatusBarView(conversation: conversation)
            }
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Helpers

    private var contentMaxWidth: CGFloat {
        settings.widthMode.maxWidth ?? .infinity
    }

    private func resumeSession(_ session: SessionEntry) {
        conversation.workingDirectory = session.cwd
        conversation.processManager.sessionId = session.id
        conversation.refreshGitBranch()

        // Load historical messages from JSONL
        DispatchQueue.global(qos: .userInitiated).async {
            let messages = SessionHistory.loadMessages(from: session.filePath)
            DispatchQueue.main.async {
                conversation.messages = messages
            }
        }
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let days = Int(interval / 86400)
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days)d ago" }
        return "\(days / 7)w ago"
    }
}
