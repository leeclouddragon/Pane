# Pane

macOS native companion app for Claude Code CLI. Provides a split-pane conversation UI, multi-provider support, and remote control capabilities. Wraps the `claude` binary, communicating via NDJSON stream-json protocol.

## Build

```
swift build        # debug build
swift run          # build + launch
```

Requirements: Swift 5.10+, macOS 14+, SPM. Single executable target, no external dependencies.

## Architecture

Three-layer structure: Models (state) → Services (CLI communication) → Views (SwiftUI).

State management uses `@Observable` classes passed via SwiftUI `.environment()`. No Combine, no MVVM ViewModels.

```
PaneApp
  ├─ PaneState (@Observable)         — pane tree + focus tracking
  │   └─ PaneNode (recursive enum)   — .conversation(ConversationState) | .split(...)
  │       └─ ConversationState       — messages, streaming, tokens, provider selection
  │           └─ ClaudeProcessManager — subprocess lifecycle + pre-warm
  │
  ├─ ProviderState (@Observable)     — provider discovery + config
  └─ AppSettings (@Observable)       — zoom level, width mode
```

### CLI Communication

Each user message spawns a new `claude` subprocess (or reuses a pre-warmed one). Session continuity via `--resume <sessionId>`.

Request flow:
```
ComposerView.sendMessage()
  → ConversationState.send(text, attachments)
    → ClaudeProcessManager.send()
      → Process(claude --output-format stream-json --permission-mode ...)
        stdin:  NDJSON {"type":"user","message":{"role":"user","content":...}}
        stdout: NDJSON events line-by-line
```

Event flow:
```
Process stdout → StreamParser.parse(line) → ClaudeEvent
  → ConversationState.handleEvent()
    → mutate messages/blocks → SwiftUI re-renders
```

Pre-warm: after response completes, a new process starts in background waiting on stdin. Next send() pipes the prompt immediately, reducing latency.

Pending queue: messages sent while streaming enter a queue (`pendingMessages`). After response completes, next pending is auto-sent.

### Permission Modes

`InteractionMode` enum: `.normal` (bypassPermissions), `.acceptEdits`, `.plan`. Passed to CLI as `--permission-mode`. Cycled via Shift+Tab or status bar click.

Non-normal modes use `preferDirect=true` to bypass clother scripts (which add `--dangerously-skip-permissions` that would override the permission mode).

## Key Files

### Models
```
Conversation.swift    — ConversationState: messages, streaming, tokens, send(), handleEvent()
Message.swift         — Message struct, ContentBlock enum (text/code/toolCall/thinking/image/...)
PaneNode.swift        — PaneState (tree ops), PaneNode (recursive split layout)
Provider.swift        — ProviderState, ProviderEntry, LaunchConfig, provider discovery
WidthMode.swift       — AppSettings (zoom, width mode)
SlashCommand.swift    — LocalAction enum for slash commands
```

### Services
```
ClaudeProcessManager.swift  — Subprocess lifecycle, pre-warm, stdin/stdout piping
StreamParser.swift          — Parse NDJSON lines → ClaudeEvent enum
StreamJSONAdapter.swift     — CLIProtocolAdapter impl (args, encode, decode)
CLIProtocolAdapter.swift    — Protocol abstraction for CLI communication
SessionHistory.swift        — Scan ~/.claude/projects/ for session JSONL files
RemoteControlServer.swift   — HTTP bridge via NWListener (see REMOTE_CONTROL.md)
MenuBarManager.swift        — macOS menu bar status item
QuickInputPanel.swift       — Global hotkey panel (Option+Space)
```

### Views
```
Shell/
  AppShell.swift            — Root view, PaneTabBar (Terminal-style tabs), zoom scaling
  StatusBarView.swift       — 2-line status: model|cwd|git|mode|cost|tokens
  TitleBarView.swift        — (legacy, replaced by PaneTabBar in toolbar)

Pane/
  PaneContainer.swift       — Recursive split layout renderer with drag handles

Conversation/
  ConversationView.swift    — Welcome page + message scroll + session loading
  MessageView.swift         — User/assistant message cards, ActivityIndicator (shimmer)
  PlanActionBar.swift       — Plan mode banner + execute actions

Composer/
  ComposerView.swift        — Text input + toolbar + provider selector
  InputTextView.swift       — NSTextView wrapper (Cmd+Enter, Cmd+V image paste)
  PendingMessagesView.swift — Queued message cards above composer
  QuestionPanel.swift       — AskUserQuestion modal
  SlashMenuView.swift       — Slash command grid

Blocks/
  ContentBlockView.swift    — Router: text→MarkdownView, toolCall→ToolCallBlockView, etc.
                              ToolCallBlockView: researchView (Read/Grep/Glob) vs reviewView (Edit/Write/Bash)
                              Edit shows diff (red/green with line numbers), Write shows content preview
  MarkdownView.swift        — Markdown → AttributedString
  ANSITextView.swift        — ANSI escape code rendering
  ContextUsageView.swift    — Token breakdown table
```

## Conventions

### State
- Use `@Observable` classes, pass via `.environment()`.
- Each `ConversationState` owns one `ClaudeProcessManager`.
- Per-conversation provider selection via `activeProviderID`.

### Views
- Place new views in the appropriate subdirectory (Shell/, Conversation/, Composer/, Blocks/).
- No separate ViewModel files. Computed properties and methods live on the state class or the view.
- Use `@Environment` to read shared state, `@Bindable` for two-way binding to observable classes.

### Font Sizes
- Headers/tool names: 13pt
- Body text, detail content, monospaced output: 12pt
- Thinking content: 12pt
- Chevrons, small labels: 9-10pt
- StatusBar: 10pt monospaced
- Composer input: 12pt (matches message body)

### Colors
- Primary content: `.tertiary` (tool names, paths, output)
- Secondary: `.quaternary` (collapsed summaries, line numbers)
- Errors: `.red` with `.red.opacity(0.06)` background
- Diff: `.red.opacity(0.8)` removed, `.green.opacity(0.8)` added
- Interaction modes: orange (normal), green (acceptEdits), blue (plan)

### Tool Display
- researchView: Read, Grep, Glob — lightweight header + collapsible output
- reviewView: Edit, Write, Bash — card with content display
  - Edit: diff from inputJson (old_string/new_string), no output shown
  - Write: content preview from inputJson, no output shown
  - Bash: command output shown

## Common Tasks

### Add a new tool display
1. If research-style (read-only): add to `researchView` in `ToolCallBlockView`
2. If mutation-style: add to `reviewView`, extend `mutationContent` computed property
3. Extract summary in `ToolCallContent.extractSummary()` (Message.swift)

### Add a new CLI event type
1. Add case to `ClaudeEvent` enum (StreamParser.swift)
2. Parse in `StreamParser.parse()` under the appropriate `type` case
3. Handle in `ConversationState.handleEvent()` (Conversation.swift)

### Add a new provider
1. Add entry to `~/.config/pane/config.json` under `providers` array
2. Provider auto-discovered by `ProviderState.discover()`
3. For cloud providers: set `apiKey` field or add env vars

### Load history sessions
- `SessionHistory.allCandidates()` — fast metadata-only scan
- `SessionHistory.enrich(_:)` — extract first message from JSONL
- `SessionHistory.loadMessages(from:)` — full message + token reconstruction
- Resume via `processManager.sessionId = session.id`

## Configuration

```
~/.config/pane/config.json     — provider configuration
~/.claude/projects/             — session JSONL storage
~/.claude/settings.json         — Claude Code settings (hooks, permissions)
```

## Debug

```
/tmp/pane_debug.log            — subprocess stderr, pre-warm events, event parsing
/tmp/pane_remote.log           — remote control server events
```

Enable verbose logging: events are logged via `debugLog()` in ClaudeProcessManager. Truncated to 200 chars by default.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+Enter | Send message |
| Cmd+D | Split right |
| Cmd+Shift+D | Split down |
| Cmd+W | Close pane |
| Cmd+1-4 | Focus pane by index |
| Cmd+N | New thread |
| Cmd+Shift+W | Cycle width mode |
| Cmd+=/- | Zoom in/out |
| Cmd+0 | Reset zoom |
| Option+Space | Global quick input |
| Shift+Tab | Cycle interaction mode |
