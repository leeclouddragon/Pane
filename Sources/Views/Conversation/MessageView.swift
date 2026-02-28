import SwiftUI

/// Renders a single message. User = right-aligned compact card, Assistant = left-aligned plain text.
struct MessageView: View {
    let message: Message

    var body: some View {
        Group {
            if message.role == .user {
                userBubble
            } else {
                assistantContent
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - User message: compact right-aligned bubble

    private var userBubble: some View {
        let imageBlocks = message.blocks.filter { if case .image = $0 { return true } else { return false } }
        let otherBlocks = message.blocks.filter { if case .image = $0 { return false } else { return true } }

        return VStack(alignment: .trailing, spacing: 6) {
            // Images: outside the bubble, right-aligned thumbnails
            if !imageBlocks.isEmpty {
                HStack(spacing: 4) {
                    ForEach(imageBlocks) { block in
                        ContentBlockView(block: block, compact: true)
                    }
                }
            }

            // Text and other blocks: inside the bubble
            if !otherBlocks.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(otherBlocks) { block in
                        ContentBlockView(block: block, compact: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Assistant message: left-aligned plain text

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(message.blocks) { block in
                ContentBlockView(block: block)
            }
            if let seconds = message.durationSeconds {
                MessageDuration(seconds: seconds)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Per-message completion duration (inline, like Claude Code)

struct MessageDuration: View {
    let seconds: Int

    @State private var verb = Self.verbs.randomElement()!

    var body: some View {
        Text("\u{2736} \(verb) for \(formatDuration(seconds))")
            .font(.system(size: 13))
            .foregroundStyle(.quaternary)
            .padding(.vertical, 2)
    }

    private func formatDuration(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let remainder = s % 60
        if remainder == 0 { return "\(m)m" }
        return "\(m)m \(remainder)s"
    }

    private static let verbs = [
        "Baked", "Crunched", "Brewed", "Simmered",
        "Whipped up", "Churned", "Distilled", "Forged",
        "Crafted", "Cooked up", "Conjured", "Percolated",
    ]
}

// MARK: - Streaming indicator (Claude Code style shimmer)

/// Unified activity indicator at the bottom of the conversation.
/// Streaming: animated star + verb + live timer.
/// Complete: static star + past-tense verb + final duration.
struct ActivityIndicator: View {
    let isStreaming: Bool
    let startTime: Date?
    let durationSeconds: Int?

    @State private var verb = Self.streamingVerbs.randomElement()!
    @State private var completionVerb = Self.completionVerbs.randomElement()!
    @State private var color = Self.palette.randomElement()!

    var body: some View {
        if isStreaming {
            streamingView
        } else if let seconds = durationSeconds {
            completionView(seconds)
        }
    }

    // MARK: - Streaming state

    private var streamingView: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let shimmerPhase = t.truncatingRemainder(dividingBy: 1.8) / 1.8
            let starPhase = sin(t * .pi / 1.5)             // -1…1, period 3s
            let starScale = 0.85 + 0.25 * (starPhase + 1) / 2  // 0.85…1.1
            let starRotation = t.truncatingRemainder(dividingBy: 4) / 4 * 360

            HStack(spacing: 7) {
                Text("\u{2736}")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                    .scaleEffect(starScale)
                    .rotationEffect(.degrees(starRotation))

                shimmerText(phase: shimmerPhase)

                if let start = startTime {
                    Text(formatDuration(Int(timeline.date.timeIntervalSince(start))))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(color.opacity(0.5))
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shimmerText(phase: Double) -> some View {
        let label = "\(verb)..."
        return ZStack(alignment: .leading) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color.opacity(0.35))

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .mask(
                    GeometryReader { geo in
                        let w = geo.size.width
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.5), .white, .white.opacity(0.5), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: w * 0.5)
                        .offset(x: -w * 0.25 + CGFloat(phase) * w * 1.25)
                    }
                )
        }
    }

    // MARK: - Completion state

    private func completionView(_ seconds: Int) -> some View {
        Text("\u{2736} \(completionVerb) for \(formatDuration(seconds))")
            .font(.system(size: 13))
            .foregroundStyle(.quaternary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func formatDuration(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let remainder = s % 60
        if remainder == 0 { return "\(m)m" }
        return "\(m)m \(remainder)s"
    }

    private static let palette: [Color] = [
        Color(red: 0.95, green: 0.45, blue: 0.30),
        Color(red: 0.90, green: 0.55, blue: 0.20),
        Color(red: 0.85, green: 0.35, blue: 0.55),
        Color(red: 0.70, green: 0.45, blue: 0.85),
        Color(red: 0.40, green: 0.55, blue: 0.90),
        Color(red: 0.35, green: 0.75, blue: 0.65),
    ]

    private static let streamingVerbs = [
        "Pondering", "Ruminating", "Cogitating", "Musing",
        "Contemplating", "Noodling", "Deliberating", "Mulling over",
        "Dreaming up", "Brainstorming", "Percolating",
        "Daydreaming", "Manifesting", "Conjuring", "Simmering",
    ]

    private static let completionVerbs = [
        "Baked", "Crunched", "Brewed", "Simmered",
        "Whipped up", "Churned", "Distilled", "Forged",
        "Crafted", "Cooked up", "Conjured", "Percolated",
    ]
}

// MARK: - Compacting indicator

struct CompactingIndicator: View {
    @State private var rotation: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(rotation))

            Text("Compacting context...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Conditional modifier

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
