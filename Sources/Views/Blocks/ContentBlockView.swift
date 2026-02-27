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
        }
    }
}

// MARK: - Text

struct TextBlockView: View {
    let content: TextContent
    var compact: Bool = false

    var body: some View {
        Text(content.text)
            .font(.system(size: 14))
            .lineSpacing(4)
            .textSelection(.enabled)
            .if(!compact) { $0.frame(maxWidth: .infinity, alignment: .leading) }
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
                    .font(.system(size: 13, design: .monospaced))
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: toolIcon(content.tool))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 16)

            Text(content.tool)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(content.summary)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            Image(systemName: content.isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func toolIcon(_ tool: String) -> String {
        switch tool.lowercased() {
        case "read": "doc.text"
        case "edit": "pencil.line"
        case "write": "doc.badge.plus"
        case "bash": "terminal"
        case "glob": "folder.badge.questionmark"
        case "grep": "magnifyingglass"
        default: "wrench"
        }
    }
}

// MARK: - Tool Result

struct ToolResultBlockView: View {
    let content: ToolResultContent

    var body: some View {
        Text(content.output)
            .font(.system(size: 12, design: .monospaced))
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain")
                .font(.system(size: 10))
                .foregroundStyle(.purple.opacity(0.6))
            Text("Thinking...")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
                .font(.system(size: 13))
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
                .font(.system(size: 12))
                .foregroundStyle(.red)
            Text(content.message)
                .font(.system(size: 13))
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
