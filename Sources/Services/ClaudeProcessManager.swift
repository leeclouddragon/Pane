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
/// Supports process pre-warming: a process is started ahead of time (without a prompt),
/// so that Node.js + CLI initialization is already done when the user sends a message.
@Observable
final class ClaudeProcessManager {
    private var process: Process?
    private var lineBuffer = ""
    private var resultReceived = false

    // Pre-warm state
    private var warmProcess: Process?
    private var warmStdinPipe: Pipe?
    private var warmStdoutPipe: Pipe?
    private var warmStderrPipe: Pipe?
    private var warmCwd: String?
    private var warmExePath: String?

    // Cached environment (built once, reused)
    private var cachedEnv: [String: String]?

    var sessionId: String?
    var isRunning: Bool = false

    /// Callback for parsed events — called on main thread.
    var onEvent: ((ClaudeEvent) -> Void)?

    /// Find the claude binary in common locations (cached).
    private static var resolvedBinary: String?
    static func findClaudeBinary() -> String {
        if let cached = resolvedBinary { return cached }
        let candidates = [
            ProcessInfo.processInfo.environment["HOME"].map { "\($0)/.local/bin/claude" },
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ].compactMap { $0 }
        let result = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
        resolvedBinary = result
        return result
    }

    /// Build and cache the environment dictionary.
    private func resolveEnv() -> [String: String] {
        if let cached = cachedEnv { return cached }
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env["CLOTHER_NO_BANNER"] = "1"
        let home = env["HOME"] ?? NSHomeDirectory()
        let extraPaths = [
            "\(home)/.local/bin",
            "\(home)/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
        ]
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        cachedEnv = env
        return env
    }

    /// Build CLI arguments (without prompt).
    private func buildArgs() -> [String] {
        var args = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
        ]
        if let sid = sessionId {
            args += ["--resume", sid]
        }
        return args
    }

    // MARK: - Pre-warm

    /// Start a process ahead of time without a prompt.
    /// The process initializes (Node.js startup, config loading, MCP connections)
    /// and waits for stdin input. When send() is called, the prompt is piped in.
    func prewarm(cwd: String, executablePath: String? = nil) {
        // Don't pre-warm if one is already running
        guard warmProcess == nil else { return }

        let exe = executablePath ?? Self.findClaudeBinary()
        let env = resolveEnv()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = buildArgs() // no prompt — reads from stdin
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        proc.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        // Buffer stdout during pre-warm (captures system init event)
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            // Process events during pre-warm to capture session ID
            self?.processChunk(chunk)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                debugLog("prewarm stderr: \(text)")
            }
        }

        proc.terminationHandler = { [weak self] p in
            debugLog("prewarm process terminated, status=\(p.terminationStatus)")
            DispatchQueue.main.async {
                if self?.warmProcess === p {
                    self?.warmProcess = nil
                }
            }
        }

        do {
            try proc.run()
            warmProcess = proc
            warmStdinPipe = stdinPipe
            warmStdoutPipe = stdoutPipe
            warmStderrPipe = stderrPipe
            warmCwd = cwd
            warmExePath = exe
            debugLog("prewarm: started (exe=\(exe) cwd=\(cwd) sid=\(sessionId ?? "nil"))")
        } catch {
            debugLog("prewarm: failed — \(error)")
        }
    }

    /// Discard a pre-warmed process (e.g. when cwd or provider changes).
    func discardPrewarm() {
        warmProcess?.terminate()
        warmProcess = nil
        warmStdinPipe = nil
        warmStdoutPipe = nil
        warmStderrPipe = nil
    }

    // MARK: - Send

    func send(prompt: String, cwd: String, executablePath: String? = nil) {
        guard !isRunning else {
            debugLog("send() blocked — isRunning=true")
            return
        }
        isRunning = true
        lineBuffer = ""
        resultReceived = false

        let exe = executablePath ?? Self.findClaudeBinary()

        // Try to use a pre-warmed process
        if let warm = warmProcess, warm.isRunning,
           warmCwd == cwd, warmExePath == exe {
            debugLog("send() using pre-warmed process")
            adoptWarmProcess(prompt: prompt)
        } else {
            // Discard stale pre-warm if any
            discardPrewarm()
            debugLog("send() creating new process (exe=\(exe) cwd=\(cwd) sid=\(sessionId ?? "nil"))")
            launchNewProcess(prompt: prompt, cwd: cwd, exe: exe)
        }
    }

    /// Take ownership of the pre-warmed process and send the prompt via stdin.
    private func adoptWarmProcess(prompt: String) {
        guard let proc = warmProcess else { return }

        self.process = proc
        warmProcess = nil

        // Replace termination handler with the real one
        proc.terminationHandler = { [weak self] p in
            debugLog("process terminated, status=\(p.terminationStatus) resultReceived=\(self?.resultReceived ?? false)")
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                if !self.resultReceived {
                    let status = p.terminationStatus
                    let msg = status == 0
                        ? "Process ended without response"
                        : "Process exited with status \(status)"
                    self.onEvent?(.result(ResultInfo(
                        sessionId: self.sessionId ?? "",
                        result: msg,
                        isError: true,
                        costUSD: 0, durationMs: 0,
                        inputTokens: 0, outputTokens: 0,
                        cacheReadTokens: 0, cacheCreationTokens: 0
                    )))
                }
            }
        }

        // Write prompt to stdin and close (signals EOF → CLI reads prompt)
        if let handle = warmStdinPipe?.fileHandleForWriting {
            handle.write(prompt.data(using: .utf8)!)
            handle.closeFile()
        }

        warmStdinPipe = nil
        warmStdoutPipe = nil
        warmStderrPipe = nil
        warmCwd = nil
        warmExePath = nil
    }

    /// Launch a brand new process with the prompt as a CLI argument.
    private func launchNewProcess(prompt: String, cwd: String, exe: String) {
        let env = resolveEnv()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        var args = buildArgs()
        args.append(prompt)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        proc.environment = env
        debugLog("args=\(args)")

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self?.processChunk(chunk)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                debugLog("stderr: \(text)")
            }
        }

        proc.terminationHandler = { [weak self] p in
            debugLog("process terminated, status=\(p.terminationStatus) resultReceived=\(self?.resultReceived ?? false)")
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                if !self.resultReceived {
                    let status = p.terminationStatus
                    let msg = status == 0
                        ? "Process ended without response"
                        : "Process exited with status \(status)"
                    self.onEvent?(.result(ResultInfo(
                        sessionId: self.sessionId ?? "",
                        result: msg,
                        isError: true,
                        costUSD: 0, durationMs: 0,
                        inputTokens: 0, outputTokens: 0,
                        cacheReadTokens: 0, cacheCreationTokens: 0
                    )))
                }
            }
        }

        self.process = proc

        do {
            try proc.run()
        } catch {
            isRunning = false
            let errorEvent = ClaudeEvent.result(ResultInfo(
                sessionId: "",
                result: "Failed to launch: \(error.localizedDescription)\nPath: \(exe)",
                isError: true,
                costUSD: 0, durationMs: 0,
                inputTokens: 0, outputTokens: 0,
                cacheReadTokens: 0, cacheCreationTokens: 0
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
                if case .result = event {
                    resultReceived = true
                }
                DispatchQueue.main.async { [weak self] in
                    self?.onEvent?(event)
                }
            }
        }
    }
}
