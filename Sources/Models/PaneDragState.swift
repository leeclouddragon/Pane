import SwiftUI

/// Which edge of the target pane the dragged pane will be placed at.
enum DropZone: Equatable {
    case left, right, top, bottom
}

/// Shared drag state for pane drag-and-drop reordering.
/// Injected via `.environment()` from AppShell.
@Observable
final class PaneDragState {
    /// The conversation being dragged. Nil when idle.
    var draggedPane: ConversationState?
    /// Current cursor position in the "paneRoot" coordinate space.
    var cursorLocation: CGPoint = .zero
    /// The target pane the cursor is hovering over.
    var hoverTarget: ConversationState?
    /// Which zone within the hover target.
    var hoverZone: DropZone?

    var isDragging: Bool { draggedPane != nil }

    private var dragOrigin: CGPoint = .zero
    private var isActivated = false

    func beginDrag(pane: ConversationState, origin: CGPoint) {
        dragOrigin = origin
        isActivated = false
    }

    /// Call on each drag change. Returns true once the drag is activated (past threshold).
    @discardableResult
    func updateDrag(pane: ConversationState, location: CGPoint) -> Bool {
        if !isActivated {
            let distance = hypot(location.x - dragOrigin.x, location.y - dragOrigin.y)
            guard distance >= 8 else { return false }
            isActivated = true
            draggedPane = pane
            NSCursor.closedHand.push()
        }
        cursorLocation = location
        return true
    }

    func endDrag() -> (source: ConversationState, target: ConversationState, zone: DropZone)? {
        let result: (ConversationState, ConversationState, DropZone)?
        if let source = draggedPane, let target = hoverTarget, let zone = hoverZone, source !== target {
            result = (source, target, zone)
        } else {
            result = nil
        }
        reset()
        return result
    }

    func cancelDrag() {
        reset()
    }

    private func reset() {
        if isActivated { NSCursor.pop() }
        draggedPane = nil
        hoverTarget = nil
        hoverZone = nil
        cursorLocation = .zero
        isActivated = false
    }
}

/// Determine drop zone by dividing the rect into 4 triangles via its diagonals.
func dropZone(at point: CGPoint, in size: CGSize) -> DropZone {
    let nx = point.x / size.width   // 0=left, 1=right
    let ny = point.y / size.height  // 0=top, 1=bottom

    // Diagonal from top-left to bottom-right: ny == nx
    // Diagonal from top-right to bottom-left: ny == 1-nx
    let belowMainDiag = ny > nx
    let belowAntiDiag = ny > (1 - nx)

    switch (belowMainDiag, belowAntiDiag) {
    case (true, false):  return .left
    case (false, true):  return .right
    case (true, true):   return .bottom
    case (false, false): return .top
    }
}
