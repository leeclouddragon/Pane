import SwiftUI

/// Native SwiftUI rendering for `/context` command output.
/// Parses once in init — no repeated regex during body evaluation.
struct ContextUsageView: View {
    let parsed: ParsedContextUsage

    init(content: SystemResultContent) {
        self.parsed = content.parseContextUsage()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            if !parsed.categories.isEmpty {
                Divider().padding(.horizontal, 10)
                categorySection
            }

            ForEach(Array(parsed.sections.enumerated()), id: \.offset) { _, section in
                Divider().padding(.horizontal, 10)
                CollapsibleSection(header: section.header, items: section.items)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let model = parsed.model {
                Text(model)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let info = parsed.tokenInfo {
                HStack(spacing: 6) {
                    Text("\(info.used) / \(info.total)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text("(\(Int(info.percentage))%)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(barColor(info.percentage))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor(info.percentage))
                            .frame(width: geo.size.width * min(info.percentage / 100, 1.0))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(parsed.categories.enumerated()), id: \.offset) { _, cat in
                HStack(spacing: 8) {
                    Circle()
                        .fill(categoryColor(cat.name))
                        .frame(width: 7, height: 7)

                    Text(cat.name)
                        .font(.system(size: 11))
                        .foregroundStyle(isFreeCategory(cat.name) ? .tertiary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(cat.tokens)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 50, alignment: .trailing)

                    Text(cat.percentage)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func barColor(_ percentage: Double) -> Color {
        if percentage < 50 { return .green }
        if percentage < 80 { return .orange }
        return .red
    }

    private func isFreeCategory(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("free") || lower.contains("autocompact")
    }

    private func categoryColor(_ name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("system prompt") { return .blue }
        if lower.contains("system tool") { return .cyan }
        if lower.contains("mcp") { return .purple }
        if lower.contains("agent") { return .orange }
        if lower.contains("memory") { return .green }
        if lower.contains("skill") { return .pink }
        if lower.contains("message") { return .yellow }
        if lower.contains("free") { return Color(white: 0.6) }
        if lower.contains("autocompact") || lower.contains("buffer") { return .red.opacity(0.6) }
        return .gray
    }
}

// MARK: - Collapsible Section (MCP tools, Agents, Memory, Skills)

private struct CollapsibleSection: View {
    let header: String
    let items: [(name: String, detail: String)]
    @State private var isExpanded = false

    private var sectionIcon: String {
        let lower = header.lowercased()
        if lower.contains("mcp") { return "server.rack" }
        if lower.contains("agent") { return "person.2" }
        if lower.contains("memory") { return "brain" }
        if lower.contains("skill") { return "sparkles" }
        return "folder"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.quaternary)
                    .frame(width: 10)

                Image(systemName: sectionIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)

                Text(header)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("(\(items.count))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 0) {
                            Text(shortName(item.name))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if !item.detail.isEmpty {
                                Spacer(minLength: 8)

                                Text(item.detail)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func shortName(_ name: String) -> String {
        let dparts = name.components(separatedBy: "__")
        if dparts.count >= 3, dparts[0] == "mcp" {
            let server = dparts[1]
            let tool = dparts[2...].joined(separator: "__")
            return "\(tool) (\(server))"
        }
        let parts = name.split(separator: "_").map(String.init)
        if parts.count >= 3, parts[0] == "mcp" {
            let server = parts[1]
            let tool = parts[2...].joined(separator: "_")
            return "\(tool) (\(server))"
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if name.hasPrefix(home) {
            return "~" + name.dropFirst(home.count)
        }
        return name
    }
}
