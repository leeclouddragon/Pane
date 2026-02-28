import Foundation
import Network

private func remoteLog(_ message: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    let path = "/tmp/pane_remote.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
    }
}

/// Lightweight authenticated HTTP bridge for remote control.
final class RemoteControlServer {
    static let shared = RemoteControlServer()

    private let queue = DispatchQueue(label: "pane.remote.server")
    private var listener: NWListener?
    private weak var paneState: PaneState?
    private var token: String = ""
    private var hasStarted = false

    private init() {}

    func startIfPossible(paneState: PaneState) {
        self.paneState = paneState
        guard !hasStarted else { return }

        let env = ProcessInfo.processInfo.environment
        let configuredToken = env["PANE_REMOTE_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configuredToken.isEmpty else {
            remoteLog("remote server disabled: PANE_REMOTE_TOKEN is not set")
            return
        }

        let portValue = UInt16(env["PANE_REMOTE_PORT"] ?? "") ?? 18765
        guard let port = NWEndpoint.Port(rawValue: portValue) else {
            remoteLog("invalid port: \(portValue)")
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    remoteLog("remote server ready on port \(portValue)")
                case .failed(let error):
                    remoteLog("remote server failed: \(error)")
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            listener.start(queue: queue)
            self.listener = listener
            self.token = configuredToken
            self.hasStarted = true
        } catch {
            remoteLog("remote server start error: \(error.localizedDescription)")
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receive(on: connection, buffer: Data())
            case .failed(let error):
                remoteLog("connection failed: \(error)")
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                remoteLog("receive error: \(error)")
                connection.cancel()
                return
            }

            var merged = buffer
            if let data, !data.isEmpty {
                merged.append(data)
            }

            switch Self.parseRequest(from: merged) {
            case .incomplete:
                if isComplete {
                    self.send(self.errorResponse(status: 400, message: "Incomplete request"), on: connection)
                } else if merged.count > 1024 * 1024 {
                    self.send(self.errorResponse(status: 413, message: "Request body too large"), on: connection)
                } else {
                    self.receive(on: connection, buffer: merged)
                }

            case .invalid(let reason):
                self.send(self.errorResponse(status: 400, message: reason), on: connection)

            case .request(let request):
                self.process(request: request, connection: connection)
            }
        }
    }

    private func process(request: RemoteHTTPRequest, connection: NWConnection) {
        guard isAuthorized(headers: request.headers) else {
            send(errorResponse(status: 401, message: "Unauthorized"), on: connection)
            return
        }

        Task { @MainActor in
            let response = route(request)
            send(response, on: connection)
        }
    }

    private func isAuthorized(headers: [String: String]) -> Bool {
        if let header = headers["authorization"],
           header.lowercased().hasPrefix("bearer ") {
            let provided = String(header.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
            return provided == token
        }

        if let provided = headers["x-pane-token"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return provided == token
        }

        return false
    }

    @MainActor
    private func route(_ request: RemoteHTTPRequest) -> RemoteHTTPResponse {
        guard let paneState else {
            return errorResponse(status: 503, message: "Pane state unavailable")
        }

        let method = request.method.uppercased()
        let path = normalizedPath(request.path)

        switch (method, path) {
        case ("GET", "/api/v1/status"):
            return statusResponse(from: paneState)

        case ("GET", "/api/v1/messages"):
            let rawLimit = request.query["limit"].flatMap(Int.init) ?? 50
            let limit = max(1, min(200, rawLimit))
            return messagesResponse(from: paneState, limit: limit)

        case ("POST", "/api/v1/message"):
            return sendMessage(request.body, paneState: paneState)

        case ("POST", "/api/v1/stop"):
            guard let conversation = currentConversation(from: paneState) else {
                return errorResponse(status: 404, message: "No active conversation")
            }
            conversation.stop()
            return successResponse(status: 200, data: StopPayload(stopped: true))

        default:
            return errorResponse(status: 404, message: "Not Found")
        }
    }

    @MainActor
    private func currentConversation(from paneState: PaneState) -> ConversationState? {
        paneState.activeConversation ?? paneState.allConversations.first
    }

    @MainActor
    private func statusResponse(from paneState: PaneState) -> RemoteHTTPResponse {
        guard let conversation = currentConversation(from: paneState) else {
            return errorResponse(status: 404, message: "No active conversation")
        }

        let payload = StatusPayload(
            conversationId: conversation.id.uuidString,
            isStreaming: conversation.isStreaming,
            workingDirectory: conversation.workingDirectory,
            gitBranch: conversation.gitBranch,
            sessionId: conversation.processManager.sessionId,
            providerId: paneState.providerState.activeProviderID,
            messageCount: conversation.messages.count,
            lastAssistantMessage: lastAssistantText(in: conversation),
            updatedAt: Date()
        )

        return successResponse(status: 200, data: payload)
    }

    @MainActor
    private func messagesResponse(from paneState: PaneState, limit: Int) -> RemoteHTTPResponse {
        guard let conversation = currentConversation(from: paneState) else {
            return errorResponse(status: 404, message: "No active conversation")
        }

        let sliced = Array(conversation.messages.suffix(limit))
        let payload = MessagesPayload(
            conversationId: conversation.id.uuidString,
            isStreaming: conversation.isStreaming,
            messages: sliced.map { toAPImessage($0) }
        )
        return successResponse(status: 200, data: payload)
    }

    @MainActor
    private func sendMessage(_ body: Data, paneState: PaneState) -> RemoteHTTPResponse {
        guard let conversation = currentConversation(from: paneState) else {
            return errorResponse(status: 404, message: "No active conversation")
        }

        let decoder = JSONDecoder()
        guard let request = try? decoder.decode(SendMessageRequest.self, from: body) else {
            return errorResponse(status: 400, message: "Invalid JSON body")
        }

        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return errorResponse(status: 400, message: "text must not be empty")
        }

        if conversation.isStreaming {
            return errorResponse(status: 409, message: "Conversation is busy")
        }

        if let cwd = request.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty {
            conversation.workingDirectory = cwd
            conversation.refreshGitBranch()
        }

        conversation.send(text)

        let payload = SendMessagePayload(
            accepted: true,
            conversationId: conversation.id.uuidString,
            queuedAt: Date()
        )
        return successResponse(status: 202, data: payload)
    }

    @MainActor
    private func lastAssistantText(in conversation: ConversationState) -> String {
        guard let message = conversation.messages.last(where: { $0.role == .assistant }) else {
            return ""
        }
        return renderMessageText(message)
    }

    private func toAPImessage(_ message: Message) -> APIRemoteMessage {
        APIRemoteMessage(
            id: message.id.uuidString,
            role: message.role.rawValue,
            text: renderMessageText(message),
            timestamp: message.timestamp,
            hasError: containsError(message)
        )
    }

    private func containsError(_ message: Message) -> Bool {
        for block in message.blocks {
            switch block {
            case .error:
                return true
            case .toolCall(let content) where content.isError:
                return true
            case .toolResult(let content) where content.isError:
                return true
            default:
                continue
            }
        }
        return false
    }

    private func renderMessageText(_ message: Message) -> String {
        var parts: [String] = []

        for block in message.blocks {
            switch block {
            case .text(let content):
                parts.append(content.text)

            case .code(let content):
                let lang = content.language ?? "text"
                parts.append("```\(lang)\n\(content.code)\n```")

            case .toolCall(let content):
                var line = "[Tool: \(content.tool)]"
                if !content.summary.isEmpty {
                    line += " \(content.summary)"
                }
                if !content.detail.isEmpty {
                    line += "\n\(content.detail)"
                }
                parts.append(line)

            case .toolResult(let content):
                parts.append(content.output)

            case .thinking(let content):
                if !content.text.isEmpty {
                    parts.append("[Thinking]\n\(content.text)")
                }

            case .progress(let content):
                parts.append("[Progress] \(content.label)")

            case .error(let content):
                parts.append("[Error] \(content.message)")

            case .image(let content):
                parts.append("[Image] \(content.url.path)")

            case .systemResult(let content):
                parts.append(content.text)
            }
        }

        return parts.joined(separator: "\n\n")
    }

    private func normalizedPath(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    private func send(_ response: RemoteHTTPResponse, on connection: NWConnection) {
        var header = "HTTP/1.1 \(response.statusCode) \(Self.reasonPhrase(for: response.statusCode))\r\n"
        header += "Content-Type: application/json; charset=utf-8\r\n"
        header += "Content-Length: \(response.body.count)\r\n"
        header += "Connection: close\r\n\r\n"

        var payload = Data(header.utf8)
        payload.append(response.body)

        connection.send(content: payload, completion: .contentProcessed { error in
            if let error {
                remoteLog("send error: \(error)")
            }
            connection.cancel()
        })
    }

    private func successResponse<T: Encodable>(status: Int, data: T) -> RemoteHTTPResponse {
        let body = encodeJSON(SuccessEnvelope(data: data))
        return RemoteHTTPResponse(statusCode: status, body: body)
    }

    private func errorResponse(status: Int, message: String) -> RemoteHTTPResponse {
        let body = encodeJSON(ErrorEnvelope(error: message))
        return RemoteHTTPResponse(statusCode: status, body: body)
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return (try? encoder.encode(value)) ?? Data("{\"ok\":false,\"error\":\"encoding failure\"}".utf8)
    }

    private static func reasonPhrase(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 503: return "Service Unavailable"
        default: return "Error"
        }
    }

    private static func parseRequest(from data: Data) -> ParseOutcome {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let delimiterRange = data.range(of: delimiter) else {
            return .incomplete
        }

        let headerData = data.subdata(in: 0..<delimiterRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .invalid("Request headers must be UTF-8")
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .invalid("Missing request line")
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return .invalid("Invalid request line")
        }

        let method = String(parts[0])
        let target = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let fields = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { continue }
            let key = fields[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        guard contentLength >= 0 else {
            return .invalid("Invalid Content-Length")
        }

        let bodyStart = delimiterRange.upperBound
        let totalLength = bodyStart + contentLength
        guard data.count >= totalLength else {
            return .incomplete
        }

        let body = data.subdata(in: bodyStart..<totalLength)
        let components = URLComponents(string: "http://localhost\(target)")
        let path = components?.path.isEmpty == false ? components!.path : target

        var query: [String: String] = [:]
        components?.queryItems?.forEach { item in
            query[item.name] = item.value ?? ""
        }

        return .request(
            RemoteHTTPRequest(
                method: method,
                path: path,
                query: query,
                headers: headers,
                body: body
            )
        )
    }
}

private enum ParseOutcome {
    case incomplete
    case invalid(String)
    case request(RemoteHTTPRequest)
}

private struct RemoteHTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

private struct RemoteHTTPResponse {
    let statusCode: Int
    let body: Data
}

private struct SendMessageRequest: Decodable {
    let text: String
    let workingDirectory: String?
}

private struct SuccessEnvelope<T: Encodable>: Encodable {
    let ok: Bool = true
    let data: T
}

private struct ErrorEnvelope: Encodable {
    let ok: Bool = false
    let error: String
}

private struct StatusPayload: Encodable {
    let conversationId: String
    let isStreaming: Bool
    let workingDirectory: String
    let gitBranch: String
    let sessionId: String?
    let providerId: String
    let messageCount: Int
    let lastAssistantMessage: String
    let updatedAt: Date
}

private struct MessagesPayload: Encodable {
    let conversationId: String
    let isStreaming: Bool
    let messages: [APIRemoteMessage]
}

private struct APIRemoteMessage: Encodable {
    let id: String
    let role: String
    let text: String
    let timestamp: Date
    let hasError: Bool
}

private struct SendMessagePayload: Encodable {
    let accepted: Bool
    let conversationId: String
    let queuedAt: Date
}

private struct StopPayload: Encodable {
    let stopped: Bool
}
