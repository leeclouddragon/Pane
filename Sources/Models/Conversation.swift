import Foundation
import SwiftUI

/// Interaction mode — mirrors Claude Code's Shift+Tab cycling.
enum InteractionMode: CaseIterable {
    case normal       // default: confirm each edit
    case acceptEdits  // auto-accept file edits
    case plan         // read-only analysis

    var label: String {
        switch self {
        case .normal: return "? for shortcuts"
        case .acceptEdits: return "accept edits on"
        case .plan: return "plan mode on"
        }
    }

    var statusIcon: String {
        switch self {
        case .normal: return ">"
        case .acceptEdits: return ">>"
        case .plan: return "||"
        }
    }

    var color: Color {
        switch self {
        case .normal: return .orange
        case .acceptEdits: return .green
        case .plan: return .blue
        }
    }

    func next() -> InteractionMode {
        let all = Self.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }
}

struct PendingMessage: Identifiable {
    let id = UUID()
    let prompt: String       // full prompt sent to CLI
    let displayText: String  // user-visible text
    let attachments: [URL]
}

/// A question from AskUserQuestion tool waiting for user response.
struct PendingQuestion {
    let toolUseId: String
    let questions: [QuestionItem]

    struct QuestionItem {
        let question: String
        let header: String
        let options: [OptionItem]
        let multiSelect: Bool
    }

    struct OptionItem {
        let label: String
        let description: String
    }

    /// Parse from tool call's inputJson.
    static func parse(toolUseId: String, inputJson: String) -> PendingQuestion? {
        guard let data = inputJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawQuestions = obj["questions"] as? [[String: Any]]
        else { return nil }

        let items = rawQuestions.map { q in
            let options = (q["options"] as? [[String: Any]] ?? []).map { opt in
                OptionItem(
                    label: opt["label"] as? String ?? "",
                    description: opt["description"] as? String ?? ""
                )
            }
            return QuestionItem(
                question: q["question"] as? String ?? "",
                header: q["header"] as? String ?? "",
                options: options,
                multiSelect: q["multiSelect"] as? Bool ?? false
            )
        }
        return PendingQuestion(toolUseId: toolUseId, questions: items)
    }
}

@Observable
final class ConversationState: Identifiable {
    let id: UUID
    var title: String
    var messages: [Message]
    var isStreaming: Bool
    var isCompacting: Bool
    var workingDirectory: String
    var draftText: String
    var totalCostUSD: Double
    var currentModel: String
    var inputTokens: Int
    var outputTokens: Int
    var cachedTokens: Int
    var contextPercent: Double
    var gitBranch: String
    let sessionStart: Date
    var interactionMode: InteractionMode = .normal

    /// Bumped when the pane tree restructures (split/close) to re-anchor scroll position.
    var scrollNudge: Int = 0

    /// AskUserQuestion pending user response — shown as panel above composer.
    var pendingQuestion: PendingQuestion?

    /// Cycle to next interaction mode and invalidate pre-warmed process.
    func cycleMode() {
        interactionMode = interactionMode.next()
        processManager.discardPrewarm()
    }

    /// Provider state — supplies the list of available providers.
    var providerState: ProviderState?

    /// Per-conversation provider selection. Falls back to providerState default.
    var activeProviderID: String = ""

    /// Launch configuration for this conversation's selected provider.
    /// Uses `preferDirect` for non-normal modes to bypass clother's --dangerously-skip-permissions
    /// which would override --permission-mode plan/acceptEdits.
    /// Normal mode can safely use clother since both flags agree on bypass.
    var currentLaunchConfig: LaunchConfig {
        let preferDirect = (interactionMode == .plan || interactionMode == .acceptEdits)
        if let ps = providerState,
           let entry = ps.providers.first(where: { $0.id == activeProviderID }) {
            return ps.launchConfig(for: entry, preferDirect: preferDirect)
        }
        return LaunchConfig(
            executablePath: ClaudeProcessManager.findClaudeBinary(),
            env: [:],
            unsetEnv: []
        )
    }

    let processManager = ClaudeProcessManager()

    /// Generation counter — incremented each send(). Stale events are discarded.
    private var eventGeneration: Int = 0
    /// The message index where the current process should write assistant content.
    private var targetAssistantIndex: Int = -1
    /// Last prompt sent to CLI, kept for session-not-found retry.
    private var lastPrompt: String = ""

    /// Buffers for frame-rate batching of streaming deltas (~60fps).
    @ObservationIgnored private var textDeltaBuffer = ""
    @ObservationIgnored private var thinkingDeltaBuffer = ""
    @ObservationIgnored private var flushScheduled = false

    /// Messages queued while streaming. Displayed as cards above the composer;
    /// moved into `messages` when actually sent.
    var pendingMessages: [PendingMessage] = []

    /// Selected index in the slash command menu (shared so ConversationView can render the menu).
    var slashSelectedIndex: Int = 0

    init(
        title: String = "New Thread",
        workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.isStreaming = false
        self.isCompacting = false
        self.workingDirectory = workingDirectory
        self.draftText = ""
        self.totalCostUSD = 0
        self.currentModel = ""
        self.inputTokens = 0
        self.outputTokens = 0
        self.cachedTokens = 0
        self.contextPercent = 0
        self.gitBranch = ""
        self.sessionStart = Date()
        refreshGitBranch()
    }

    func refreshGitBranch() {
        let cwd = workingDirectory
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let branch = Self.detectGitBranch(in: cwd)
            DispatchQueue.main.async {
                self?.gitBranch = branch
            }
        }
    }

    private static func detectGitBranch(in dir: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return process.terminationStatus == 0 && !output.isEmpty ? output : ""
        } catch {
            return ""
        }
    }

    /// Display title: first user message or "New Thread"
    var displayTitle: String {
        if let firstUser = messages.first(where: { $0.role == .user }) {
            if let textBlock = firstUser.blocks.first(where: {
                if case .text = $0 { return true } else { return false }
            }), case .text(let content) = textBlock {
                let trimmed = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return String(trimmed.prefix(40))
            }
            if firstUser.blocks.contains(where: {
                if case .image = $0 { return true } else { return false }
            }) {
                return "Image"
            }
        }
        return title
    }

    func send(_ text: String, attachments: [URL] = []) {
        guard !text.isEmpty || !attachments.isEmpty else { return }

        // Build prompt: user text + attachment references
        var prompt = text
        if !attachments.isEmpty {
            let refs = attachments.map { $0.path }.joined(separator: "\n")
            if prompt.isEmpty {
                prompt = "Please look at the attached image(s):\n\(refs)"
            } else {
                prompt += "\n\n[attached: \(refs)]"
            }
        }

        draftText = ""

        // If currently streaming, queue as pending (shown as card above composer)
        if isStreaming {
            pendingMessages.append(PendingMessage(
                prompt: prompt, displayText: text, attachments: attachments
            ))
            return
        }

        // Add user message to chat and start request
        appendUserMessage(text: text, attachments: attachments)
        startRequest(prompt: prompt)
    }

    /// Execute a local slash command (handled by Pane, not sent to CLI).
    func executeLocal(_ action: LocalAction) {
        switch action {
        case .clear:
            messages.removeAll()
            targetAssistantIndex = -1
        }
    }

    func removePending(at index: Int) {
        guard pendingMessages.indices.contains(index) else { return }
        pendingMessages.remove(at: index)
    }

    func removePending(id: UUID) {
        pendingMessages.removeAll { $0.id == id }
    }

    private func appendUserMessage(text: String, attachments: [URL]) {
        var userBlocks: [ContentBlock] = attachments.map { .image(ImageContent(url: $0)) }
        if !text.isEmpty {
            userBlocks.append(.text(TextContent(text: text)))
        }
        messages.append(Message(role: .user, blocks: userBlocks))
    }

    private func startRequest(prompt: String) {
        // Stop any in-flight process before starting a new one
        if processManager.isRunning {
            processManager.stop()
        }

        // Bump generation so stale events from old process are discarded
        eventGeneration += 1
        let gen = eventGeneration

        // Start streaming assistant message
        isStreaming = true
        messages.append(Message(role: .assistant, blocks: []))
        targetAssistantIndex = messages.count - 1

        // Set event handler with captured generation
        processManager.onEvent = { [weak self] event in
            self?.handleEvent(event, generation: gen)
        }

        lastPrompt = prompt
        let lc = currentLaunchConfig
        processManager.send(
            prompt: prompt,
            cwd: workingDirectory,
            executablePath: lc.executablePath,
            providerEnv: lc.env,
            providerUnsetEnv: lc.unsetEnv,
            permissionMode: interactionMode
        )
    }

    /// Send a tool result back to the CLI via stdin (e.g. AskUserQuestion response).
    func respondToTool(toolUseId: String, result: String) {
        let data = processManager.adapter.encodeToolResult(toolUseId: toolUseId, result: result)
        processManager.writeToStdin(data)
    }

    /// Answer the pending AskUserQuestion and clear it.
    func answerQuestion(answers: [String: String]) {
        guard let pq = pendingQuestion else { return }
        if let data = try? JSONSerialization.data(withJSONObject: ["answers": answers]),
           let json = String(data: data, encoding: .utf8) {
            respondToTool(toolUseId: pq.toolUseId, result: json)
        }
        pendingQuestion = nil
    }

    /// Skip the pending AskUserQuestion.
    func skipQuestion() {
        guard let pq = pendingQuestion else { return }
        respondToTool(toolUseId: pq.toolUseId, result: "{\"skipped\": true}")
        pendingQuestion = nil
    }

    func stop() {
        flushBuffers()
        processManager.stop()
        isStreaming = false
        // Clean up empty assistant message if no content was received
        if targetAssistantIndex >= 0 && targetAssistantIndex < messages.count
            && messages[targetAssistantIndex].blocks.isEmpty {
            messages.remove(at: targetAssistantIndex)
            targetAssistantIndex = -1
        }
        sendNextPending()
    }

    private func sendNextPending() {
        guard !pendingMessages.isEmpty else { return }
        let next = pendingMessages.removeFirst()
        appendUserMessage(text: next.displayText, attachments: next.attachments)
        startRequest(prompt: next.prompt)
    }

    // MARK: - Event handling

    private func scheduleFlush(generation: Int) {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            guard generation == self.eventGeneration else {
                self.textDeltaBuffer = ""
                self.thinkingDeltaBuffer = ""
                return
            }
            self.flushBuffers()
        }
    }

    private func flushBuffers() {
        flushScheduled = false
        guard !textDeltaBuffer.isEmpty || !thinkingDeltaBuffer.isEmpty else { return }

        let idx = targetAssistantIndex
        guard idx >= 0 && idx < messages.count else {
            textDeltaBuffer = ""
            thinkingDeltaBuffer = ""
            return
        }

        if !thinkingDeltaBuffer.isEmpty {
            let blockCount = messages[idx].blocks.count
            if blockCount > 0,
               case .thinking(var content) = messages[idx].blocks[blockCount - 1] {
                content.text += thinkingDeltaBuffer
                messages[idx].blocks[blockCount - 1] = .thinking(content)
            }
            thinkingDeltaBuffer = ""
        }

        if !textDeltaBuffer.isEmpty {
            completeOpenThinkingBlocks(at: idx)
            if case .text(var content) = messages[idx].blocks.last {
                content.text += textDeltaBuffer
                messages[idx].blocks[messages[idx].blocks.count - 1] = .text(content)
            } else {
                messages[idx].blocks.append(.text(TextContent(text: textDeltaBuffer)))
            }
            textDeltaBuffer = ""
        }
    }

    /// Mark all incomplete thinking blocks as complete in the given message.
    private func completeOpenThinkingBlocks(at msgIdx: Int) {
        for blockIdx in 0..<messages[msgIdx].blocks.count {
            if case .thinking(var content) = messages[msgIdx].blocks[blockIdx], !content.isComplete {
                content.isComplete = true
                if content.endTime == nil { content.endTime = Date() }
                messages[msgIdx].blocks[blockIdx] = .thinking(content)
            }
        }
    }

    /// Mark all still-running tool calls as complete in the given message.
    private func completeOpenToolCalls(at msgIdx: Int) {
        for blockIdx in 0..<messages[msgIdx].blocks.count {
            if case .toolCall(var content) = messages[msgIdx].blocks[blockIdx], content.isRunning {
                content.isRunning = false
                messages[msgIdx].blocks[blockIdx] = .toolCall(content)
            }
        }
    }

    private func handleEvent(_ event: ClaudeEvent, generation: Int) {
        // Discard events from a previous (stale) process
        guard generation == eventGeneration else { return }

        // Buffer high-frequency deltas for frame-rate flushing (~60fps)
        switch event {
        case .textDelta(let text):
            textDeltaBuffer += text
            scheduleFlush(generation: generation)
            return
        case .thinkingDelta(let text):
            thinkingDeltaBuffer += text
            scheduleFlush(generation: generation)
            return
        default:
            flushBuffers()
        }

        let idx = targetAssistantIndex
        guard idx >= 0 && idx < messages.count else { return }

        switch event {
        case .systemInit(let info):
            currentModel = info.model
            if !info.cwd.isEmpty {
                workingDirectory = info.cwd
            }
            // Sync interaction mode from CLI's actual permission mode
            if !info.permissionMode.isEmpty {
                let cliMode: InteractionMode
                switch info.permissionMode {
                case "plan": cliMode = .plan
                case "acceptEdits": cliMode = .acceptEdits
                default: cliMode = .normal
                }
                if interactionMode != cliMode {
                    interactionMode = cliMode
                    processManager.discardPrewarm()
                }
            }
            refreshGitBranch()

        case .textDelta, .thinkingDelta:
            break // handled by frame-rate buffer above

        case .toolUseStart(_, let id, let name):
            completeOpenThinkingBlocks(at: idx)
            messages[idx].blocks.append(
                .toolCall(ToolCallContent(tool: name, toolUseId: id, summary: "", detail: ""))
            )
            // Sync mode when CLI autonomously enters/exits plan mode
            if name == "EnterPlanMode" && interactionMode != .plan {
                interactionMode = .plan
                processManager.discardPrewarm()
            }

        case .contentBlockStop:
            let blockCount = messages[idx].blocks.count
            guard blockCount > 0 else { break }
            // Mark thinking block as complete
            if case .thinking(var content) = messages[idx].blocks[blockCount - 1] {
                content.isComplete = true
                content.endTime = Date()
                messages[idx].blocks[blockCount - 1] = .thinking(content)
            }
            // Extract tool call summary + detect AskUserQuestion
            if case .toolCall(var content) = messages[idx].blocks[blockCount - 1],
               !content.inputJson.isEmpty {
                content.extractSummary()
                messages[idx].blocks[blockCount - 1] = .toolCall(content)

                // Surface AskUserQuestion as a floating panel
                if content.tool.lowercased() == "askuserquestion" {
                    pendingQuestion = PendingQuestion.parse(
                        toolUseId: content.toolUseId,
                        inputJson: content.inputJson
                    )
                }
            }

        case .assistantMessage:
            break

        case .result(let info):
            // Session not found — clear stale sessionId and auto-retry without duplicating user msg
            if info.isError && info.result.contains("No conversation found") {
                processManager.sessionId = nil
                guard !lastPrompt.isEmpty else { break }

                // Retry with the exact same prompt
                eventGeneration += 1
                let gen = eventGeneration
                processManager.onEvent = { [weak self] event in
                    self?.handleEvent(event, generation: gen)
                }
                let lc = currentLaunchConfig
                processManager.send(
                    prompt: lastPrompt,
                    cwd: workingDirectory,
                    executablePath: lc.executablePath,
                    providerEnv: lc.env,
                    providerUnsetEnv: lc.unsetEnv,

                    permissionMode: interactionMode
                )
                return
            }

            completeOpenThinkingBlocks(at: idx)
            completeOpenToolCalls(at: idx)
            isStreaming = false
            isCompacting = false
            // Record response duration on the assistant message
            if info.durationMs > 0 {
                messages[idx].durationSeconds = max(info.durationMs / 1000, 1)
            }
            totalCostUSD = info.costUSD
            inputTokens += info.inputTokens
            outputTokens += info.outputTokens
            cachedTokens += info.cacheReadTokens + info.cacheCreationTokens
            if let pct = info.contextUsedPercent {
                contextPercent = Double(pct) / 100.0
            }
            if info.isError {
                messages[idx].blocks.append(
                    .error(ErrorContent(message: info.result))
                )
            } else if messages[idx].blocks.isEmpty && !info.result.isEmpty {
                // Slash commands handled locally by CLI return result text without content blocks
                messages[idx].blocks.append(
                    .systemResult(SystemResultContent(text: info.result))
                )
            }
            // Remove empty assistant message if still nothing to show
            if messages[idx].blocks.isEmpty {
                messages.remove(at: idx)
                targetAssistantIndex = -1
            }

            // Send next pending message, or pre-warm
            if !pendingMessages.isEmpty {
                sendNextPending()
            } else if !info.isError {
                let lc = currentLaunchConfig
                processManager.prewarm(
                    cwd: workingDirectory,
                    executablePath: lc.executablePath,
                    providerEnv: lc.env,
                    providerUnsetEnv: lc.unsetEnv,

                    permissionMode: interactionMode
                )
            }

        case .messageStart, .messageStop:
            break

        case .contentBlockStart(_, let type):
            if type == "thinking" {
                messages[idx].blocks.append(
                    .thinking(ThinkingContent(text: ""))
                )
            } else {
                completeOpenThinkingBlocks(at: idx)
            }

        case .toolInputDelta(_, let json):
            let blockCount = messages[idx].blocks.count
            if blockCount > 0,
               case .toolCall(var content) = messages[idx].blocks[blockCount - 1] {
                content.inputJson += json
                messages[idx].blocks[blockCount - 1] = .toolCall(content)
            }

        case .toolResult(let toolUseId, let resultContent, let isError):
            // Clear pending question if this result is for it
            if pendingQuestion?.toolUseId == toolUseId {
                pendingQuestion = nil
            }
            for msgIdx in stride(from: messages.count - 1, through: 0, by: -1) {
                for blockIdx in stride(from: messages[msgIdx].blocks.count - 1, through: 0, by: -1) {
                    if case .toolCall(var content) = messages[msgIdx].blocks[blockIdx],
                       content.toolUseId == toolUseId {
                        // Cap stored output to prevent memory bloat (100K chars)
                        if resultContent.count > 100_000 {
                            content.detail = String(resultContent.prefix(100_000))
                                + "\n\n… truncated (\(resultContent.count) total chars)"
                        } else {
                            content.detail = resultContent
                        }
                        content.isError = isError
                        content.isRunning = false
                        messages[msgIdx].blocks[blockIdx] = .toolCall(content)
                        return
                    }
                }
            }

        case .compacting:
            isCompacting = true

        case .compactDone:
            isCompacting = false

        case .unknown:
            break
        }
    }
}
