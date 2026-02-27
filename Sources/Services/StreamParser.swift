import Foundation

/// Events parsed from Claude CLI's --output-format stream-json.
enum ClaudeEvent {
    case systemInit(SessionInfo)
    case textDelta(String)
    case contentBlockStart(index: Int, type: String)
    case contentBlockStop(index: Int)
    case toolUseStart(index: Int, id: String, name: String)
    case toolInputDelta(index: Int, json: String)
    case toolResult(toolUseId: String, content: String, isError: Bool)
    case assistantMessage(fullText: String, model: String)
    case result(ResultInfo)
    case messageStart
    case messageStop(stopReason: String?)
    case unknown(type: String, raw: String)
}

struct SessionInfo {
    let sessionId: String
    let model: String
    let cwd: String
    let tools: [String]
}

struct ResultInfo {
    let sessionId: String
    let result: String
    let isError: Bool
    let costUSD: Double
    let durationMs: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
}

/// Parses NDJSON lines from claude CLI stdout into ClaudeEvents.
struct StreamParser {
    static func parse(line: String) -> ClaudeEvent? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return nil }

        switch type {

        // system init
        case "system":
            let sessionId = json["session_id"] as? String ?? ""
            let model = json["model"] as? String ?? ""
            let cwd = json["cwd"] as? String ?? ""
            let tools = json["tools"] as? [String] ?? []
            return .systemInit(SessionInfo(sessionId: sessionId, model: model, cwd: cwd, tools: tools))

        // streaming events
        case "stream_event":
            return parseStreamEvent(json)

        // full assistant message (emitted after all content blocks)
        case "assistant":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                let fullText = content.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }.joined()
                let model = message["model"] as? String ?? ""
                return .assistantMessage(fullText: fullText, model: model)
            }
            return .unknown(type: type, raw: line)

        // final result
        case "result":
            let sessionId = json["session_id"] as? String ?? ""
            let result = json["result"] as? String ?? ""
            let isError = json["is_error"] as? Bool ?? false
            let costUSD = json["total_cost_usd"] as? Double ?? 0
            let durationMs = json["duration_ms"] as? Int ?? 0
            var inputTokens = 0
            var outputTokens = 0
            var cacheReadTokens = 0
            var cacheCreationTokens = 0
            if let usage = json["usage"] as? [String: Any] {
                inputTokens = usage["input_tokens"] as? Int ?? 0
                outputTokens = usage["output_tokens"] as? Int ?? 0
                cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0
                cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
            }
            return .result(ResultInfo(
                sessionId: sessionId,
                result: result,
                isError: isError,
                costUSD: costUSD,
                durationMs: durationMs,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                cacheCreationTokens: cacheCreationTokens
            ))

        default:
            return .unknown(type: type, raw: line)
        }
    }

    private static func parseStreamEvent(_ json: [String: Any]) -> ClaudeEvent? {
        guard let event = json["event"] as? [String: Any],
              let eventType = event["type"] as? String
        else { return nil }

        switch eventType {
        case "message_start":
            return .messageStart

        case "content_block_start":
            let index = event["index"] as? Int ?? 0
            let block = event["content_block"] as? [String: Any] ?? [:]
            let blockType = block["type"] as? String ?? "text"
            if blockType == "tool_use" {
                let id = block["id"] as? String ?? ""
                let name = block["name"] as? String ?? ""
                return .toolUseStart(index: index, id: id, name: name)
            }
            return .contentBlockStart(index: index, type: blockType)

        case "content_block_delta":
            let index = event["index"] as? Int ?? 0
            if let delta = event["delta"] as? [String: Any] {
                let deltaType = delta["type"] as? String ?? ""
                if deltaType == "text_delta", let text = delta["text"] as? String {
                    return .textDelta(text)
                }
                if deltaType == "input_json_delta", let json = delta["partial_json"] as? String {
                    return .toolInputDelta(index: index, json: json)
                }
            }
            return nil

        case "content_block_stop":
            let index = event["index"] as? Int ?? 0
            return .contentBlockStop(index: index)

        case "message_delta":
            let delta = event["delta"] as? [String: Any]
            let stopReason = delta?["stop_reason"] as? String
            return .messageStop(stopReason: stopReason)

        case "message_stop":
            return .messageStop(stopReason: nil)

        default:
            return nil
        }
    }
}
