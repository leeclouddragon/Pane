import Foundation

/// Abstracts the Claude CLI's wire format (arguments, stdin encoding, stdout parsing).
/// When CLI changes its streaming protocol, create a new conforming type —
/// the rest of the app (Conversation, UI, SessionHistory) stays untouched.
protocol CLIProtocolAdapter {
    /// CLI arguments that configure the output/input format.
    /// Session-level args (e.g. --resume) are appended by the caller.
    func formatArguments() -> [String]

    /// Encode a user prompt into the wire format written to CLI stdin.
    /// The returned Data must include any trailing delimiter (e.g. newline).
    func encodeUserMessage(_ prompt: String) -> Data

    /// Parse a single stdout line into an internal event.
    /// Returns nil for blank or unparseable lines.
    func parseLine(_ line: String) -> ClaudeEvent?
}
