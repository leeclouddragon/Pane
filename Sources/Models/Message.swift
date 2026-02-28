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
    /// Elapsed seconds for this assistant response (nil while streaming or for user messages).
    var durationSeconds: Int?

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

    /// Lightweight check on raw text — no ANSI stripping needed.
    var isContextUsage: Bool {
        text.contains("Context Usage")
    }

    /// Parse all context usage data in a single pass. Call once, use the result.
    func parseContextUsage() -> ParsedContextUsage {
        ParsedContextUsage.parse(text)
    }
}

/// Pre-parsed context usage data. Avoids repeated ANSI stripping + regex on every property access.
struct ParsedContextUsage {
    let model: String?
    let tokenInfo: TokenInfo?
    let categories: [(name: String, tokens: String, percentage: String)]
    let sections: [(header: String, items: [(name: String, detail: String)])]

    struct TokenInfo {
        let used: String
        let total: String
        let percentage: Double
    }

    static func parse(_ rawText: String) -> ParsedContextUsage {
        let clean = rawText.replacingOccurrences(of: #"\u{1B}\[[0-9;]*m"#, with: "", options: .regularExpression)
        let lines = clean.components(separatedBy: "\n")

        return ParsedContextUsage(
            model: parseModel(lines),
            tokenInfo: parseTokenInfo(lines),
            categories: parseCategories(lines, fullText: clean),
            sections: parseSections(lines)
        )
    }

    // MARK: - Private parsers (all work from shared lines array)

    private static func parseModel(_ lines: [String]) -> String? {
        if let line = lines.first(where: { $0.contains("·") && $0.contains("tokens") }) {
            return line.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces)
        }
        if let line = lines.first(where: { $0.contains("**Model:**") }) {
            return line.replacingOccurrences(of: "**Model:**", with: "").trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parseTokenInfo(_ lines: [String]) -> TokenInfo? {
        for line in lines {
            if let range = line.range(of: #"(\d+\.?\d*k?)\s*/\s*(\d+\.?\d*k?)\s*tokens"#, options: .regularExpression) {
                let match = String(line[range])
                let parts = match.replacingOccurrences(of: "tokens", with: "").components(separatedBy: "/")
                guard parts.count >= 2 else { continue }
                let used = parts[0].trimmingCharacters(in: .whitespaces)
                let total = parts[1].trimmingCharacters(in: .whitespaces)
                if let pctLine = lines.first(where: { $0.contains("%") }),
                   let pctRange = pctLine.range(of: #"(\d+)%"#, options: .regularExpression) {
                    let pct = Double(pctLine[pctRange].filter(\.isNumber)) ?? 0
                    return TokenInfo(used: used, total: total, percentage: pct)
                }
                return TokenInfo(used: used, total: total, percentage: 0)
            }
            if line.contains("**Tokens") {
                let cleaned = line.replacingOccurrences(of: #"\*\*Tokens?:\*\*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                let parts = cleaned.components(separatedBy: "/")
                guard parts.count >= 2 else { continue }
                let used = parts[0].trimmingCharacters(in: .whitespaces)
                let rest = parts[1].trimmingCharacters(in: .whitespaces)
                if let pctRange = rest.range(of: #"(\d+)%"#, options: .regularExpression) {
                    let total = String(rest[rest.startIndex..<pctRange.lowerBound])
                        .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "()")))
                    let pct = Double(rest[pctRange].filter(\.isNumber)) ?? 0
                    return TokenInfo(used: used, total: total, percentage: pct)
                }
            }
        }
        return nil
    }

    private static func parseCategories(_ lines: [String], fullText: String) -> [(name: String, tokens: String, percentage: String)] {
        var rows: [(String, String, String)] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: #"[⛁⛀⛶⛝]\s+(.+?):\s+(.+?)\s+\((.+?)\)"#, options: .regularExpression) {
                let match = String(trimmed[range])
                let noMarker = String(match.dropFirst()).trimmingCharacters(in: .whitespaces)
                let colonParts = noMarker.components(separatedBy: ":")
                guard colonParts.count >= 2 else { continue }
                let name = colonParts[0].trimmingCharacters(in: .whitespaces)
                let rest = colonParts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                if let pctRange = rest.range(of: #"\((.+?)\)"#, options: .regularExpression) {
                    let tokens = String(rest[rest.startIndex..<pctRange.lowerBound])
                        .replacingOccurrences(of: "tokens", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    let pct = String(rest[pctRange]).filter { $0.isNumber || $0 == "." } + "%"
                    rows.append((name, tokens, pct))
                }
            }
        }
        if rows.isEmpty {
            rows = parseMarkdownTable(lines: lines, after: "usage by category")
        }
        return rows
    }

    private static func parseSections(_ lines: [String]) -> [(header: String, items: [(name: String, detail: String)])] {
        let sectionMarkers = ["MCP tools", "Custom agents", "Memory files", "Skills"]
        var sections: [(String, [(String, String)])] = []

        for marker in sectionMarkers {
            guard let startIdx = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix(marker.lowercased())
            }) else { continue }

            var items: [(String, String)] = []
            for i in (startIdx + 1)..<lines.count {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                if sectionMarkers.contains(where: { line.lowercased().hasPrefix($0.lowercased()) }) { break }
                if line.hasPrefix("└") {
                    let content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                    if let colonRange = content.range(of: ": ") {
                        items.append((String(content[content.startIndex..<colonRange.lowerBound]),
                                      String(content[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)))
                    } else {
                        items.append((content, ""))
                    }
                }
                if line.hasPrefix("|") && !line.contains("---") {
                    let cols = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    if cols.count >= 2 {
                        if cols[0].lowercased() == "tool" || cols[0].lowercased() == "category" { continue }
                        let detail = cols.count >= 3 ? "\(cols[1]) · \(cols[2])" : cols[1]
                        items.append((cols[0], detail))
                    }
                }
            }
            if !items.isEmpty { sections.append((marker, items)) }
        }
        return sections
    }

    private static func parseMarkdownTable(lines: [String], after marker: String) -> [(name: String, tokens: String, percentage: String)] {
        guard let headerIdx = lines.firstIndex(where: { $0.lowercased().contains(marker.lowercased()) }) else { return [] }
        var tableStart = headerIdx + 1
        while tableStart < lines.count && !lines[tableStart].hasPrefix("|") { tableStart += 1 }
        guard tableStart < lines.count else { return [] }

        var dataStart = tableStart + 1
        if dataStart < lines.count && lines[dataStart].contains("---") { dataStart += 1 }

        var rows: [(String, String, String)] = []
        for i in dataStart..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else { break }
            let cols = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if cols.count >= 3 { rows.append((cols[0], cols[1], cols[2])) }
            else if cols.count == 2 { rows.append((cols[0], cols[1], "")) }
        }
        return rows
    }
}
