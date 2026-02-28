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
    // Internal state accessed from background threads — must be excluded
    // from @Observable tracking to avoid deadlocking with the main thread.
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var lineBuffer = ""
    @ObservationIgnored private var resultReceived = false

    /// Serial queue protecting lineBuffer from concurrent access by readability handlers.
    @ObservationIgnored private let parseQueue = DispatchQueue(label: "com.pane.line-parser")

    // Active stdin handle — kept open for interactive tool responses (e.g. AskUserQuestion)
    @ObservationIgnored private var activeStdinHandle: FileHandle?

    // Pre-warm state (background thread access)
    @ObservationIgnored private var warmProcess: Process?
    @ObservationIgnored private var warmStdinPipe: Pipe?
    @ObservationIgnored private var warmStdoutPipe: Pipe?
    @ObservationIgnored private var warmStderrPipe: Pipe?
    @ObservationIgnored private var warmCwd: String?
    @ObservationIgnored private var warmExePath: String?
    @ObservationIgnored private var warmPermissionMode: InteractionMode?

    // Cached base environment (built once, reused)
    @ObservationIgnored private var cachedBaseEnv: [String: String]?
    // Provider env for the current/warm process
    @ObservationIgnored private var warmProviderEnv: [String: String]?
    @ObservationIgnored private var warmProviderUnsetEnv: [String]?

    /// CLI protocol adapter — encapsulates format-specific args, encoding, and parsing.
    @ObservationIgnored var adapter: CLIProtocolAdapter = StreamJSONAdapter()

    var sessionId: String?
    var isRunning: Bool = false

    /// Callback for parsed events — called on main thread.
    @ObservationIgnored var onEvent: ((ClaudeEvent) -> Void)?

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

    /// Build the base environment (without provider overrides). Cached.
    private func baseEnv() -> [String: String] {
        if let cached = cachedBaseEnv { return cached }
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
        cachedBaseEnv = env
        return env
    }

    /// Build environment with provider-specific overrides merged in.
    private func resolveEnv(
        providerEnv: [String: String] = [:],
        providerUnsetEnv: [String] = []
    ) -> [String: String] {
        var env = baseEnv()
        for key in providerUnsetEnv {
            env.removeValue(forKey: key)
        }
        for (key, value) in providerEnv {
            env[key] = value
        }
        return env
    }

    /// Build CLI arguments (without prompt).
    /// Uses --permission-mode exclusively to avoid --dangerously-skip-permissions
    /// overriding plan mode.
    private func buildArgs(permissionMode: InteractionMode = .normal) -> [String] {
        var args = adapter.formatArguments()
        switch permissionMode {
        case .normal:
            args += ["--permission-mode", "bypassPermissions"]
        case .acceptEdits:
            args += ["--permission-mode", "acceptEdits"]
        case .plan:
            args += ["--permission-mode", "plan"]
        }
        if let sid = sessionId {
            args += ["--resume", sid]
        }
        return args
    }

    // MARK: - Pre-warm

    /// Start a process ahead of time without a prompt.
    /// The process initializes (Node.js startup, config loading, MCP connections)
    /// and waits for stdin input. When send() is called, the prompt is piped in.
    func prewarm(
        cwd: String,
        executablePath: String? = nil,
        providerEnv: [String: String] = [:],
        providerUnsetEnv: [String] = [],
        permissionMode: InteractionMode = .normal
    ) {
        // Don't pre-warm if one is already running or cwd is empty
        guard warmProcess == nil, !cwd.isEmpty else { return }

        let exe = executablePath ?? Self.findClaudeBinary()
        let env = resolveEnv(providerEnv: providerEnv, providerUnsetEnv: providerUnsetEnv)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = buildArgs(permissionMode: permissionMode)
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
            warmPermissionMode = permissionMode
            debugLog("prewarm: started (exe=\(exe) cwd=\(cwd) mode=\(permissionMode) sid=\(sessionId ?? "nil"))")
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

    func send(
        prompt: String,
        cwd: String,
        executablePath: String? = nil,
        providerEnv: [String: String] = [:],
        providerUnsetEnv: [String] = [],
        permissionMode: InteractionMode = .normal
    ) {
        guard !isRunning else {
            debugLog("send() blocked — isRunning=true")
            return
        }
        isRunning = true
        lineBuffer = ""
        resultReceived = false

        let exe = executablePath ?? Self.findClaudeBinary()

        // Try to use a pre-warmed process (must match cwd, exe, AND permission mode)
        if let warm = warmProcess, warm.isRunning,
           warmCwd == cwd, warmExePath == exe, warmPermissionMode == permissionMode {
            debugLog("send() using pre-warmed process")
            adoptWarmProcess(prompt: prompt)
        } else {
            // Discard stale pre-warm if any
            discardPrewarm()
            debugLog("send() creating new process (exe=\(exe) cwd=\(cwd) mode=\(permissionMode) sid=\(sessionId ?? "nil"))")
            launchNewProcess(prompt: prompt, cwd: cwd, exe: exe, providerEnv: providerEnv, providerUnsetEnv: providerUnsetEnv, permissionMode: permissionMode)
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
                guard let self, self.process === p else { return }
                self.activeStdinHandle = nil
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
                        cacheReadTokens: 0, cacheCreationTokens: 0,
                        contextUsedPercent: nil, contextWindowSize: nil
                    )))
                }
            }
        }

        // Write user message as JSON line — keep stdin open for interactive responses
        if let handle = warmStdinPipe?.fileHandleForWriting {
            handle.write(adapter.encodeUserMessage(prompt))
            activeStdinHandle = handle
        }

        warmStdinPipe = nil
        warmStdoutPipe = nil
        warmStderrPipe = nil
        warmCwd = nil
        warmExePath = nil
        warmPermissionMode = nil
    }

    /// Launch a brand new process and send the prompt via stdin JSON.
    private func launchNewProcess(
        prompt: String,
        cwd: String,
        exe: String,
        providerEnv: [String: String] = [:],
        providerUnsetEnv: [String] = [],
        permissionMode: InteractionMode = .normal
    ) {
        let env = resolveEnv(providerEnv: providerEnv, providerUnsetEnv: providerUnsetEnv)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = buildArgs(permissionMode: permissionMode)
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        proc.environment = env
        debugLog("launchNewProcess (exe=\(exe) cwd=\(cwd) sid=\(sessionId ?? "nil"))")

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
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
                guard let self, self.process === p else { return }
                self.activeStdinHandle = nil
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
                        cacheReadTokens: 0, cacheCreationTokens: 0,
                        contextUsedPercent: nil, contextWindowSize: nil
                    )))
                }
            }
        }

        self.process = proc

        do {
            try proc.run()
            // Send prompt via stdin as JSON — keep stdin open for interactive responses
            stdinPipe.fileHandleForWriting.write(adapter.encodeUserMessage(prompt))
            activeStdinHandle = stdinPipe.fileHandleForWriting
        } catch {
            isRunning = false
            let errorEvent = ClaudeEvent.result(ResultInfo(
                sessionId: "",
                result: "Failed to launch: \(error.localizedDescription)\nPath: \(exe)",
                isError: true,
                costUSD: 0, durationMs: 0,
                inputTokens: 0, outputTokens: 0,
                cacheReadTokens: 0, cacheCreationTokens: 0,
                contextUsedPercent: nil, contextWindowSize: nil
            ))
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(errorEvent)
            }
        }
    }

    /// Write data to the active stdin (for interactive tool responses).
    func writeToStdin(_ data: Data) {
        guard let handle = activeStdinHandle else {
            debugLog("writeToStdin: no active stdin handle")
            return
        }
        handle.write(data)
        debugLog("writeToStdin: wrote \(data.count) bytes")
    }

    func stop() {
        activeStdinHandle?.closeFile()
        activeStdinHandle = nil
        let old = process
        process = nil
        isRunning = false
        old?.terminate()
    }

    // MARK: - Line buffering

    private func processChunk(_ chunk: String) {
        parseQueue.async { [weak self] in
            self?._processChunkSync(chunk)
        }
    }

    /// Must only be called on parseQueue.
    private func _processChunkSync(_ chunk: String) {
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
            if !line.isEmpty, let event = adapter.parseLine(line) {
                // Capture session ID from init
                if case .systemInit(let info) = event {
                    DispatchQueue.main.async { [weak self] in
                        self?.sessionId = info.sessionId
                    }
                }
                if case .result = event {
                    resultReceived = true
                    // Reset isRunning BEFORE delivering the event, so that
                    // sendNextPending() → startRequest() → send() sees isRunning=false.
                    DispatchQueue.main.async { [weak self] in
                        self?.isRunning = false
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    self?.onEvent?(event)
                }
            }
        }
    }
}
