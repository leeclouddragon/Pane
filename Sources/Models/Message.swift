import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct Message: Identifiable {
    let id: UUID
    let role: MessageRole
    var blocks: [ContentBlock]
    let timestamp: Date

    init(role: MessageRole, blocks: [ContentBlock] = []) {
        self.id = UUID()
        self.role = role
        self.blocks = blocks
        self.timestamp = Date()
    }
}

// MARK: - Content Blocks

enum ContentBlock: Identifiable {
    case text(TextContent)
    case code(CodeContent)
    case toolCall(ToolCallContent)
    case toolResult(ToolResultContent)
    case thinking(ThinkingContent)
    case progress(ProgressContent)
    case error(ErrorContent)
    case image(ImageContent)
    case systemResult(SystemResultContent)

    var id: UUID {
        switch self {
        case .text(let c): c.id
        case .code(let c): c.id
        case .toolCall(let c): c.id
        case .toolResult(let c): c.id
        case .thinking(let c): c.id
        case .progress(let c): c.id
        case .error(let c): c.id
        case .image(let c): c.id
        case .systemResult(let c): c.id
        }
    }
}

struct TextContent: Identifiable {
    let id = UUID()
    var text: String
}

struct CodeContent: Identifiable {
    let id = UUID()
    var code: String
    var language: String?
}

struct ToolCallContent: Identifiable {
    let id = UUID()
    var tool: String           // Read, Edit, Bash, Grep, Glob, Write...
    var toolUseId: String = "" // tool_use_id for matching results
    var summary: String        // extracted meaningful info (file path, command, etc.)
    var inputJson: String = "" // accumulated raw JSON input
    var detail: String         // tool result output
    var isError: Bool = false  // whether tool result was error
    var isExpanded: Bool = false
    var isRunning: Bool = true // still waiting for result

    /// Parse accumulated inputJson and extract a meaningful summary line.
    mutating func extractSummary() {
        guard let data = inputJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        switch tool.lowercased() {
        case "read":
            summary = obj["file_path"] as? String ?? summary
        case "edit":
            summary = obj["file_path"] as? String ?? summary
        case "write":
            summary = obj["file_path"] as? String ?? summary
        case "bash":
            if let cmd = obj["command"] as? String {
                let firstLine = cmd.components(separatedBy: "\n").first ?? cmd
                summary = String(firstLine.prefix(120))
            }
        case "grep":
            let pattern = obj["pattern"] as? String ?? ""
            let path = obj["path"] as? String
            summary = path != nil ? "\(pattern) in \(path!)" : pattern
        case "glob":
            summary = obj["pattern"] as? String ?? summary
        case "task":
            summary = obj["description"] as? String ?? summary
        default:
            // Try to show first string value
            if let first = obj.values.compactMap({ $0 as? String }).first {
                summary = String(first.prefix(80))
            }
        }
    }
}

struct ToolResultContent: Identifiable {
    let id = UUID()
    var output: String
    var isError: Bool = false
}

struct ThinkingContent: Identifiable {
    let id = UUID()
    var text: String
    var isComplete: Bool = false
    var startTime: Date = Date()
    var endTime: Date? = nil
    var isExpanded: Bool = false
}

struct ProgressContent: Identifiable {
    let id = UUID()
    var label: String
}

struct ErrorContent: Identifiable {
    let id = UUID()
    var message: String
}

struct ImageContent: Identifiable {
    let id = UUID()
    var url: URL
}

struct SystemResultContent: Identifiable {
    let id = UUID()
    var text: String

    /// Try to extract context usage percentage from text like "Xk/Yk tokens (Z%)"
    var contextPercentage: Double? {
        guard let range = text.range(of: #"\((\d+)%\)"#, options: .regularExpression) else { return nil }
        let match = text[range]
        let digits = match.filter(\.isNumber)
        return Double(digits)
    }

    /// Try to extract model name from first line containing "·"
    var modelLine: String? {
        text.components(separatedBy: "\n")
            .first { $0.contains("·") && $0.contains("tokens") }?
            .trimmingCharacters(in: .whitespaces)
    }
}
