import SwiftUI

/// Renders markdown text by splitting into blocks: paragraphs, code, hr, tables.
struct MarkdownView: View {
    let text: String
    var compact: Bool = false

    @State private var blocks: [MarkdownBlock] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .if(!compact) { $0.frame(maxWidth: .infinity, alignment: .leading) }
        .onChange(of: text, initial: true) { blocks = parseBlocks() }
    }

    // MARK: - Block types

    private enum MarkdownBlock {
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
            if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed)
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            } else {
                Text(text)
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }

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
                        .font(.system(size: 11, design: .monospaced))
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
                        .font(.system(size: 11, weight: .semibold))
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
                            .font(.system(size: 11))
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
