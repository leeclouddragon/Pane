import Foundation

/// Adapter for Claude CLI's `--output-format stream-json` protocol.
struct StreamJSONAdapter: CLIProtocolAdapter {
    func formatArguments() -> [String] {
        [
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
        ]
    }

    func encodeUserMessage(_ prompt: String) -> Data {
        let message: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": prompt,
            ],
        ]
        var data = try! JSONSerialization.data(withJSONObject: message)
        data.append(0x0A) // newline
        return data
    }

    func encodeToolResult(toolUseId: String, result: String) -> Data {
        let message: [String: Any] = [
            "type": "tool_result",
            "tool_use_id": toolUseId,
            "content": result,
        ]
        var data = try! JSONSerialization.data(withJSONObject: message)
        data.append(0x0A) // newline
        return data
    }

    func parseLine(_ line: String) -> ClaudeEvent? {
        StreamParser.parse(line: line)
    }
}
