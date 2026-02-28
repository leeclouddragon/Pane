import AppKit

/// Manages the macOS menu bar status item (NSStatusItem).
/// Clicking the icon shows a Cursor-style dropdown with recent sessions,
/// New Thread, Open Pane, Settings, and Quit.
final class MenuBarManager: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var paneState: PaneState?
    /// Cached sessions — refreshed each time the menu opens.
    private var cachedSessions: [SessionEntry] = []

    func setup(paneState: PaneState) {
        self.paneState = paneState

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "ellipsis.message", accessibilityDescription: "Pane")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Pane"
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        self.statusItem = item

        // Pre-cache sessions in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sessions = SessionHistory.scan(limit: 20)
            DispatchQueue.main.async { self?.cachedSessions = sessions }
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        buildMenu(into: menu)

        // Refresh cache for next open
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sessions = SessionHistory.scan(limit: 20)
            DispatchQueue.main.async { self?.cachedSessions = sessions }
        }
    }

    // MARK: - Menu construction

    private func buildMenu(into menu: NSMenu) {
        // Section header: Recent Threads
        let header = NSMenuItem(title: "Recent Threads", action: nil, keyEquivalent: "")
        header.isEnabled = false
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.systemOrange,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ]
        header.attributedTitle = NSAttributedString(string: "Recent Threads", attributes: attrs)
        menu.addItem(header)

        menu.addItem(.separator())

        // Recent sessions (top 3 inline)
        let inline = Array(cachedSessions.prefix(3))
        let remaining = Array(cachedSessions.dropFirst(3))

        for session in inline {
            let item = makeSessionItem(session)
            menu.addItem(item)
        }

        // "View More (N)" submenu
        if !remaining.isEmpty {
            let more = NSMenuItem(title: "View More (\(remaining.count))", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for session in remaining {
                sub.addItem(makeSessionItem(session))
            }
            more.submenu = sub
            menu.addItem(more)
        }

        menu.addItem(.separator())

        // New Thread
        let newItem = NSMenuItem(title: "New Thread", action: #selector(newThread), keyEquivalent: "n")
        newItem.keyEquivalentModifierMask = .command
        newItem.target = self
        menu.addItem(newItem)

        menu.addItem(.separator())

        // Open Pane
        let openItem = NSMenuItem(title: "Open Pane", action: #selector(openPane), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func makeSessionItem(_ session: SessionEntry) -> NSMenuItem {
        let title = String(session.firstMessage.prefix(50))
        let item = NSMenuItem(title: title, action: #selector(resumeSession(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = session

        // Subtitle: relative time + project path
        let timeStr = relativeDate(session.modifiedDate)
        let sub = NSMutableAttributedString()
        sub.append(NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13)
        ]))
        // Store time as tooltip instead of inline to keep it clean
        item.toolTip = "\(shortPath(session.cwd)) · \(timeStr)"
        return item
    }

    // MARK: - Actions

    @objc private func resumeSession(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? SessionEntry,
              let paneState else { return }

        activateApp()

        let conversation = paneState.activeConversation ?? paneState.allConversations.first
        guard let conversation else { return }

        conversation.workingDirectory = session.cwd
        conversation.processManager.sessionId = session.id
        conversation.refreshGitBranch()

        DispatchQueue.global(qos: .userInitiated).async {
            let result = SessionHistory.loadMessages(from: session.filePath)
            DispatchQueue.main.async {
                conversation.messages = result.messages
                conversation.inputTokens = result.inputTokens
                conversation.outputTokens = result.outputTokens
                conversation.cachedTokens = result.cacheReadTokens + result.cacheCreationTokens
                conversation.totalCostUSD = result.costUSD
                conversation.contextPercent = result.contextPercent
                if !result.model.isEmpty {
                    conversation.currentModel = result.model
                }
            }
        }
    }

    @objc private func newThread() {
        activateApp()
        paneState?.newThread()
    }

    @objc private func openPane() {
        activateApp()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first { $0.isKeyWindow || $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(max(Int(interval / 60), 1))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let days = Int(interval / 86400)
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days)d ago" }
        return "\(days / 7)w ago"
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// NSMenuItem action helper
private extension NSMenuItem {
    func performAction() {
        guard let menu else { return }
        let idx = menu.index(of: self)
        menu.performActionForItem(at: idx)
    }
}
