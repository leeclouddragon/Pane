# Pane Remote Control API

This document describes the remote HTTP bridge exposed by Pane on macOS.

## 1. Start Pane with remote bridge enabled

Set environment variables before launching Pane:

```bash
export PANE_REMOTE_TOKEN='replace_with_strong_token'
export PANE_REMOTE_PORT='18765' # optional, defaults to 18765
```

Then run Pane from the same shell session:

```bash
swift run
```

If you launch Pane from Finder/GUI, export env vars via `launchctl setenv` first.

## 2. Security model

- Every API request must include:
  - `Authorization: Bearer <PANE_REMOTE_TOKEN>`
- Requests without a valid token return `401`.
- Do not expose this port directly to the public internet.
- Recommended: access it over Tailscale/WireGuard/SSH tunnel.

## 3. Endpoints

### `GET /api/v1/status`

Returns current active conversation status.

Example response:

```json
{
  "ok": true,
  "data": {
    "conversationId": "UUID",
    "isStreaming": false,
    "workingDirectory": "/Users/liyunlong/codebase/Pane",
    "gitBranch": "feat/remote-ios-bridge",
    "sessionId": "abc123",
    "providerId": "bedrock",
    "messageCount": 24,
    "lastAssistantMessage": "Latest assistant text...",
    "updatedAt": "2026-02-28T03:45:00Z"
  }
}
```

### `GET /api/v1/messages?limit=80`

Returns recent messages from the active conversation.

Query params:

- `limit`: optional, default `50`, range `1...200`

### `POST /api/v1/message`

Sends a new user prompt to the active conversation.

Request body:

```json
{
  "text": "Please check failing tests",
  "workingDirectory": "/Users/liyunlong/codebase/Pane"
}
```

Notes:

- `workingDirectory` is optional.
- If a request is already running, returns `409`.

### `POST /api/v1/stop`

Stops the current running request for the active conversation.

## 4. Minimal curl checks

```bash
TOKEN='replace_with_strong_token'
BASE='http://127.0.0.1:18765'

curl -sS "$BASE/api/v1/status" \
  -H "Authorization: Bearer $TOKEN" | jq .

curl -sS "$BASE/api/v1/message" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"hello from phone"}' | jq .
```
