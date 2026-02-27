import Foundation

@Observable
final class ConversationState: Identifiable {
    let id: UUID
    var title: String
    var messages: [Message]
    var isStreaming: Bool
    var workingDirectory: String
    var draftText: String
    var totalCostUSD: Double
    var currentModel: String
    var inputTokens: Int
    var outputTokens: Int
    var cachedTokens: Int
    var totalTokens: Int
    var contextPercent: Double
    var gitBranch: String
    let sessionStart: Date

    /// Provider state — supplies the clother executable path.
    var providerState: ProviderState?

    let processManager = ClaudeProcessManager()

    /// Generation counter — incremented each send(). Stale events are discarded.
    private var eventGeneration: Int = 0
    /// The message index where the current process should write assistant content.
    private var targetAssistantIndex: Int = -1

    init(
        title: String = "New Thread",
        workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.isStreaming = false
        self.workingDirectory = workingDirectory
        self.draftText = ""
        self.totalCostUSD = 0
        self.currentModel = ""
        self.inputTokens = 0
        self.outputTokens = 0
        self.cachedTokens = 0
        self.totalTokens = 0
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
        if let firstUser = messages.first(where: { $0.role == .user }),
           case .text(let content) = firstUser.blocks.first {
            let trimmed = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(40))
        }
        return title
    }

    func send(_ text: String) {
        guard !text.isEmpty else { return }

        // Stop any in-flight process before starting a new one
        if processManager.isRunning {
            processManager.stop()
        }

        // Bump generation so stale events from old process are discarded
        eventGeneration += 1
        let gen = eventGeneration

        // Add user message
        let userMsg = Message(role: .user, blocks: [.text(TextContent(text: text))])
        messages.append(userMsg)
        draftText = ""

        // Start streaming assistant message
        isStreaming = true
        let assistantMsg = Message(role: .assistant, blocks: [])
        messages.append(assistantMsg)
        targetAssistantIndex = messages.count - 1

        // Set event handler with captured generation
        processManager.onEvent = { [weak self] event in
            self?.handleEvent(event, generation: gen)
        }

        processManager.send(
            prompt: text,
            cwd: workingDirectory,
            executablePath: providerState?.executablePath
        )
    }

    func stop() {
        processManager.stop()
        isStreaming = false
    }

    // MARK: - Event handling

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

    private func handleEvent(_ event: ClaudeEvent, generation: Int) {
        // Discard events from a previous (stale) process
        guard generation == eventGeneration else { return }

        let idx = targetAssistantIndex
        guard idx >= 0 && idx < messages.count else { return }

        switch event {
        case .systemInit(let info):
            currentModel = info.model
            workingDirectory = info.cwd
            refreshGitBranch()

        case .textDelta(let text):
            completeOpenThinkingBlocks(at: idx)
            if case .text(var content) = messages[idx].blocks.last {
                content.text += text
                messages[idx].blocks[messages[idx].blocks.count - 1] = .text(content)
            } else {
                messages[idx].blocks.append(.text(TextContent(text: text)))
            }

        case .toolUseStart(_, let id, let name):
            completeOpenThinkingBlocks(at: idx)
            messages[idx].blocks.append(
                .toolCall(ToolCallContent(tool: name, toolUseId: id, summary: "", detail: ""))
            )

        case .thinkingDelta(let text):
            // Append to current thinking block
            let blockCount = messages[idx].blocks.count
            if blockCount > 0,
               case .thinking(var content) = messages[idx].blocks[blockCount - 1] {
                content.text += text
                messages[idx].blocks[blockCount - 1] = .thinking(content)
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
            // Extract tool call summary
            if case .toolCall(var content) = messages[idx].blocks[blockCount - 1],
               !content.inputJson.isEmpty {
                content.extractSummary()
                messages[idx].blocks[blockCount - 1] = .toolCall(content)
            }

        case .assistantMessage:
            break

        case .result(let info):
            // Session not found — clear stale sessionId and auto-retry without duplicating user msg
            if info.isError && info.result.contains("No conversation found") {
                processManager.sessionId = nil
                if idx > 0, let userBlock = messages[idx - 1].blocks.first,
                   case .text(let content) = userBlock {
                    // Retry: bump generation, keep existing messages, just restart process
                    eventGeneration += 1
                    let gen = eventGeneration
                    processManager.onEvent = { [weak self] event in
                        self?.handleEvent(event, generation: gen)
                    }
                    processManager.send(
                        prompt: content.text,
                        cwd: workingDirectory,
                        executablePath: providerState?.executablePath
                    )
                    return
                }
            }

            completeOpenThinkingBlocks(at: idx)
            isStreaming = false
            totalCostUSD = info.costUSD
            inputTokens = info.inputTokens
            outputTokens = info.outputTokens
            cachedTokens = info.cacheReadTokens + info.cacheCreationTokens
            totalTokens = info.inputTokens + info.outputTokens + cachedTokens
            if info.isError {
                messages[idx].blocks.append(
                    .error(ErrorContent(message: info.result))
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
            for msgIdx in stride(from: messages.count - 1, through: 0, by: -1) {
                for blockIdx in stride(from: messages[msgIdx].blocks.count - 1, through: 0, by: -1) {
                    if case .toolCall(var content) = messages[msgIdx].blocks[blockIdx],
                       content.toolUseId == toolUseId {
                        content.detail = resultContent
                        content.isError = isError
                        content.isRunning = false
                        messages[msgIdx].blocks[blockIdx] = .toolCall(content)
                        return
                    }
                }
            }

        case .unknown:
            break
        }
    }
}
