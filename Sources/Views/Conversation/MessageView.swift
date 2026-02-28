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
            if message.blocks.isEmpty {
                StreamingIndicator()
            }
            ForEach(message.blocks) { block in
                ContentBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Streaming indicator (Claude Code style shimmer)

struct StreamingIndicator: View {
    // Picked once at creation — no cycling
    @State private var verb = Self.verbs.randomElement()!
    @State private var color = Self.palette.randomElement()!

    @State private var shimmerPhase: CGFloat = 0
    @State private var starScale: CGFloat = 0.85
    @State private var starRotation: Double = 0

    var body: some View {
        HStack(spacing: 7) {
            // Six-pointed star with gentle pulse + spin
            Text("\u{2736}")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .scaleEffect(starScale)
                .rotationEffect(.degrees(starRotation))

            // Shimmer text
            shimmerText
        }
        .padding(.vertical, 6)
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                starScale = 1.1
            }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                starRotation = 360
            }
        }
    }

    private var shimmerText: some View {
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
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.5), .white, .white.opacity(0.5), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: -geo.size.width * 0.25 + shimmerPhase * geo.size.width * 1.25)
                    }
                )
        }
    }

    private static let palette: [Color] = [
        Color(red: 0.95, green: 0.45, blue: 0.30), // coral
        Color(red: 0.90, green: 0.55, blue: 0.20), // amber
        Color(red: 0.85, green: 0.35, blue: 0.55), // rose
        Color(red: 0.70, green: 0.45, blue: 0.85), // violet
        Color(red: 0.40, green: 0.55, blue: 0.90), // blue
        Color(red: 0.35, green: 0.75, blue: 0.65), // teal
    ]

    private static let verbs = [
        "Pondering", "Ruminating", "Cogitating", "Musing",
        "Contemplating", "Noodling", "Deliberating", "Mulling over",
        "Dilly-dallying", "Dreaming up", "Brainstorming", "Percolating",
        "Woolgathering", "Chewing on it", "Marinating", "Infusing",
        "Daydreaming", "Manifesting", "Conjuring", "Simmering",
    ]
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
