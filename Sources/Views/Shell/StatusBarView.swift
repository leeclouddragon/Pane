import SwiftUI

/// Two-line status bar modeled after Claude Code's statusline.
/// Line 1: model | cwd | git | mode            session  $cost  ring
/// Line 2: Ctx | Total | In | Out | Cache
struct StatusBarView: View {
    let conversation: ConversationState

    var body: some View {
        VStack(spacing: 0) {
            // Line 1: info + cost
            HStack(spacing: 0) {
                StatusSegment {
                    Text(modelDisplay)
                }

                Pipe()

                StatusSegment {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 8))
                        Text(compactPath(conversation.workingDirectory))
                            .lineLimit(1)
                            .help(shortPath(conversation.workingDirectory))
                    }
                }

                Pipe()

                StatusSegment {
                    HStack(spacing: 3) {
                        Image(systemName: conversation.gitBranch.isEmpty ? "xmark.circle" : "arrow.triangle.branch")
                            .font(.system(size: 8))
                        Text(conversation.gitBranch.isEmpty ? "no git" : conversation.gitBranch)
                    }
                }

                Pipe()

                StatusSegment {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(conversation.interactionMode.color)
                            .frame(width: 5, height: 5)
                        Text("\(conversation.interactionMode.statusIcon) \(conversation.interactionMode.label)")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        conversation.cycleMode()
                    }
                }

                Spacer()

                StatusSegment {
                    SessionDuration(since: conversation.sessionStart)
                }

                StatusSegment {
                    Text(String(format: "$%.2f", conversation.totalCostUSD))
                }

                ContextRing(percent: conversation.contextPercent)
                    .padding(.horizontal, 6)
            }

            // Line 2: token breakdown (only when there's data)
            if hasTokenData {
                HStack(spacing: 0) {
                    StatusSegment {
                        Text("Ctx: \(Int(conversation.contextPercent * 100))%")
                    }
                    Pipe()
                    StatusSegment {
                        Text("Total: \(smartTokens(totalAllTokens))")
                    }
                    Pipe()
                    StatusSegment {
                        Text("In: \(smartTokens(conversation.inputTokens))")
                    }
                    Pipe()
                    StatusSegment {
                        Text("Out: \(smartTokens(conversation.outputTokens))")
                    }
                    Pipe()
                    StatusSegment {
                        Text("Cache: \(smartTokens(conversation.cachedTokens))")
                    }
                    Spacer()
                }
                .foregroundStyle(.quaternary)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Computed

    private var modelDisplay: String {
        let m = conversation.currentModel
        if m.isEmpty { return "—" }
        return shortModel(m)
    }

    private var hasTokenData: Bool {
        conversation.inputTokens > 0 || conversation.outputTokens > 0
    }

    private var totalAllTokens: Int {
        conversation.inputTokens + conversation.outputTokens + conversation.cachedTokens
    }

    // MARK: - Formatting

    /// Format token counts with automatic unit selection.
    private func smartTokens(_ count: Int) -> String {
        if count < 1_000 { return "\(count)" }
        if count < 1_000_000 {
            let k = Double(count) / 1_000
            return k >= 100 ? String(format: "%.0fk", k) : String(format: "%.1fk", k)
        }
        let m = Double(count) / 1_000_000
        return m >= 100 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
    }

    private func shortModel(_ model: String) -> String {
        // "global.anthropic.claude-opus-4-6-v1" → "Opus 4.6"
        if let range = model.range(of: "claude-") {
            var short = String(model[range.upperBound...])
            if let vRange = short.range(of: "-v", options: .backwards) {
                short = String(short[short.startIndex..<vRange.lowerBound])
            }
            let parts = short.split(separator: "-")
            if parts.count >= 3, let major = parts.dropFirst().first, let minor = parts.dropFirst(2).first {
                return "\(parts[0].capitalized) \(major).\(minor)"
            }
            return short
        }
        return model
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func compactPath(_ path: String, maxLength: Int = 45) -> String {
        let display = shortPath(path)
        guard display.count > maxLength else { return display }

        let parts = display.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 3 else { return display }

        let head = [parts[0]]
        let tail = Array(parts.suffix(2))
        let middle = Array(parts.dropFirst().dropLast(2))

        let abbreviated = middle.map { comp -> String in
            if comp.count <= 1 { return comp }
            if comp.count > 12 {
                return "\(comp.prefix(1))\u{2026}\(comp.suffix(1))"
            }
            return String(comp.prefix(1))
        }

        return (head + abbreviated + tail).joined(separator: "/")
    }
}

// MARK: - Session Duration

/// Displays elapsed time since session start, updating every 60s.
private struct SessionDuration: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 60)) { context in
            Text(formatDuration(from: since, to: context.date))
        }
    }

    private func formatDuration(from start: Date, to now: Date) -> String {
        let interval = Int(now.timeIntervalSince(start))
        let minutes = interval / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 { return "\(days)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(max(minutes, 1))m"
    }
}

// MARK: - Context Ring

private struct ContextRing: View {
    let percent: Double

    private let size: CGFloat = 12
    private let lineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: percent)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private var ringColor: Color {
        if percent > 0.85 { return .red }
        if percent > 0.65 { return .orange }
        return Color(nsColor: .secondaryLabelColor)
    }
}

// MARK: - Shared components

private struct StatusSegment<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(.horizontal, 6)
    }
}

private struct Pipe: View {
    var body: some View {
        Text("│")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.quaternary)
    }
}
