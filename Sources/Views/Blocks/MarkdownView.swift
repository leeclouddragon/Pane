import SwiftUI

/// Renders markdown text by splitting into blocks: paragraphs, code, hr, tables.
struct MarkdownView: View {
    let text: String
    var compact: Bool = false
    var isStreaming: Bool = false

    @State private var blocks: [MarkdownBlock] = []
    @State private var lastParseTime: Date = .distantPast
    @State private var lastParsedLength: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                if isStreaming && index == blocks.count - 1,
                   case .paragraph(let paragraphText) = block {
                    Text(paragraphText)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                } else {
                    renderBlock(block)
                }
            }
        }
        .if(!compact) { $0.frame(maxWidth: .infinity, alignment: .leading) }
        .onChange(of: text, initial: true) {
            if isStreaming {
                let now = Date()
                if blocks.isEmpty || now.timeIntervalSince(lastParseTime) > 0.3 {
                    blocks = parseBlocks()
                    lastParseTime = now
                    lastParsedLength = text.count
                } else {
                    // Fast path: append new text to the last paragraph without re-parsing.
                    let delta = String(text.dropFirst(lastParsedLength))
                    lastParsedLength = text.count
                    if delta.contains("```") {
                        // Code fence detected — must full-parse
                        blocks = parseBlocks()
                        lastParseTime = now
                    } else if !blocks.isEmpty, case .paragraph(let existing) = blocks.last {
                        blocks[blocks.count - 1] = .paragraph(existing + delta)
                    } else {
                        let trimmed = delta.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { blocks.append(.paragraph(trimmed)) }
                    }
                }
            } else {
                blocks = parseBlocks()
                lastParseTime = .now
                lastParsedLength = text.count
            }
        }
        .onChange(of: isStreaming) { _, streaming in
            if !streaming { blocks = parseBlocks() }
        }
    }

    // MARK: - Block types

    private enum MarkdownBlock: Equatable {
        case paragraph(String)
        case codeBlock(language: String?, code: String)
        case horizontalRule
        case table(headers: [String], rows: [[String]])
    }

    // MARK: - Rendering

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            ParagraphBlockView(text: text).equatable()

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, language != nil ? 4 : 12)
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

        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
        }
    }

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 12, weight: .semibold))
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(.quaternary.opacity(0.3))

            // Rows
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell.trimmingCharacters(in: .whitespaces))
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Parsing

    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var paragraphLines: [String] = []

        func flushParagraph() {
            let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines = []
        }

        while i < lines.count {
            let line = lines[i]

            // Code fence
            if line.hasPrefix("```") {
                flushParagraph()
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                // Skip closing ```
                if i < lines.count { i += 1 }
                blocks.append(.codeBlock(
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            // Horizontal rule
            if line.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == "-" || $0 == " " })
                && line.filter({ $0 == "-" }).count >= 3
                && !line.contains("|") {
                flushParagraph()
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Table detection: line starts with | and contains multiple |
            if line.hasPrefix("|") && line.filter({ $0 == "|" }).count >= 2 {
                flushParagraph()
                var tableLines: [String] = []
                while i < lines.count && lines[i].hasPrefix("|") {
                    tableLines.append(lines[i])
                    i += 1
                }
                if let table = parseTable(tableLines) {
                    blocks.append(table)
                }
                continue
            }

            paragraphLines.append(line)
            i += 1
        }

        flushParagraph()
        return blocks
    }

    private func parseTable(_ lines: [String]) -> MarkdownBlock? {
        guard lines.count >= 2 else { return nil }

        func splitRow(_ line: String) -> [String] {
            var s = line
            if s.hasPrefix("|") { s = String(s.dropFirst()) }
            if s.hasSuffix("|") { s = String(s.dropLast()) }
            return s.components(separatedBy: "|")
        }

        let headers = splitRow(lines[0])

        // Skip separator line (|---|---|)
        let startRow = lines.count > 1 && lines[1].contains("---") ? 2 : 1

        var rows: [[String]] = []
        for j in startRow..<lines.count {
            let cells = splitRow(lines[j])
            if !cells.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(cells)
            }
        }

        return .table(headers: headers, rows: rows)
    }
}

/// Paragraph view that skips body re-evaluation when text hasn't changed.
private struct ParagraphBlockView: View, Equatable {
    let text: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .font(.system(size: 13))
                .lineSpacing(4)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}
