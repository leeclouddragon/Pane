import SwiftUI

/// Routes a ContentBlock to its renderer.
struct ContentBlockView: View {
    let block: ContentBlock
    var compact: Bool = false

    var body: some View {
        switch block {
        case .text(let content):
            TextBlockView(content: content, compact: compact)
        case .code(let content):
            CodeBlockView(content: content)
        case .toolCall(let content):
            ToolCallBlockView(content: content)
        case .toolResult(let content):
            ToolResultBlockView(content: content)
        case .thinking(let content):
            ThinkingBlockView(content: content)
        case .progress(let content):
            ProgressBlockView(content: content)
        case .error(let content):
            ErrorBlockView(content: content)
        case .image(let content):
            ImageBlockView(content: content, compact: compact)
        case .systemResult(let content):
            SystemResultBlockView(content: content)
        }
    }
}

// MARK: - Text

struct TextBlockView: View {
    let content: TextContent
    var compact: Bool = false

    var body: some View {
        MarkdownView(text: content.text, compact: compact)
    }
}

// MARK: - Code

struct CodeBlockView: View {
    let content: CodeContent
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label + copy button
            if content.language != nil || isHovered {
                HStack {
                    if let lang = content.language {
                        Text(lang)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isHovered {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content.code, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(content.code)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, content.language != nil ? 4 : 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Tool Call

struct ToolCallBlockView: View {
    let content: ToolCallContent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 6) {
                // Spinning indicator or tool icon
                if content.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: toolIcon(content.tool))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(content.isError ? .red : .orange)
                        .frame(width: 14)
                }

                Text(content.tool)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                // Summary: file path, command, pattern, etc.
                if !content.summary.isEmpty {
                    Text(abbreviatePath(content.summary))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if !content.detail.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture {
                if !content.detail.isEmpty {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
            }

            // Expandable detail (tool result output)
            if isExpanded && !content.detail.isEmpty {
                Divider().padding(.horizontal, 8)

                ScrollView(.vertical, showsIndicators: true) {
                    Text(content.detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(content.isError ? .red : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func toolIcon(_ tool: String) -> String {
        switch tool.lowercased() {
        case "read": return "doc.text"
        case "edit": return "pencil.line"
        case "write": return "doc.badge.plus"
        case "bash": return "terminal"
        case "glob": return "folder.badge.questionmark"
        case "grep": return "magnifyingglass"
        case "task": return "person.2"
        case "webfetch": return "globe"
        default: return "wrench"
        }
    }

    /// Shorten absolute paths: /Users/foo/codebase/Bar/src/main.swift → ~/codebase/Bar/src/main.swift
    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Tool Result

struct ToolResultBlockView: View {
    let content: ToolResultContent

    var body: some View {
        Text(content.output)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(content.isError ? .red : .secondary)
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Thinking

struct ThinkingBlockView: View {
    let content: ThinkingContent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 4) {
                if content.isComplete {
                    Text("Thought for \(formattedDuration)")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = Int(context.date.timeIntervalSince(content.startTime))
                        if content.text.isEmpty {
                            Text("Thinking...")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Thinking for \(elapsed)s")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }

            // Thinking content — shown when expanded
            if isExpanded && !content.text.isEmpty {
                Text(content.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
            // Streaming: start expanded; completed/historical: start collapsed
            isExpanded = !content.isComplete
        }
        .onChange(of: content.isComplete) { _, complete in
            // Auto-collapse when thinking finishes
            if complete {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded = false
                }
            }
        }
    }

    private var formattedDuration: String {
        let end = content.endTime ?? Date()
        let elapsed = max(1, Int(end.timeIntervalSince(content.startTime)))
        if elapsed < 60 { return "\(elapsed)s" }
        return "\(elapsed / 60)m \(elapsed % 60)s"
    }
}

// MARK: - Progress

struct ProgressBlockView: View {
    let content: ProgressContent

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(content.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Error

struct ErrorBlockView: View {
    let content: ErrorContent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
            Text(content.message)
                .font(.system(size: 11))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.red.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Image

struct ImageBlockView: View {
    let content: ImageContent
    var compact: Bool = false

    var body: some View {
        if let nsImage = NSImage(contentsOf: content.url) {
            let maxW: CGFloat = compact ? 120 : 280
            let maxH: CGFloat = compact ? 80 : 200

            Button(action: { NSWorkspace.shared.open(content.url) }) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxW, maxHeight: maxH)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator.opacity(0.5), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - System Result (slash command output)

struct SystemResultBlockView: View {
    let content: SystemResultContent
    @State private var isHovered = false

    var body: some View {
        if content.isContextUsage {
            ContextUsageView(content: content)
        } else {
            defaultView
        }
    }

    private var defaultView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Raw text content (with ANSI color support)
            HStack(alignment: .top) {
                ANSITextView(text: content.text)

                Spacer(minLength: 0)
            }
            .padding(12)

            // Copy button on hover
            if isHovered {
                HStack {
                    Spacer()
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(content.text, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 6)
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
    }

}
