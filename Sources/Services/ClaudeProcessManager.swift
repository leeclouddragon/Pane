import Foundation

/// Manages a claude CLI subprocess per conversation.
@Observable
final class ClaudeProcessManager {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var lineBuffer = ""

    var sessionId: String?
    var isRunning: Bool = false

    /// Callback for parsed events — called on main thread.
    var onEvent: ((ClaudeEvent) -> Void)?

    /// Find the claude binary in common locations.
    static func findClaudeBinary() -> String {
        let candidates = [
            ProcessInfo.processInfo.environment["HOME"].map { "\($0)/.local/bin/claude" },
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
    }

    /// Send a prompt via claude CLI (or clother wrapper) with streaming JSON output.
    /// - Parameters:
    ///   - prompt: User message text
    ///   - cwd: Working directory for the CLI process
    ///   - executablePath: Path to claude binary or clother-* script
    func send(prompt: String, cwd: String, executablePath: String? = nil) {
        guard !isRunning else { return }
        isRunning = true

        let exe = executablePath ?? Self.findClaudeBinary()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)

        var args = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
        ]

        // Resume session if we have one
        if let sid = sessionId {
            args += ["--resume", sid, "--continue"]
        }

        args.append(prompt)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        // Environment: inherit + unset CLAUDECODE (prevent nested session detection)
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        // Suppress clother banner in non-tty context
        env["CLOTHER_NO_BANNER"] = "1"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Read stdout line by line
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self?.processChunk(chunk)
        }

        // Stderr: log but don't crash
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                print("[claude stderr] \(text)")
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }

        self.process = process

        do {
            try process.run()
        } catch {
            isRunning = false
            let errorEvent = ClaudeEvent.result(ResultInfo(
                sessionId: "",
                result: "Failed to launch: \(error.localizedDescription)\nPath: \(exe)",
                isError: true,
                costUSD: 0,
                durationMs: 0,
                inputTokens: 0,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0
            ))
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(errorEvent)
            }
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
    }

    // MARK: - Line buffering

    private func processChunk(_ chunk: String) {
        lineBuffer += chunk
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])

            if !line.isEmpty, let event = StreamParser.parse(line: line) {
                // Capture session ID from init
                if case .systemInit(let info) = event {
                    DispatchQueue.main.async { [weak self] in
                        self?.sessionId = info.sessionId
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    self?.onEvent?(event)
                }
            }
        }
    }
}
