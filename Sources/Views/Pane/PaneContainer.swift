import SwiftUI

/// Recursive pane renderer. Leaf → ConversationView, split → two panes with divider.
struct PaneContainer: View {
    @Environment(PaneState.self) private var paneState
    @Environment(PaneDragState.self) private var dragState
    let node: PaneNode

    var body: some View {
        switch node {
        case .conversation(let state):
            VStack(spacing: 0) {
                if paneState.paneCount > 1 {
                    PaneTitleBar(conversation: state)
                    Divider()
                }
                ConversationView(conversation: state)
                    .overlay(dimOverlay(for: state))
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded { paneState.focusedConversation = state }
            )
            .overlay {
                if dragState.isDragging {
                    DropZoneDetector(conversation: state)
                }
            }

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

// MARK: - Drop Zone Detection & Overlay

/// Detects whether the drag cursor is over this pane and computes the drop zone.
/// Renders the visual drop zone indicator.
private struct DropZoneDetector: View {
    let conversation: ConversationState
    @Environment(PaneDragState.self) private var dragState

    private var isDragSource: Bool {
        dragState.draggedPane === conversation
    }

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named("paneRoot"))
            let isHovered = !isDragSource && frame.contains(dragState.cursorLocation)
            let zone: DropZone? = isHovered
                ? dropZone(
                    at: CGPoint(
                        x: dragState.cursorLocation.x - frame.minX,
                        y: dragState.cursorLocation.y - frame.minY
                    ),
                    in: frame.size
                )
                : nil

            DropZoneOverlay(zone: zone, isSource: isDragSource)
                .onChange(of: isHovered, initial: true) { _, hovered in
                    if hovered {
                        dragState.hoverTarget = conversation
                    } else if dragState.hoverTarget === conversation {
                        dragState.hoverTarget = nil
                        dragState.hoverZone = nil
                    }
                }
                .onChange(of: zone, initial: true) { _, newZone in
                    if isHovered {
                        dragState.hoverZone = newZone
                    }
                }
        }
        .allowsHitTesting(false)
    }
}

/// Renders a semi-transparent highlight on the target drop zone edge.
private struct DropZoneOverlay: View {
    let zone: DropZone?
    let isSource: Bool

    var body: some View {
        Group {
            if isSource {
                Color.black.opacity(0.3)
            } else if let zone {
                dropHighlight(zone: zone)
            } else {
                Color.clear
            }
        }
        .animation(.easeOut(duration: 0.12), value: zone)
    }

    @ViewBuilder
    private func dropHighlight(zone: DropZone) -> some View {
        GeometryReader { geo in
            let fill = Color.accentColor.opacity(0.12)
            let border = Color.accentColor.opacity(0.45)

            switch zone {
            case .left:
                HStack(spacing: 0) {
                    zoneRect(fill: fill, border: border)
                        .frame(width: geo.size.width * 0.5)
                    Spacer(minLength: 0)
                }
            case .right:
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    zoneRect(fill: fill, border: border)
                        .frame(width: geo.size.width * 0.5)
                }
            case .top:
                VStack(spacing: 0) {
                    zoneRect(fill: fill, border: border)
                        .frame(height: geo.size.height * 0.5)
                    Spacer(minLength: 0)
                }
            case .bottom:
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    zoneRect(fill: fill, border: border)
                        .frame(height: geo.size.height * 0.5)
                }
            }
        }
    }

    private func zoneRect(fill: Color, border: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: 1.5))
            .padding(4)
    }
}

// MARK: - PaneSplit (unchanged)

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

// MARK: - PaneTitleBar (with drag gesture)

/// Per-pane title bar, visible only in multi-pane mode.
/// Shows conversation title + "+" split button. Drag to move pane.
private struct PaneTitleBar: View {
    let conversation: ConversationState
    @Environment(PaneState.self) private var paneState
    @Environment(PaneDragState.self) private var dragState

    var body: some View {
        HStack(spacing: 4) {
            Text("—")
                .foregroundStyle(.quaternary)
            Text(title)
                .foregroundStyle(isFocused ? .primary : .secondary)
                .lineLimit(1)

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    paneState.splitHorizontal(pane: conversation)
                }
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Split Right")
        }
        .font(.system(size: 11))
        .frame(height: 28)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
        .gesture(paneDragGesture)
        .opacity(dragState.draggedPane === conversation ? 0.4 : 1.0)
    }

    private var paneDragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("paneRoot"))
            .onChanged { value in
                guard paneState.paneCount > 1 else { return }
                if !dragState.isDragging {
                    dragState.beginDrag(pane: conversation, origin: value.startLocation)
                }
                dragState.updateDrag(pane: conversation, location: value.location)
            }
            .onEnded { _ in
                guard dragState.isDragging else { return }
                if let (source, target, zone) = dragState.endDrag() {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        paneState.movePane(source: source, to: target, zone: zone)
                    }
                }
            }
    }

    private var isFocused: Bool {
        paneState.focusedConversation === conversation
    }

    private var title: String {
        let t = conversation.displayTitle
        return t.isEmpty ? "New Thread" : t
    }
}

// MARK: - PaneDivider (unchanged)

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
