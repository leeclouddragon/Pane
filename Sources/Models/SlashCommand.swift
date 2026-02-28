import Foundation

enum SlashCommandType {
    case cli    // Sent to CLI via stream-json
    case local  // Handled locally by Pane
}

/// Action performed by a local slash command.
enum LocalAction {
    case clear
}

struct SlashCommand: Identifiable {
    let id: String
    let icon: String
    let name: String
    let description: String
    let type: SlashCommandType
    let localAction: LocalAction?

    var command: String { "/\(id)" }

    init(id: String, icon: String, name: String, description: String,
         type: SlashCommandType = .cli, localAction: LocalAction? = nil) {
        self.id = id
        self.icon = icon
        self.name = name
        self.description = description
        self.type = type
        self.localAction = localAction
    }
}

extension SlashCommand {
    static let all: [SlashCommand] = [
        // ── Local (handled by Pane) ──
        SlashCommand(id: "clear", icon: "trash",
                     name: "Clear", description: "Clear conversation history",
                     type: .local, localAction: .clear),

        // ── CLI local (supportsNonInteractive) ──
        SlashCommand(id: "compact", icon: "arrow.triangle.2.circlepath",
                     name: "Compact", description: "Clear history but keep a summary in context"),
        SlashCommand(id: "context", icon: "chart.bar.fill",
                     name: "Context", description: "Visualize current context usage"),
        SlashCommand(id: "cost", icon: "dollarsign.circle",
                     name: "Cost", description: "Show total cost and duration of current session"),

        // ── CLI prompt (triggers LLM) ──
        SlashCommand(id: "commit", icon: "checkmark.circle",
                     name: "Commit", description: "Generate a git commit for pending changes"),
        SlashCommand(id: "init", icon: "doc.badge.plus",
                     name: "Init", description: "Initialize a new CLAUDE.md file"),
        SlashCommand(id: "pr-comments", icon: "text.bubble",
                     name: "PR comments", description: "Get comments from a GitHub pull request"),
        SlashCommand(id: "review", icon: "eye",
                     name: "Review", description: "Review a pull request"),
        SlashCommand(id: "security-review", icon: "shield.lefthalf.filled",
                     name: "Security review", description: "Security review of pending changes"),
        SlashCommand(id: "simplify", icon: "scissors",
                     name: "Simplify", description: "Review changed code for reuse, quality, efficiency"),
        SlashCommand(id: "debug", icon: "ant",
                     name: "Debug", description: "Systematic debugging of an issue"),
    ]

    static func filtered(by query: String) -> [SlashCommand] {
        if query.isEmpty { return all }
        let q = query.lowercased()
        return all.filter {
            $0.id.lowercased().contains(q)
            || $0.name.lowercased().contains(q)
            || $0.description.lowercased().contains(q)
        }
    }
}
