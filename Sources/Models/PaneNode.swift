import SwiftUI

/// Recursive pane layout model.
/// Leaf = conversation, branch = split into two panes.
@Observable
final class PaneState {
    var root: PaneNode
    let providerState: ProviderState

    init(providerState: ProviderState = ProviderState()) {
        self.providerState = providerState
        let conversation = ConversationState()
        conversation.providerState = providerState
        self.root = .conversation(conversation)
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
    }

    func closePane(_ pane: ConversationState) {
        root = removeNode(containing: pane, from: root) ?? .conversation(makeConversation())
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
