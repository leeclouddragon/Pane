import SwiftUI

/// Recursive pane layout model.
/// Leaf = conversation, branch = split into two panes.
@Observable
final class PaneState {
    var root: PaneNode
    let providerState: ProviderState
    /// Currently focused conversation pane.
    var focusedConversation: ConversationState?

    init(providerState: ProviderState = ProviderState()) {
        self.providerState = providerState
        let conversation = ConversationState()
        conversation.providerState = providerState
        self.root = .conversation(conversation)
        self.focusedConversation = conversation
    }

    private func makeConversation() -> ConversationState {
        let c = ConversationState()
        c.providerState = providerState
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
        focusedConversation = newConversation
    }

    func closePane(_ pane: ConversationState) {
        root = removeNode(containing: pane, from: root) ?? .conversation(makeConversation())
        // Focus the remaining pane (or the new one)
        if focusedConversation === pane {
            focusedConversation = allConversations.first
        }
    }

    /// All leaf conversations in tree order.
    var allConversations: [ConversationState] {
        collectConversations(from: root)
    }

    /// The focused conversation, or the first one if none is set.
    var activeConversation: ConversationState? {
        if let fc = focusedConversation, allConversations.contains(where: { $0 === fc }) {
            return fc
        }
        return allConversations.first
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
        // Don't close the last pane
        guard allConversations.count > 1 else { return }
        closePane(pane)
    }

    /// Replace the entire root with a fresh welcome conversation.
    func newThread() {
        let c = makeConversation()
        root = .conversation(c)
        focusedConversation = c
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
