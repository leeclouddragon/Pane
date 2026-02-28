import Foundation

struct SlashCommand: Identifiable {
    let id: String           // command name without /
    let icon: String         // SF Symbol name
    let name: String         // Display name
    let description: String  // Short description

    /// The string sent to Claude Code CLI (e.g. "/compact").
    var command: String { "/\(id)" }
}

extension SlashCommand {
    /// All commands from Claude Code CLI 2.1.63 (non-hidden, isEnabled: true).
    static let all: [SlashCommand] = [
        SlashCommand(id: "add-dir", icon: "folder.badge.plus",
                     name: "Add dir", description: "Add a new working directory"),
        SlashCommand(id: "agents", icon: "person.3",
                     name: "Agents", description: "Manage agent configurations"),
        SlashCommand(id: "bashes", icon: "terminal",
                     name: "Bashes", description: "List and manage background tasks"),
        SlashCommand(id: "clear", icon: "trash",
                     name: "Clear", description: "Clear conversation history and free up context"),
        SlashCommand(id: "compact", icon: "arrow.triangle.2.circlepath",
                     name: "Compact", description: "Clear history but keep a summary in context"),
        SlashCommand(id: "config", icon: "gearshape",
                     name: "Config", description: "Open config panel"),
        SlashCommand(id: "context", icon: "chart.bar.fill",
                     name: "Context", description: "Visualize current context usage as a colored grid"),
        SlashCommand(id: "cost", icon: "dollarsign.circle",
                     name: "Cost", description: "Show total cost and duration of current session"),
        SlashCommand(id: "doctor", icon: "stethoscope",
                     name: "Doctor", description: "Diagnose and verify installation and settings"),
        SlashCommand(id: "export", icon: "square.and.arrow.up",
                     name: "Export", description: "Export the current conversation to a file or clipboard"),
        SlashCommand(id: "feedback", icon: "envelope",
                     name: "Feedback", description: "Submit feedback about Claude Code"),
        SlashCommand(id: "help", icon: "questionmark.circle",
                     name: "Help", description: "Show help and available commands"),
        SlashCommand(id: "hooks", icon: "link",
                     name: "Hooks", description: "Manage hook configurations for tool events"),
        SlashCommand(id: "ide", icon: "laptopcomputer",
                     name: "IDE", description: "Manage IDE integrations and show status"),
        SlashCommand(id: "init", icon: "doc.badge.plus",
                     name: "Init", description: "Initialize a new CLAUDE.md file"),
        SlashCommand(id: "login", icon: "person.crop.circle.badge.checkmark",
                     name: "Login", description: "Switch Anthropic accounts"),
        SlashCommand(id: "logout", icon: "person.crop.circle.badge.xmark",
                     name: "Logout", description: "Sign out from your Anthropic account"),
        SlashCommand(id: "mcp", icon: "server.rack",
                     name: "MCP", description: "Manage MCP servers"),
        SlashCommand(id: "memory", icon: "brain",
                     name: "Memory", description: "Edit Claude memory files"),
        SlashCommand(id: "model", icon: "cpu",
                     name: "Model", description: "Switch AI model"),
        SlashCommand(id: "permissions", icon: "lock.shield",
                     name: "Permissions", description: "View or update permissions"),
        SlashCommand(id: "pr-comments", icon: "text.bubble",
                     name: "PR comments", description: "Get comments from a GitHub pull request"),
        SlashCommand(id: "resume", icon: "arrow.uturn.backward",
                     name: "Resume", description: "Resume a conversation"),
        SlashCommand(id: "review", icon: "eye",
                     name: "Review", description: "Review a pull request"),
        SlashCommand(id: "security-review", icon: "shield.lefthalf.filled",
                     name: "Security review", description: "Security review of pending changes on current branch"),
        SlashCommand(id: "status", icon: "info.circle",
                     name: "Status", description: "Show version, model, account, and tool statuses"),
        SlashCommand(id: "stickers", icon: "star",
                     name: "Stickers", description: "Order Claude Code stickers"),
        SlashCommand(id: "terminal-setup", icon: "terminal",
                     name: "Terminal setup", description: "Install Shift+Enter key binding for terminal"),
        SlashCommand(id: "todos", icon: "checklist",
                     name: "Todos", description: "List current todo items"),
        SlashCommand(id: "usage", icon: "chart.pie",
                     name: "Usage", description: "Show plan usage limits"),
        SlashCommand(id: "vim", icon: "keyboard",
                     name: "Vim", description: "Toggle between Vim and Normal editing modes"),
    ]

    /// Filter commands by query (matches id, name or description, case-insensitive).
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
