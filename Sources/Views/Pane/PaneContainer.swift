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
struct PaneSplit<First: View, Second: View>: View {
    let direction: Axis
    @State private var ratio: CGFloat
    @State private var isDragging = false
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
                        .transaction { $0.animation = isDragging ? nil : $0.animation }
                    PaneDivider(direction: direction, ratio: $ratio, totalSize: totalSize, isDragging: $isDragging)
                    second
                        .transaction { $0.animation = isDragging ? nil : $0.animation }
                }
            } else {
                VStack(spacing: 0) {
                    first
                        .frame(height: firstSize)
                        .transaction { $0.animation = isDragging ? nil : $0.animation }
                    PaneDivider(direction: direction, ratio: $ratio, totalSize: totalSize, isDragging: $isDragging)
                    second
                        .transaction { $0.animation = isDragging ? nil : $0.animation }
                }
            }
        }
    }
}

/// Draggable divider between panes.
struct PaneDivider: View {
    let direction: Axis
    @Binding var ratio: CGFloat
    let totalSize: CGFloat
    @Binding var isDragging: Bool
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
                        if dragStartRatio == nil {
                            dragStartRatio = ratio
                            isDragging = true
                        }
                        let offset = direction == .horizontal ? value.translation.width : value.translation.height
                        let newRatio = (dragStartRatio ?? ratio) + offset / totalSize
                        ratio = min(max(newRatio, 0.15), 0.85)
                    }
                    .onEnded { _ in
                        dragStartRatio = nil
                        isDragging = false
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
