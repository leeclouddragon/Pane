import SwiftUI

/// A complete conversation pane.
/// Welcome state: centered composer with folder/provider + session history.
/// Active state: message scroll + composer + status bar at bottom.
struct ConversationView: View {
    @Bindable var conversation: ConversationState
    @Environment(AppSettings.self) private var settings
    @Environment(PaneState.self) private var paneState
    @State private var recentSessions: [SessionEntry] = []
    @State private var sessionsLoaded = false
    @State private var allCandidates: [SessionEntry] = []
    @State private var nextCandidateIndex = 0
    @State private var hasMoreSessions = true
    @State private var isLoadingMore = false
    private let sessionPageSize = 20

    // MARK: - Slash menu (computed from conversation.draftText)

    private var showSlashMenu: Bool {
        conversation.draftText.hasPrefix("/") && !conversation.isStreaming
    }

    private var slashQuery: String {
        guard showSlashMenu else { return "" }
        return String(conversation.draftText.dropFirst())
    }

    private var filteredSlashCommands: [SlashCommand] {
        SlashCommand.filtered(by: slashQuery)
    }

    @ViewBuilder
    private var slashMenuView: some View {
        if showSlashMenu && !filteredSlashCommands.isEmpty {
            SlashMenuView(
                commands: filteredSlashCommands,
                selectedIndex: conversation.slashSelectedIndex,
                onSelect: { cmd in
                    conversation.draftText = ""
                    if cmd.type == .local, let action = cmd.localAction {
                        conversation.executeLocal(action)
                    } else {
                        conversation.send(cmd.command)
                    }
                }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeOut(duration: 0.12), value: showSlashMenu)
        }
    }

    private var isFocusedPane: Bool {
        paneState.activeConversation === conversation
    }

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
                    ComposeIconView(size: 36)
                        .foregroundStyle(.secondary)

                    Text("Pane")
                        .font(.system(size: 16, weight: .semibold))
                }

                // Slash menu + Composer
                slashMenuView
                ComposerView(conversation: conversation, isWelcome: true, isFocused: isFocusedPane)

                // Recent sessions
                if !recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            ClockIconView(size: 12)
                            Text("Recent")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)

                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(recentSessions) { session in
                                    Button(action: { resumeSession(session) }) {
                                        HStack(spacing: 8) {
                                            ComposeIconView(size: 12)
                                                .foregroundStyle(.tertiary)
                                                .frame(width: 16)

                                            Text(session.firstMessage)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)

                                            Spacer()

                                            Text(shortPath(session.cwd))
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.quaternary)
                                                .lineLimit(1)

                                            Text(relativeDate(session.modifiedDate))
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.quaternary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }

                                if hasMoreSessions {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .onAppear { loadMoreSessions() }
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                }
            }
            .frame(maxWidth: min(contentMaxWidth, 600))
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            guard !sessionsLoaded else { return }
            sessionsLoaded = true
            DispatchQueue.global(qos: .userInitiated).async {
                let candidates = SessionHistory.allCandidates()
                DispatchQueue.main.async {
                    allCandidates = candidates
                    loadMoreSessions()
                }
            }
        }
    }

    // MARK: - Conversation layout

    private var showPlanActionBar: Bool {
        conversation.interactionMode == .plan
        && !conversation.isStreaming
        && (conversation.messages.last?.role == .assistant)
        && !(conversation.messages.last?.blocks.isEmpty ?? true)
    }

    private var conversationLayout: some View {
        VStack(spacing: 0) {
            if conversation.interactionMode == .plan {
                PlanModeBanner()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(conversation.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                        if conversation.isCompacting {
                            CompactingIndicator()
                                .padding(.vertical, 6)
                        }
                        // Activity indicator: streaming only (completion durations are inline per message)
                        if conversation.isStreaming {
                            ActivityIndicator(
                                isStreaming: true,
                                startTime: conversation.messages.last?.timestamp,
                                durationSeconds: nil
                            )
                        }
                        // Invisible anchor at the very bottom (includes bottom padding)
                        Color.clear
                            .frame(height: 24)
                            .id("bottom")
                    }
                    .frame(maxWidth: contentMaxWidth, alignment: .center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
                .scrollContentBackground(.hidden)
                .defaultScrollAnchor(.bottom)
                .onChange(of: conversation.messages.count) {
                    scrollToBottom(proxy)
                }
                .onChange(of: conversation.messages.last?.blocks.count) {
                    if conversation.isStreaming {
                        scrollToBottom(proxy)
                    }
                }
                .onChange(of: lastBlockContentLength) {
                    if conversation.isStreaming {
                        scrollToBottom(proxy)
                    }
                }
                .onChange(of: conversation.isStreaming) {
                    scrollToBottom(proxy)
                }
                .onChange(of: conversation.isCompacting) {
                    scrollToBottom(proxy)
                }
                .onAppear {
                    scrollToBottom(proxy)
                }
            }

            VStack(spacing: 6) {
                if showPlanActionBar {
                    PlanActionBar { mode in
                        conversation.interactionMode = mode
                        conversation.processManager.discardPrewarm()
                        let prompt = mode == .acceptEdits
                            ? "Execute the plan above. Proceed with all changes."
                            : "Execute the plan above."
                        conversation.send(prompt)
                    }
                }

                slashMenuView

                if !conversation.pendingMessages.isEmpty {
                    PendingMessagesView(conversation: conversation)
                }

                ComposerView(conversation: conversation, isFocused: isFocusedPane)

                StatusBarView(conversation: conversation)
            }
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Helpers

    private func loadMoreSessions() {
        guard hasMoreSessions, !isLoadingMore else { return }
        isLoadingMore = true

        let batchSize = sessionPageSize * 3 // over-fetch to account for empty sessions
        let endIndex = min(nextCandidateIndex + batchSize, allCandidates.count)
        guard nextCandidateIndex < endIndex else {
            hasMoreSessions = false
            isLoadingMore = false
            return
        }
        let batch = Array(allCandidates[nextCandidateIndex..<endIndex])

        DispatchQueue.global(qos: .userInitiated).async {
            let enriched = SessionHistory.enrich(batch)
            let page = Array(enriched.prefix(sessionPageSize))
            DispatchQueue.main.async {
                recentSessions.append(contentsOf: page)
                nextCandidateIndex = endIndex
                hasMoreSessions = nextCandidateIndex < allCandidates.count
                isLoadingMore = false
            }
        }
    }

    /// Content length of the last block in the last message — triggers scroll on any streaming content.
    /// Capped to avoid expensive .count on very large strings (only used as change signal).
    private var lastBlockContentLength: Int {
        guard let lastMsg = conversation.messages.last,
              let lastBlock = lastMsg.blocks.last else { return 0 }
        switch lastBlock {
        case .text(let c): return min(c.text.count, 50_000)
        case .thinking(let c): return min(c.text.count, 50_000)
        case .toolCall(let c): return min(c.inputJson.count, 50_000) + min(c.detail.count, 50_000)
        case .code(let c): return min(c.code.count, 50_000)
        case .error(let c): return min(c.message.count, 50_000)
        default: return 0
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        // Defer to next run loop so layout is finalized before scrolling
        DispatchQueue.main.async {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var contentMaxWidth: CGFloat {
        settings.widthMode.maxWidth ?? .infinity
    }

    private func resumeSession(_ session: SessionEntry) {
        conversation.workingDirectory = session.cwd
        conversation.processManager.sessionId = session.id
        conversation.refreshGitBranch()

        // Load historical messages + token data from JSONL
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SessionHistory.loadMessages(from: session.filePath)
            DispatchQueue.main.async {
                conversation.messages = result.messages
                conversation.inputTokens = result.inputTokens
                conversation.outputTokens = result.outputTokens
                conversation.cachedTokens = result.cacheReadTokens + result.cacheCreationTokens
                conversation.totalCostUSD = result.costUSD
                conversation.contextPercent = result.contextPercent
                if !result.model.isEmpty {
                    conversation.currentModel = result.model
                }
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
