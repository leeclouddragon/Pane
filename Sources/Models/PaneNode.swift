import SwiftUI

/// Recursive pane layout model.
/// Leaf = conversation, branch = split into two panes.
@Observable
final class PaneState {
    var root: PaneNode {
        didSet { paneCount = Self.countLeaves(root) }
    }
    let providerState: ProviderState
    /// Currently focused conversation pane.
    var focusedConversation: ConversationState?
    /// Cached leaf count — O(1) reads, updated on tree mutation.
    private(set) var paneCount: Int = 1

    init(providerState: ProviderState = ProviderState()) {
        self.providerState = providerState
        let conversation = ConversationState()
        conversation.providerState = providerState
        conversation.activeProviderID = providerState.activeProviderID
        self.root = .conversation(conversation)
        self.focusedConversation = conversation
    }

    private func makeConversation() -> ConversationState {
        let c = ConversationState()
        c.providerState = providerState
        c.activeProviderID = providerState.activeProviderID
        return c
    }

    func splitHorizontal(pane: ConversationState) {
        guard case .conversation(let existing) = findNode(containing: pane) else { return }
        let newConversation = makeConversation()
        replaceNode(
            containing: pane,
            with: .split(
                direction: .horizontal,
                ratio: 0.5,
                first: .conversation(existing),
                second: .conversation(newConversation)
            )
        )
        existing.scrollNudge += 1
        focusedConversation = newConversation
    }

    func splitVertical(pane: ConversationState) {
        guard case .conversation(let existing) = findNode(containing: pane) else { return }
        let newConversation = makeConversation()
        replaceNode(
            containing: pane,
            with: .split(
                direction: .vertical,
                ratio: 0.5,
                first: .conversation(existing),
                second: .conversation(newConversation)
            )
        )
        existing.scrollNudge += 1
        focusedConversation = newConversation
    }

    func closePane(_ pane: ConversationState) {
        root = removeNode(containing: pane, from: root) ?? .conversation(makeConversation())
        // Focus the remaining pane (or the new one)
        if focusedConversation === pane {
            focusedConversation = allConversations.first
        }
    }

    /// All leaf conversations in tree order. Use sparingly — O(n) traversal.
    var allConversations: [ConversationState] {
        collectConversations(from: root)
    }

    /// The focused conversation. Always valid — maintained by split/close/newThread.
    var activeConversation: ConversationState? {
        focusedConversation
    }

    /// Split focused pane horizontally.
    func splitFocusedHorizontal() {
        guard let pane = activeConversation else { return }
        splitHorizontal(pane: pane)
    }

    /// Split focused pane vertically.
    func splitFocusedVertical() {
        guard let pane = activeConversation else { return }
        splitVertical(pane: pane)
    }

    /// Close the focused pane.
    func closeFocusedPane() {
        guard let pane = activeConversation else { return }
        guard paneCount > 1 else { return }
        closePane(pane)
    }

    /// Adopt an external conversation into the main pane tree.
    /// If the focused pane is empty (welcome state), replace it; otherwise split.
    func adoptConversation(_ conversation: ConversationState) {
        conversation.providerState = providerState
        if let focused = focusedConversation, focused.messages.isEmpty {
            replaceNode(containing: focused, with: .conversation(conversation))
        } else if let focused = focusedConversation {
            replaceNode(
                containing: focused,
                with: .split(
                    direction: .horizontal,
                    ratio: 0.5,
                    first: .conversation(focused),
                    second: .conversation(conversation)
                )
            )
            focused.scrollNudge += 1
        }
        focusedConversation = conversation
    }

    /// Move a pane to a new position relative to a target pane.
    /// Removes source from the tree, then wraps target in a new split with source at the given zone.
    func movePane(source: ConversationState, to target: ConversationState, zone: DropZone) {
        guard source !== target, paneCount > 1 else { return }

        // Step 1: Remove source from tree
        guard let pruned = removeNode(containing: source, from: root) else { return }

        // Step 2: Determine split direction and ordering
        let direction: Axis
        let sourceIsFirst: Bool
        switch zone {
        case .left:   direction = .horizontal; sourceIsFirst = true
        case .right:  direction = .horizontal; sourceIsFirst = false
        case .top:    direction = .vertical;   sourceIsFirst = true
        case .bottom: direction = .vertical;   sourceIsFirst = false
        }

        let sourceNode = PaneNode.conversation(source)
        let targetNode = PaneNode.conversation(target)
        let newSplit: PaneNode = sourceIsFirst
            ? .split(direction: direction, ratio: 0.5, first: sourceNode, second: targetNode)
            : .split(direction: direction, ratio: 0.5, first: targetNode, second: sourceNode)

        // Step 3: Replace target in the pruned tree with the new split
        root = replaceNode(containing: target, in: pruned, with: newSplit)

        // Step 4: Focus follows the dragged pane
        focusedConversation = source
        source.scrollNudge += 1
    }

    /// Reset the focused pane to a fresh welcome conversation.
    func newThread() {
        guard let pane = focusedConversation else { return }
        let c = makeConversation()
        replaceNode(containing: pane, with: .conversation(c))
        focusedConversation = c
    }

    private static func countLeaves(_ node: PaneNode) -> Int {
        switch node {
        case .conversation: return 1
        case .split(_, _, let first, let second):
            return countLeaves(first) + countLeaves(second)
        }
    }

    private func collectConversations(from node: PaneNode) -> [ConversationState] {
        switch node {
        case .conversation(let state):
            return [state]
        case .split(_, _, let first, let second):
            return collectConversations(from: first) + collectConversations(from: second)
        }
    }

    // MARK: - Tree operations

    private func findNode(containing pane: ConversationState) -> PaneNode? {
        findNode(containing: pane, in: root)
    }

    private func findNode(containing pane: ConversationState, in node: PaneNode) -> PaneNode? {
        switch node {
        case .conversation(let state):
            return state === pane ? node : nil
        case .split(_, _, let first, let second):
            return findNode(containing: pane, in: first) ?? findNode(containing: pane, in: second)
        }
    }

    private func replaceNode(containing pane: ConversationState, with replacement: PaneNode) {
        root = replaceNode(containing: pane, in: root, with: replacement)
    }

    private func replaceNode(containing pane: ConversationState, in node: PaneNode, with replacement: PaneNode) -> PaneNode {
        switch node {
        case .conversation(let state):
            return state === pane ? replacement : node
        case .split(let dir, let ratio, let first, let second):
            return .split(
                direction: dir,
                ratio: ratio,
                first: replaceNode(containing: pane, in: first, with: replacement),
                second: replaceNode(containing: pane, in: second, with: replacement)
            )
        }
    }

    private func removeNode(containing pane: ConversationState, from node: PaneNode) -> PaneNode? {
        switch node {
        case .conversation(let state):
            return state === pane ? nil : node
        case .split(let dir, let ratio, let first, let second):
            let newFirst = removeNode(containing: pane, from: first)
            let newSecond = removeNode(containing: pane, from: second)
            if newFirst == nil { return newSecond }
            if newSecond == nil { return newFirst }
            return .split(direction: dir, ratio: ratio, first: newFirst!, second: newSecond!)
        }
    }
}

enum PaneNode {
    case conversation(ConversationState)
    indirect case split(direction: Axis, ratio: CGFloat, first: PaneNode, second: PaneNode)
}
