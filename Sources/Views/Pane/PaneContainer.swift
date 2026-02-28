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
        // Dim unfocused panes when there are multiple.
        // Clicking the overlay focuses the pane and dismisses it.
        if paneState.allConversations.count > 1 && paneState.activeConversation !== state {
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

            if direction == .horizontal {
                HStack(spacing: 0) {
                    first.frame(width: totalSize * ratio)
                    PaneDivider(direction: direction, ratio: $ratio, totalSize: totalSize)
                    second
                }
            } else {
                VStack(spacing: 0) {
                    first.frame(height: totalSize * ratio)
                    PaneDivider(direction: direction, ratio: $ratio, totalSize: totalSize)
                    second
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
    @State private var dragStartRatio: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(
                width: direction == .horizontal ? 1 : nil,
                height: direction == .vertical ? 1 : nil
            )
            .contentShape(Rectangle().inset(by: -3))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartRatio == nil {
                            dragStartRatio = ratio
                        }
                        let offset = direction == .horizontal ? value.translation.width : value.translation.height
                        let newRatio = (dragStartRatio ?? ratio) + offset / totalSize
                        ratio = min(max(newRatio, 0.15), 0.85)
                    }
                    .onEnded { _ in
                        dragStartRatio = nil
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
