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
        setupEventHandler()
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

        // Add user message
        let userMsg = Message(role: .user, blocks: [.text(TextContent(text: text))])
        messages.append(userMsg)
        draftText = ""

        // Start streaming assistant message
        isStreaming = true
        let assistantMsg = Message(role: .assistant, blocks: [])
        messages.append(assistantMsg)

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

    private func setupEventHandler() {
        processManager.onEvent = { [weak self] event in
            self?.handleEvent(event)
        }
    }

    private func handleEvent(_ event: ClaudeEvent) {
        guard !messages.isEmpty else { return }
        let lastIndex = messages.count - 1

        switch event {
        case .systemInit(let info):
            currentModel = info.model
            workingDirectory = info.cwd
            refreshGitBranch()

        case .textDelta(let text):
            // Append to last text block, or create one
            if case .text(var content) = messages[lastIndex].blocks.last {
                content.text += text
                messages[lastIndex].blocks[messages[lastIndex].blocks.count - 1] = .text(content)
            } else {
                messages[lastIndex].blocks.append(.text(TextContent(text: text)))
            }

        case .toolUseStart(_, let id, let name):
            messages[lastIndex].blocks.append(
                .toolCall(ToolCallContent(tool: name, toolUseId: id, summary: "", detail: ""))
            )

        case .contentBlockStop:
            // When a tool_use block finishes streaming, extract summary from accumulated JSON
            let blockCount = messages[lastIndex].blocks.count
            if blockCount > 0,
               case .toolCall(var content) = messages[lastIndex].blocks[blockCount - 1],
               !content.inputJson.isEmpty {
                content.extractSummary()
                messages[lastIndex].blocks[blockCount - 1] = .toolCall(content)
            }

        case .assistantMessage:
            // Full message already built from deltas; skip
            break

        case .result(let info):
            isStreaming = false
            totalCostUSD = info.costUSD
            inputTokens = info.inputTokens
            outputTokens = info.outputTokens
            cachedTokens = info.cacheReadTokens + info.cacheCreationTokens
            totalTokens = info.inputTokens + info.outputTokens + cachedTokens
            if info.isError {
                messages[lastIndex].blocks.append(
                    .error(ErrorContent(message: info.result))
                )
            }

        case .messageStart, .messageStop:
            break

        case .contentBlockStart(_, let type):
            if type == "thinking" {
                messages[lastIndex].blocks.append(
                    .thinking(ThinkingContent(text: ""))
                )
            }

        case .toolInputDelta(_, let json):
            // Accumulate JSON input into the last tool call block
            let blockCount = messages[lastIndex].blocks.count
            if blockCount > 0,
               case .toolCall(var content) = messages[lastIndex].blocks[blockCount - 1] {
                content.inputJson += json
                messages[lastIndex].blocks[blockCount - 1] = .toolCall(content)
            }

        case .toolResult(let toolUseId, let resultContent, let isError):
            // Find the matching tool call and attach result
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
