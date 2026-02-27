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

    var id: UUID {
        switch self {
        case .text(let c): c.id
        case .code(let c): c.id
        case .toolCall(let c): c.id
        case .toolResult(let c): c.id
        case .thinking(let c): c.id
        case .progress(let c): c.id
        case .error(let c): c.id
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
    var tool: String       // Read, Edit, Bash, Grep, Glob, Write...
    var summary: String    // short description
    var detail: String     // full output
    var isExpanded: Bool = false
}

struct ToolResultContent: Identifiable {
    let id = UUID()
    var output: String
    var isError: Bool = false
}

struct ThinkingContent: Identifiable {
    let id = UUID()
    var text: String
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
