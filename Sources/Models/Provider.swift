import Foundation

/// A clother provider discovered from ~/bin/clother-* scripts.
struct ClotherProvider: Identifiable, Hashable {
    let id: String          // e.g. "bedrock", "kimi"
    let scriptPath: String  // e.g. "/Users/.../bin/clother-bedrock"

    var displayName: String {
        id.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

@Observable
final class ProviderState {
    var providers: [ClotherProvider] = []
    var activeProviderID: String = ""

    var active: ClotherProvider? {
        providers.first { $0.id == activeProviderID }
    }

    /// The executable path for the active provider (or fallback to claude).
    var executablePath: String {
        active?.scriptPath ?? ClaudeProcessManager.findClaudeBinary()
    }

    init() {
        discover()
        // Default to bedrock if available, otherwise first found
        if let bedrock = providers.first(where: { $0.id == "bedrock" }) {
            activeProviderID = bedrock.id
        } else if let first = providers.first {
            activeProviderID = first.id
        }
    }

    /// Scan ~/bin/clother-* for available provider scripts.
    /// Only includes providers whose required API keys are configured.
    func discover() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binDir = home.appendingPathComponent("bin")
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: binDir.path) else { return }

        let skip = Set(["clother-use", "clother-vscode"])
        let configuredKeys = loadConfiguredKeys()

        providers = contents
            .filter { $0.hasPrefix("clother-") && !skip.contains($0) }
            .sorted()
            .compactMap { name -> ClotherProvider? in
                let path = binDir.appendingPathComponent(name).path
                guard fm.isExecutableFile(atPath: path) else { return nil }
                let id = String(name.dropFirst("clother-".count))

                // Check if the script's required API key is configured
                guard isProviderConfigured(scriptPath: path, configuredKeys: configuredKeys) else {
                    return nil
                }

                return ClotherProvider(id: id, scriptPath: path)
            }
    }

    /// Read secrets.env and return set of key names that have real values.
    private func loadConfiguredKeys() -> Set<String> {
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

                // Skip placeholder values
                if !value.isEmpty && !value.hasPrefix("REPLACE_") {
                    keys.insert(key)
                }
            }
        }
        return keys
    }

    /// Check if a clother script's required API key is available.
    /// Scripts without API key checks (bedrock, native, local) are always valid.
    private func isProviderConfigured(scriptPath: String, configuredKeys: Set<String>) -> Bool {
        guard let content = try? String(contentsOfFile: scriptPath, encoding: .utf8) else {
            return false
        }

        // Find required API key: pattern like [[ -z "${SOME_API_KEY:-}" ]]
        // or $SOME_API_KEY in the script
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            // Match the key-check pattern: -z "${KEY:-}"
            if line.contains("_API_KEY") && line.contains("-z") {
                // Extract the key name
                if let range = line.range(of: #"\$\{(\w+_API_KEY)"#, options: .regularExpression) {
                    let match = String(line[range])
                    let keyName = match
                        .replacingOccurrences(of: "${", with: "")
                        .replacingOccurrences(of: "}", with: "")
                    return configuredKeys.contains(keyName)
                }
            }
        }

        // No API key check found — check if it's a local provider (localhost URL)
        for line in lines {
            if let range = line.range(of: #"localhost:(\d+)"#, options: .regularExpression) {
                let portStr = String(line[range]).components(separatedBy: ":").last ?? ""
                if let port = UInt16(portStr) {
                    return isPortOpen(port: port)
                }
            }
        }

        // No API key, no localhost — always available (bedrock, native)
        return true
    }

    /// Quick TCP port check — returns true if something is listening.
    private func isPortOpen(port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }

        // Set short connect timeout
        var tv = timeval(tv_sec: 0, tv_usec: 300_000) // 300ms
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
