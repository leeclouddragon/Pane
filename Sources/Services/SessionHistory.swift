import Foundation

struct SessionEntry: Identifiable {
    let id: String        // session UUID
    let filePath: String
    let project: String   // decoded project path
    let cwd: String
    let firstMessage: String
    let modifiedDate: Date
}

/// Scans ~/.claude/projects/ for session JSONL files and extracts metadata.
struct SessionHistory {

    static func scan(limit: Int = 20) -> [SessionEntry] {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: claudeDir.path) else { return [] }

        var entries: [SessionEntry] = []

        for projName in projectDirs {
            let projPath = claudeDir.appendingPathComponent(projName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projPath.path, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let files = try? fm.contentsOfDirectory(atPath: projPath.path) else { continue }

            for file in files {
                // Only top-level .jsonl files (UUID format), skip subagents/
                guard file.hasSuffix(".jsonl"),
                      file.count > 10,
                      !file.hasPrefix("agent-")
                else { continue }

                let filePath = projPath.appendingPathComponent(file).path

                guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                      let modDate = attrs[.modificationDate] as? Date
                else { continue }

                let sessionId = String(file.dropLast(6)) // remove .jsonl
                let project = decodeProjectName(projName)

                entries.append(SessionEntry(
                    id: sessionId,
                    filePath: filePath,
                    project: project,
                    cwd: "",
                    firstMessage: "",
                    modifiedDate: modDate
                ))
            }
        }

        // Sort by most recent, take top N
        entries.sort { $0.modifiedDate > $1.modifiedDate }
        let top = Array(entries.prefix(limit * 3))

        // Enrich with first user message, filter out empty sessions, then limit
        let enriched = top.compactMap { entry -> SessionEntry? in
            let e = enrichEntry(entry)
            return e.firstMessage == entry.id ? nil : e
        }
        return Array(enriched.prefix(limit))
    }

    private static func enrichEntry(_ entry: SessionEntry) -> SessionEntry {
        guard let handle = FileHandle(forReadingAtPath: entry.filePath) else { return entry }
        defer { handle.closeFile() }

        // Read first ~128KB to find first user message (some files have many snapshots first)
        let data = handle.readData(ofLength: 131072)
        guard let text = String(data: data, encoding: .utf8) else { return entry }

        var cwd = ""
        var firstMsg = ""

        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let type = json["type"] as? String ?? ""
            if type == "user" {
                cwd = json["cwd"] as? String ?? ""

                if let message = json["message"] as? [String: Any] {
                    let content = message["content"]
                    if let text = content as? String {
                        // content is a plain string
                        firstMsg = String(text.prefix(80))
                    } else if let blocks = content as? [[String: Any]] {
                        // content is an array of blocks
                        for block in blocks {
                            if block["type"] as? String == "text",
                               let t = block["text"] as? String {
                                firstMsg = String(t.prefix(80))
                                break
                            }
                        }
                    }
                }
                break
            }
        }

        return SessionEntry(
            id: entry.id,
            filePath: entry.filePath,
            project: entry.project,
            cwd: cwd.isEmpty ? entry.project : cwd,
            firstMessage: firstMsg.isEmpty ? entry.id : firstMsg,
            modifiedDate: entry.modifiedDate
        )
    }

    // MARK: - Load conversation messages from JSONL

    struct LoadResult {
        let messages: [Message]
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
    }

    static func loadMessages(from filePath: String) -> LoadResult {
        guard let data = FileManager.default.contents(atPath: filePath),
              let text = String(data: data, encoding: .utf8)
        else { return LoadResult(messages: [], model: "", inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0) }

        var messages: [Message] = []
        var model = ""
        var totalInput = 0
        var totalOutput = 0
        var totalCacheRead = 0
        var totalCacheCreation = 0

        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let type = json["type"] as? String ?? ""

            if type == "user" {
                if let msg = parseUserMessage(json) {
                    messages.append(msg)
                }
            } else if type == "assistant" {
                // Extract usage data
                if let message = json["message"] as? [String: Any] {
                    if model.isEmpty, let m = message["model"] as? String {
                        model = m
                    }
                    if let usage = message["usage"] as? [String: Any] {
                        totalInput += usage["input_tokens"] as? Int ?? 0
                        totalOutput += usage["output_tokens"] as? Int ?? 0
                        totalCacheRead += usage["cache_read_input_tokens"] as? Int ?? 0
                        totalCacheCreation += usage["cache_creation_input_tokens"] as? Int ?? 0
                    }
                }

                if let msg = parseAssistantMessage(json) {
                    if let last = messages.last, last.role == .assistant {
                        var merged = last
                        merged.blocks.append(contentsOf: msg.blocks)
                        messages[messages.count - 1] = merged
                    } else {
                        messages.append(msg)
                    }
                }
            }
        }

        return LoadResult(
            messages: messages,
            model: model,
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cacheReadTokens: totalCacheRead,
            cacheCreationTokens: totalCacheCreation
        )
    }

    private static func parseUserMessage(_ json: [String: Any]) -> Message? {
        guard let message = json["message"] as? [String: Any] else { return nil }
        let content = message["content"]

        var text = ""
        if let s = content as? String {
            text = s
        } else if let blocks = content as? [[String: Any]] {
            text = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined()
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Message(role: .user, blocks: [.text(TextContent(text: text))])
    }

    private static func parseAssistantMessage(_ json: [String: Any]) -> Message? {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else { return nil }

        var blocks: [ContentBlock] = []

        for block in content {
            let blockType = block["type"] as? String ?? ""
            switch blockType {
            case "text":
                if let text = block["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(TextContent(text: text)))
                }
            case "tool_use":
                let name = block["name"] as? String ?? "tool"
                let id = block["id"] as? String ?? ""
                blocks.append(.toolCall(ToolCallContent(tool: name, summary: id, detail: "")))
            case "thinking":
                let text = block["thinking"] as? String ?? ""
                if !text.isEmpty {
                    blocks.append(.thinking(ThinkingContent(text: String(text.prefix(200)))))
                }
            default:
                break
            }
        }

        guard !blocks.isEmpty else { return nil }
        return Message(role: .assistant, blocks: blocks)
    }

    private static func decodeProjectName(_ name: String) -> String {
        // "-Users-liyunlong-codebase-nemo-mega" → "/Users/liyunlong/codebase/nemo-mega"
        if name == "-" { return "~" }
        var decoded = name.replacingOccurrences(of: "-", with: "/")
        if decoded.hasPrefix("/") {
            // Keep as-is
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if decoded.hasPrefix(home) {
            decoded = "~" + decoded.dropFirst(home.count)
        }
        return decoded
    }
}
