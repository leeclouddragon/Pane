import Foundation

// MARK: - Config file types

/// A provider entry in ~/.config/pane/config.json.
struct ProviderEntry: Codable, Identifiable, Hashable {
    let id: String
    var displayName: String
    var category: Category
    var env: [String: String]?
    var unsetEnv: [String]?
    var apiKey: String?
    var localPort: UInt16?

    enum Category: String, Codable, CaseIterable {
        case native, cloud, bedrock, local
    }
}

struct PaneConfig: Codable {
    var defaultProvider: String?
    var providers: [ProviderEntry]
}

// MARK: - Config manager

final class PaneConfigManager {
    static let configDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/pane")
    }()

    static let configFile: URL = {
        configDir.appendingPathComponent("config.json")
    }()

    func load() -> PaneConfig {
        ensureDefaults()
        guard let data = try? Data(contentsOf: Self.configFile),
              let config = try? JSONDecoder().decode(PaneConfig.self, from: data)
        else {
            return PaneConfig(defaultProvider: "native", providers: Self.defaultProviders)
        }
        return config
    }

    func save(_ config: PaneConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(at: Self.configDir, withIntermediateDirectories: true)
        try? data.write(to: Self.configFile, options: .atomic)
    }

    /// Create default config if none exists.
    func ensureDefaults() {
        guard !FileManager.default.fileExists(atPath: Self.configFile.path) else { return }
        let config = PaneConfig(defaultProvider: nil, providers: Self.defaultProviders)
        save(config)
    }

    // MARK: - Default provider definitions

    static let defaultProviders: [ProviderEntry] = [
        ProviderEntry(
            id: "native",
            displayName: "Claude (Native)",
            category: .native
        ),
        ProviderEntry(
            id: "bedrock",
            displayName: "AWS Bedrock",
            category: .bedrock,
            env: [
                "CLAUDE_CODE_USE_BEDROCK": "1",
                "ANTHROPIC_MODEL": "global.anthropic.claude-opus-4-6-v1",
                "CLAUDE_MODEL_ID": "global.anthropic.claude-opus-4-6-v1",
                "AWS_PROFILE": "nemovideo",
                "AWS_REGION": "us-east-1",
            ]
        ),
        ProviderEntry(
            id: "kimi",
            displayName: "Kimi",
            category: .cloud,
            env: [
                "ANTHROPIC_BASE_URL": "https://api.kimi.com/coding/",
                "ANTHROPIC_MODEL": "kimi-k2.5",
                "ANTHROPIC_SMALL_FAST_MODEL": "kimi-k2.5",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"]
        ),
        ProviderEntry(
            id: "moonshot",
            displayName: "Moonshot",
            category: .cloud,
            env: [
                "ANTHROPIC_BASE_URL": "https://api.moonshot.cn/anthropic",
                "ANTHROPIC_MODEL": "kimi-k2.5",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"]
        ),
        ProviderEntry(
            id: "deepseek",
            displayName: "DeepSeek",
            category: .cloud,
            env: [
                "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
                "ANTHROPIC_MODEL": "deepseek-chat",
                "ANTHROPIC_SMALL_FAST_MODEL": "deepseek-chat",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"]
        ),
        ProviderEntry(
            id: "zai",
            displayName: "GLM-5",
            category: .cloud,
            env: [
                "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
                "ANTHROPIC_MODEL": "glm-5",
                "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-5",
                "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5",
                "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"]
        ),
        ProviderEntry(
            id: "zai-cn",
            displayName: "GLM-5 CN",
            category: .cloud,
            env: [
                "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic",
                "ANTHROPIC_MODEL": "glm-5",
                "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-5",
                "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5",
                "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"]
        ),
        ProviderEntry(
            id: "minimax",
            displayName: "MiniMax",
            category: .cloud,
            env: [
                "ANTHROPIC_BASE_URL": "https://api.minimax.io/anthropic",
                "ANTHROPIC_MODEL": "MiniMax-M2.5",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"]
        ),
        ProviderEntry(
            id: "minimax-cn",
            displayName: "MiniMax CN",
            category: .cloud,
            env: [
                "ANTHROPIC_BASE_URL": "https://api.minimaxi.com/anthropic",
                "ANTHROPIC_MODEL": "MiniMax-M2.5",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"]
        ),
        ProviderEntry(
            id: "mimo",
            displayName: "MiMo",
            category: .cloud,
            env: [
                "ANTHROPIC_BASE_URL": "https://api.xiaomimimo.com/anthropic",
                "ANTHROPIC_MODEL": "mimo-v2-flash",
                "ANTHROPIC_DEFAULT_HAIKU_MODEL": "mimo-v2-flash",
                "ANTHROPIC_DEFAULT_SONNET_MODEL": "mimo-v2-flash",
                "ANTHROPIC_DEFAULT_OPUS_MODEL": "mimo-v2-flash",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"]
        ),
        ProviderEntry(
            id: "ve",
            displayName: "Doubao",
            category: .cloud,
            env: [
                "ANTHROPIC_BASE_URL": "https://ark.cn-beijing.volces.com/api/coding",
                "ANTHROPIC_MODEL": "doubao-seed-code-preview-latest",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"]
        ),
        ProviderEntry(
            id: "ollama",
            displayName: "Ollama",
            category: .local,
            env: [
                "ANTHROPIC_BASE_URL": "http://localhost:11434",
                "ANTHROPIC_AUTH_TOKEN": "ollama",
                "ANTHROPIC_API_KEY": "",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"],
            localPort: 11434
        ),
        ProviderEntry(
            id: "lmstudio",
            displayName: "LM Studio",
            category: .local,
            env: [
                "ANTHROPIC_BASE_URL": "http://localhost:1234",
                "ANTHROPIC_AUTH_TOKEN": "lmstudio",
                "ANTHROPIC_API_KEY": "",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"],
            localPort: 1234
        ),
        ProviderEntry(
            id: "llamacpp",
            displayName: "Llama.cpp",
            category: .local,
            env: [
                "ANTHROPIC_BASE_URL": "http://localhost:8000",
            ],
            unsetEnv: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"],
            localPort: 8000
        ),
    ]
}

// MARK: - Legacy clother support

/// A clother provider discovered from ~/bin/clother-* scripts.
struct ClotherProvider: Identifiable, Hashable {
    let id: String
    let scriptPath: String

    var displayName: String {
        id.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

// MARK: - Provider state

/// Launch configuration for a provider.
struct LaunchConfig {
    let executablePath: String
    let env: [String: String]
    let unsetEnv: [String]
}

@Observable
final class ProviderState {
    /// Available (configured) providers — shown in the provider menu.
    var providers: [ProviderEntry] = []
    /// All providers from config — shown in Settings.
    var allProviders: [ProviderEntry] = []
    var activeProviderID: String = ""

    /// Legacy clother providers (not in config file).
    private var clotherProviders: [ClotherProvider] = []

    let configManager = PaneConfigManager()

    var active: ProviderEntry? {
        providers.first { $0.id == activeProviderID }
    }

    init() {
        discover()
    }

    /// Reload config and refresh available provider list.
    func discover() {
        let config = configManager.load()
        allProviders = config.providers

        // Scan clother scripts first — used for availability fallback and launch
        clotherProviders = scanClotherScripts()
        let clotherIDs = Set(clotherProviders.map(\.id))

        // A config provider is available if:
        // 1. isAvailable() passes (has key, port open, etc.), OR
        // 2. A matching clother script exists (clother handles auth itself)
        var available = config.providers.filter { entry in
            isAvailable(entry) || clotherIDs.contains(entry.id)
        }

        // Add clother-only providers not in config
        let configIDs = Set(config.providers.map(\.id))
        for cp in clotherProviders where !configIDs.contains(cp.id) {
            available.append(ProviderEntry(
                id: cp.id,
                displayName: cp.displayName,
                category: .native
            ))
        }

        providers = available

        // Set default: explicit config > first non-native available > first available
        if let explicit = config.defaultProvider,
           providers.contains(where: { $0.id == explicit }) {
            activeProviderID = explicit
        } else {
            activeProviderID = providers.first(where: { $0.category != .native })?.id
                ?? providers.first?.id ?? ""
        }
    }

    /// Save updated API key back to config.
    func updateAPIKey(providerID: String, key: String) {
        var config = configManager.load()
        if let idx = config.providers.firstIndex(where: { $0.id == providerID }) {
            config.providers[idx].apiKey = key
        }
        configManager.save(config)
        discover()
    }

    /// Build LaunchConfig for a given provider entry.
    /// When `preferDirect` is true (non-normal modes: plan, acceptEdits), bypasses the
    /// clother script to avoid --dangerously-skip-permissions overriding --permission-mode.
    func launchConfig(for entry: ProviderEntry, preferDirect: Bool = false) -> LaunchConfig {
        // If a matching clother script exists AND config doesn't have its own key,
        // delegate to the clother script (it handles auth via secrets.env).
        // Skip clother when preferDirect is requested (plan mode needs direct launch).
        if !preferDirect, let cp = clotherProviders.first(where: { $0.id == entry.id }) {
            let hasConfigKey = entry.category == .cloud
                && !(entry.apiKey ?? "").isEmpty
            if !hasConfigKey {
                return LaunchConfig(
                    executablePath: cp.scriptPath,
                    env: [:],
                    unsetEnv: []
                )
            }
        }

        // Config-based provider: launch claude directly with env vars
        var env = entry.env ?? [:]
        if entry.category == .cloud, let key = entry.apiKey, !key.isEmpty {
            env["ANTHROPIC_AUTH_TOKEN"] = key
        }

        return LaunchConfig(
            executablePath: ClaudeProcessManager.findClaudeBinary(),
            env: env,
            unsetEnv: entry.unsetEnv ?? []
        )
    }

    // MARK: - Availability check

    func isAvailable(_ entry: ProviderEntry) -> Bool {
        switch entry.category {
        case .native:
            return true
        case .cloud:
            return !(entry.apiKey ?? "").isEmpty
        case .bedrock:
            return true
        case .local:
            guard let port = entry.localPort else { return true }
            return isPortOpen(port: port)
        }
    }

    // MARK: - Clother scanning

    /// Scan ~/bin/clother-* for available provider scripts.
    /// Only returns providers whose required API keys are configured in secrets.env
    /// or whose local ports are reachable.
    private func scanClotherScripts() -> [ClotherProvider] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binDir = home.appendingPathComponent("bin")
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: binDir.path) else { return [] }

        let skip = Set(["clother-use", "clother-vscode"])
        let configuredKeys = loadClotherConfiguredKeys()

        return contents
            .filter { $0.hasPrefix("clother-") && !skip.contains($0) }
            .sorted()
            .compactMap { name -> ClotherProvider? in
                let path = binDir.appendingPathComponent(name).path
                guard fm.isExecutableFile(atPath: path) else { return nil }
                guard isClotherScriptConfigured(scriptPath: path, configuredKeys: configuredKeys) else {
                    return nil
                }
                let id = String(name.dropFirst("clother-".count))
                return ClotherProvider(id: id, scriptPath: path)
            }
    }

    /// Read ~/.local/share/clother/secrets.env and return set of key names that have values.
    private func loadClotherConfiguredKeys() -> Set<String> {
        let secretsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/clother/secrets.env").path

        guard let content = try? String(contentsOfFile: secretsPath, encoding: .utf8) else {
            return []
        }

        var keys = Set<String>()
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[trimmed.startIndex..<eqIndex])
                let value = String(trimmed[trimmed.index(after: eqIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty && !value.hasPrefix("REPLACE_") {
                    keys.insert(key)
                }
            }
        }
        return keys
    }

    /// Check if a clother script's required API key exists, or if its local port is open.
    private func isClotherScriptConfigured(scriptPath: String, configuredKeys: Set<String>) -> Bool {
        guard let content = try? String(contentsOfFile: scriptPath, encoding: .utf8) else {
            return false
        }

        let lines = content.components(separatedBy: "\n")

        // Check for required API key: pattern like -z "${SOME_API_KEY:-}"
        for line in lines {
            if line.contains("_API_KEY") && line.contains("-z") {
                if let range = line.range(of: #"\$\{(\w+_API_KEY)"#, options: .regularExpression) {
                    let match = String(line[range])
                    let keyName = match
                        .replacingOccurrences(of: "${", with: "")
                        .replacingOccurrences(of: "}", with: "")
                    return configuredKeys.contains(keyName)
                }
            }
        }

        // Check for local provider (localhost URL)
        for line in lines {
            if let range = line.range(of: #"localhost:(\d+)"#, options: .regularExpression) {
                let portStr = String(line[range]).components(separatedBy: ":").last ?? ""
                if let port = UInt16(portStr) {
                    return isPortOpen(port: port)
                }
            }
        }

        // No API key check, no localhost — always available (bedrock, native)
        return true
    }

    // MARK: - Port check

    private func isPortOpen(port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }

        var tv = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
