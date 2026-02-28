import SwiftUI

/// Single-line status bar: left info segments, right context ring + cost.
struct StatusBarView: View {
    let conversation: ConversationState

    var body: some View {
        HStack(spacing: 0) {
            // Left-aligned: model | cwd | git | status
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
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                    Text("bypass permissions")
                }
            }

            Spacer()

            // Right-aligned: cost | context ring
            StatusSegment {
                Text(String(format: "$%.2f", conversation.totalCostUSD))
            }

            ContextRing(percent: contextPercent)
                .padding(.horizontal, 6)
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

    private var contextPercent: Double {
        // Estimate from total tokens vs typical context window (200k)
        let total = conversation.totalTokens
        guard total > 0 else { return 0 }
        return min(Double(total) / 200_000.0, 1.0)
    }

    // MARK: - Formatting

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

    /// Compact path for status bar display.
    /// When path is short, show as-is. When long, abbreviate middle directories to first letter,
    /// keep first and last 2 components full. Long individual names get middle-truncated.
    private func compactPath(_ path: String, maxLength: Int = 45) -> String {
        let display = shortPath(path)
        guard display.count > maxLength else { return display }

        let parts = display.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 3 else { return display }

        let head = [parts[0]]                       // ~ or root
        let tail = Array(parts.suffix(2))            // last 2 components
        let middle = Array(parts.dropFirst().dropLast(2))

        // Abbreviate middle directories to first character;
        // for long names (e.g. DerivedData hash), show first char + … + last char
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

// MARK: - Context Ring

/// Thin circular progress indicator showing context window usage.
private struct ContextRing: View {
    let percent: Double

    private let size: CGFloat = 12
    private let lineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: lineWidth)

            // Filled arc
            Circle()
                .trim(from: 0, to: percent)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private var ringColor: Color {
        Color(nsColor: .secondaryLabelColor)
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
