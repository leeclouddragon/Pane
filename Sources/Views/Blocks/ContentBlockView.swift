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
                    .font(.system(size: 12, design: .monospaced))
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

    private var isReviewable: Bool {
        ["edit", "write", "bash"].contains(content.tool.lowercased())
    }

    var body: some View {
        if isReviewable {
            reviewView
        } else {
            researchView
        }
    }

    // MARK: - Research: lightweight, like Thinking blocks
    // Shows: tool name + input params (header) + brief output summary (collapsed)

    private var researchView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: tool name + input params
            HStack(spacing: 5) {
                if content.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                }

                Text(content.tool)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)

                if !content.summary.isEmpty {
                    Text(abbreviatePath(content.summary))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if !content.detail.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                if !content.detail.isEmpty {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
            }

            if !content.detail.isEmpty && !content.isRunning {
                if isExpanded {
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(truncatedDetail)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                    .frame(maxHeight: 200)
                } else {
                    Text("└ \(resultSummary)")
                        .font(.system(size: 12))
                        .foregroundStyle(.quaternary)
                        .padding(.leading, 4)
                }
            }
        }
    }

    // MARK: - Review: container for Edit, Write, Bash

    @ViewBuilder
    private var reviewView: some View {
        let hasError = content.isError

        VStack(alignment: .leading, spacing: 0) {
            // Header: same layout as researchView
            HStack(spacing: 5) {
                if content.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                }

                Text(content.tool)
                    .font(.system(size: 13))
                    .foregroundStyle(hasError ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))

                if !content.summary.isEmpty {
                    Text(abbreviatePath(content.summary))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(hasError ? AnyShapeStyle(.red.opacity(0.7)) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if reviewHasExpandableContent {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                if reviewHasExpandableContent {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
            }

            // Summary when collapsed
            if !isExpanded && !content.isRunning {
                if let mc = mutationContent {
                    Text("└ \(mc.collapsed)")
                        .font(.system(size: 12))
                        .foregroundStyle(.quaternary)
                        .padding(.leading, 4)
                }
            }

            // Content: Edit→diff, Write→preview, Bash→command output
            if isExpanded && !content.isRunning {
                if let mc = mutationContent {
                    mc.expandedView
                } else if !content.detail.isEmpty {
                    let detailColor: Color = hasError ? .red : .secondary
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(truncatedDetail)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(detailColor)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 300)

                    if content.detail.count > Self.detailTruncateLimit {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content.detail, forType: .string)
                        }) {
                            Text("Copy full output (\(content.detail.count) chars)")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .padding(.bottom, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            isExpanded = true
        }
    }

    // MARK: - Helpers

    private static let detailTruncateLimit = 20_000
    private static let bashTruncateLimit = 5_000

    private var effectiveTruncateLimit: Int {
        content.tool.lowercased() == "bash" ? Self.bashTruncateLimit : Self.detailTruncateLimit
    }

    private var truncatedDetail: String {
        let limit = effectiveTruncateLimit
        if content.detail.count > limit {
            return String(content.detail.prefix(limit)) + "\n\n… (\(content.detail.count - limit) more chars)"
        }
        return content.detail
    }

    /// Brief output summary for research tools (shown when collapsed).
    private var resultSummary: String {
        let lines = content.detail.components(separatedBy: "\n").filter { !$0.isEmpty }
        let count = lines.count
        switch content.tool.lowercased() {
        case "read":
            return "\(count) lines"
        case "grep":
            return "\(count) results"
        case "glob":
            return "\(count) files"
        default:
            return "\(count) lines"
        }
    }

    private var isMutationTool: Bool {
        ["edit", "write"].contains(content.tool.lowercased())
    }

    /// reviewView: expandable if has mutation input or command output
    private var reviewHasExpandableContent: Bool {
        isMutationTool || !content.detail.isEmpty
    }

    // MARK: - Mutation content (Edit diff / Write preview)

    struct MutationView {
        let collapsed: String
        let expandedView: AnyView
    }

    private var mutationContent: MutationView? {
        guard let data = content.inputJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        switch content.tool.lowercased() {
        case "edit":
            guard let oldStr = obj["old_string"] as? String,
                  let newStr = obj["new_string"] as? String
            else { return nil }
            let removed = oldStr.components(separatedBy: "\n")
            let added = newStr.components(separatedBy: "\n")
            let summary = diffSummary(removed: removed.count, added: added.count)
            return MutationView(
                collapsed: summary,
                expandedView: AnyView(editDiffView(removed: removed, added: added, summary: summary))
            )
        case "write":
            guard let written = obj["content"] as? String else { return nil }
            let lines = written.components(separatedBy: "\n")
            return MutationView(
                collapsed: "Added \(lines.count) lines",
                expandedView: AnyView(writePreviewView(lines))
            )
        default:
            return nil
        }
    }

    private func diffSummary(removed: Int, added: Int) -> String {
        if removed == 0 { return "Added \(added) lines" }
        if added == 0 { return "Removed \(removed) lines" }
        return "\(removed) removed, \(added) added"
    }

    private func editDiffView(removed: [String], added: [String], summary: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary: └ Added 2 lines
            Text("└ \(summary)")
                .font(.system(size: 12))
                .foregroundStyle(.quaternary)
                .padding(.leading, 4)
                .padding(.bottom, 4)

            // Diff lines with line numbers
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(removed.enumerated()), id: \.offset) { idx, line in
                        diffLine(number: idx + 1, marker: "-", text: line, color: .red.opacity(0.8), bg: .red.opacity(0.08))
                    }
                    ForEach(Array(added.enumerated()), id: \.offset) { idx, line in
                        diffLine(number: idx + 1, marker: "+", text: line, color: .green.opacity(0.8), bg: .green.opacity(0.08))
                    }
                }
                .textSelection(.enabled)
            }
            .frame(maxHeight: 300)
        }
    }

    private func diffLine(number: Int, marker: String, text: String, color: Color, bg: Color) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(number)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 32, alignment: .trailing)
            Text(" \(marker) ")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .background(bg)
    }

    private func writePreviewView(_ lines: [String]) -> some View {
        let preview = Array(lines.prefix(50))
        let truncated = lines.count > 50
        return VStack(alignment: .leading, spacing: 0) {
            Text("└ Added \(lines.count) lines")
                .font(.system(size: 12))
                .foregroundStyle(.quaternary)
                .padding(.leading, 4)
                .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(preview.enumerated()), id: \.offset) { idx, line in
                        HStack(alignment: .top, spacing: 0) {
                            Text("\(idx + 1)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .frame(width: 32, alignment: .trailing)
                            Text("   ")
                                .font(.system(size: 12, design: .monospaced))
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 1)
                    }
                    if truncated {
                        Text("… \(lines.count - 50) more lines")
                            .font(.system(size: 12))
                            .foregroundStyle(.quaternary)
                            .padding(.top, 4)
                            .padding(.leading, 36)
                    }
                }
                .textSelection(.enabled)
            }
            .frame(maxHeight: 300)
        }
    }

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

    private static let truncateLimit = 20_000

    private var truncatedOutput: String {
        if content.output.count > Self.truncateLimit {
            return String(content.output.prefix(Self.truncateLimit)) + "\n\n… (\(content.output.count - Self.truncateLimit) more chars)"
        }
        return content.output
    }

    var body: some View {
        Text(truncatedOutput)
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
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 4) {
                if content.isComplete {
                    Text("Thought for \(formattedDuration)")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = Int(context.date.timeIntervalSince(content.startTime))
                        if content.text.isEmpty {
                            Text("Thinking...")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Thinking for \(elapsed)s")
                                .font(.system(size: 13))
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
                .font(.system(size: 12))
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
                .font(.system(size: 12))
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
