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
    func discover() {
        let binDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("bin")
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: binDir.path) else { return }

        let skip = Set(["clother-use", "clother-vscode"])

        providers = contents
            .filter { $0.hasPrefix("clother-") && !skip.contains($0) }
            .sorted()
            .compactMap { name -> ClotherProvider? in
                let path = binDir.appendingPathComponent(name).path
                guard fm.isExecutableFile(atPath: path) else { return nil }
                let id = String(name.dropFirst("clother-".count))
                return ClotherProvider(id: id, scriptPath: path)
            }
    }
}
