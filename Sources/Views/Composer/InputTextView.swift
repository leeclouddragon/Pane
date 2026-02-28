import SwiftUI
import AppKit

enum SlashNavigateAction {
    case up
    case down
    case confirm
    case dismiss
}

/// NSTextView wrapper with custom cursor color, auto-growing height, and Cmd+Enter to send.
struct InputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var font: NSFont = .systemFont(ofSize: 13)
    var isFocused: Bool = true
    var slashMenuVisible: Bool = false
    var onCommit: () -> Void = {}
    var onImagePaste: ((NSImage) -> Void)?
    var onSlashNavigate: ((SlashNavigateAction) -> Void)?
    var onModeToggle: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = PaneTextView()
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.font = font
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        // Cursor: light gray
        textView.insertionPointColor = NSColor.secondaryLabelColor

        // Left inset = 6 to align cursor with the + button below
        textView.textContainerInset = NSSize(width: 6, height: 2)
        textView.textContainer?.lineFragmentPadding = 0

        // Grow vertically
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        textView.onCommit = onCommit
        context.coordinator.textView = textView

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PaneTextView else { return }

        if textView.string != text {
            textView.string = text
            context.coordinator.recalcHeight()
        }

        textView.onCommit = onCommit
        textView.onModeToggle = onModeToggle
        textView.slashMenuVisible = slashMenuVisible
        // Keep coordinator callbacks fresh
        context.coordinator.parent = self

        // Auto focus only when this pane is the focused one
        if context.coordinator.parent.isFocused {
            DispatchQueue.main.async {
                if let window = textView.window, window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InputTextView
        weak var textView: PaneTextView?

        init(_ parent: InputTextView) {
            self.parent = parent
        }

        func handleImagePaste(_ image: NSImage) {
            parent.onImagePaste?(image)
        }

        func handleSlashNavigate(_ action: SlashNavigateAction) {
            parent.onSlashNavigate?(action)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalcHeight()
        }

        func recalcHeight() {
            guard let textView else { return }
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
            let newHeight = usedRect.height + textView.textContainerInset.height * 2
            let lineHeight = textView.font?.pointSize ?? 14
            let minH = lineHeight + 8  // single line
            let maxH: CGFloat = 160
            let clamped = min(max(newHeight, minH), maxH)
            DispatchQueue.main.async {
                self.parent.height = clamped
            }
        }
    }
}

/// Custom NSTextView: placeholder + Enter to send, Shift+Enter for newline.
class PaneTextView: NSTextView {
    var onCommit: () -> Void = {}
    var onModeToggle: (() -> Void)?
    var slashMenuVisible: Bool = false
    weak var coordinator: InputTextView.Coordinator?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Cmd+V: handle paste (SPM executable has no Edit menu, so paste: is never dispatched)
        // Guard: only handle if this text view is the first responder (prevents cross-pane paste in split mode)
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "v",
           window?.firstResponder == self {
            pasteFromClipboard()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general

        // NSImage(pasteboard:) handles all image types NSImage supports (tiff, png, jpeg, heic, gif, webp, etc.)
        // Only intercept when clipboard has no text — if both exist, prefer text paste.
        if pb.string(forType: .string) == nil,
           let image = NSImage(pasteboard: pb),
           image.isValid {
            coordinator?.handleImagePaste(image)
            return
        }

        // Fall back to text paste
        if let text = pb.string(forType: .string) {
            insertText(text, replacementRange: selectedRange())
        }
    }

    override func keyDown(with event: NSEvent) {
        // When slash menu is visible, intercept navigation keys
        if slashMenuVisible {
            switch event.keyCode {
            case 126: // Up arrow
                coordinator?.handleSlashNavigate(.up)
                return
            case 125: // Down arrow
                coordinator?.handleSlashNavigate(.down)
                return
            case 36: // Enter
                if !hasMarkedText() {
                    coordinator?.handleSlashNavigate(.confirm)
                    return
                }
            case 53: // Escape
                coordinator?.handleSlashNavigate(.dismiss)
                return
            default:
                break
            }
        }

        // Shift+Tab (keyCode 48): cycle interaction mode
        if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
            onModeToggle?()
            return
        }

        // Enter (keyCode 36) without Shift → send
        // Skip if IME is composing (hasMarkedText) — e.g. Chinese pinyin using Enter to confirm
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) && !hasMarkedText() {
            onCommit()
            return
        }
        // Shift+Enter → insert newline (default behavior)
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let placeholder = NSAttributedString(string: "Message...", attributes: attrs)
            placeholder.draw(at: NSPoint(x: textContainerInset.width, y: textContainerInset.height))
        }
    }
}
