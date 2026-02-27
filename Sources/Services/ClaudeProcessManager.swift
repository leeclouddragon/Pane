import Foundation

private func debugLog(_ msg: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
    let path = "/tmp/pane_debug.log"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

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
        guard !isRunning else {
            debugLog("send() blocked — isRunning=true")
            return
        }
        isRunning = true
        lineBuffer = ""

        let exe = executablePath ?? Self.findClaudeBinary()
        debugLog("send() exe=\(exe) cwd=\(cwd) sessionId=\(sessionId ?? "nil")")

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
            args += ["--resume", sid]
        }

        args.append(prompt)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        debugLog("args=\(args)")

        // Environment: inherit + ensure claude is on PATH
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env["CLOTHER_NO_BANNER"] = "1"
        // GUI apps have minimal PATH; add common claude install locations
        let home = env["HOME"] ?? NSHomeDirectory()
        let extraPaths = [
            "\(home)/.local/bin",
            "\(home)/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
        ]
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
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
                debugLog("stderr: \(text)")
            }
        }

        process.terminationHandler = { [weak self] proc in
            debugLog("process terminated, status=\(proc.terminationStatus)")
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

            if !line.isEmpty {
                if line.contains("\"is_error\":true") || line.contains("error_during") {
                    debugLog("stdout[FULL]: \(line)")
                } else {
                    debugLog("stdout: \(line.prefix(200))")
                }
            }
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
