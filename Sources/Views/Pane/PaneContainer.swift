import SwiftUI

/// Recursive pane renderer. Leaf → ConversationView, split → two panes with divider.
struct PaneContainer: View {
    @Environment(PaneState.self) private var paneState
    let node: PaneNode

    var body: some View {
        switch node {
        case .conversation(let state):
            ConversationView(conversation: state)
                .overlay(dimOverlay(for: state))
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { paneState.focusedConversation = state }
                )

        case .split(let direction, let ratio, let first, let second):
            PaneSplit(direction: direction, ratio: ratio) {
                PaneContainer(node: first)
            } second: {
                PaneContainer(node: second)
            }
        }
    }

    @ViewBuilder
    private func dimOverlay(for state: ConversationState) -> some View {
        if paneState.paneCount > 1 && paneState.focusedConversation !== state {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture {
                    paneState.focusedConversation = state
                }
        }
    }
}

/// Resizable split between two panes.
/// Uses deferred resize: during drag only a ghost divider moves; pane content
/// stays frozen. Layout commits once on drag end → zero flickering.
struct PaneSplit<First: View, Second: View>: View {
    let direction: Axis
    @State private var ratio: CGFloat
    /// Non-nil while dragging — the ratio the user is dragging toward.
    @State private var pendingRatio: CGFloat?
    let first: First
    let second: Second

    init(
        direction: Axis,
        ratio: CGFloat,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self.direction = direction
        self._ratio = State(initialValue: ratio)
        self.first = first()
        self.second = second()
    }

    var body: some View {
        GeometryReader { geo in
            let totalSize = direction == .horizontal ? geo.size.width : geo.size.height
            let firstSize = round(totalSize * ratio)

            if direction == .horizontal {
                HStack(spacing: 0) {
                    first
                        .frame(width: firstSize)
                        .clipped()
                    PaneDivider(
                        direction: direction,
                        ratio: ratio,
                        totalSize: totalSize,
                        onDragChanged: { pendingRatio = $0 },
                        onDragEnded: { ratio = $0; pendingRatio = nil }
                    )
                    second
                        .clipped()
                }
                .overlay { ghostLine(totalSize: totalSize, crossSize: geo.size.height) }
            } else {
                VStack(spacing: 0) {
                    first
                        .frame(height: firstSize)
                        .clipped()
                    PaneDivider(
                        direction: direction,
                        ratio: ratio,
                        totalSize: totalSize,
                        onDragChanged: { pendingRatio = $0 },
                        onDragEnded: { ratio = $0; pendingRatio = nil }
                    )
                    second
                        .clipped()
                }
                .overlay { ghostLine(totalSize: totalSize, crossSize: geo.size.width) }
            }
        }
    }

    @ViewBuilder
    private func ghostLine(totalSize: CGFloat, crossSize: CGFloat) -> some View {
        if let pendingRatio {
            let pos = round(totalSize * pendingRatio)
            if direction == .horizontal {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.45))
                    .frame(width: 2)
                    .position(x: pos, y: crossSize / 2)
            } else {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.45))
                    .frame(height: 2)
                    .position(x: crossSize / 2, y: pos)
            }
        }
    }
}

/// Draggable divider between panes.
struct PaneDivider: View {
    let direction: Axis
    let ratio: CGFloat
    let totalSize: CGFloat
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void
    @State private var dragStartRatio: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(
                width: direction == .horizontal ? 1 : nil,
                height: direction == .vertical ? 1 : nil
            )
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartRatio == nil { dragStartRatio = ratio }
                        let offset = direction == .horizontal
                            ? value.translation.width : value.translation.height
                        let newRatio = min(max((dragStartRatio ?? ratio) + offset / totalSize, 0.15), 0.85)
                        onDragChanged(newRatio)
                    }
                    .onEnded { value in
                        let offset = direction == .horizontal
                            ? value.translation.width : value.translation.height
                        let newRatio = min(max((dragStartRatio ?? ratio) + offset / totalSize, 0.15), 0.85)
                        dragStartRatio = nil
                        onDragEnded(newRatio)
                    }
            )
            .onHover { hovering in
                if hovering {
                    if direction == .horizontal {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.resizeUpDown.push()
                    }
                } else {
                    NSCursor.pop()
                }
            }
    }
}
