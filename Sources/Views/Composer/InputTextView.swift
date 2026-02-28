import SwiftUI
import AppKit

/// NSTextView wrapper with custom cursor color, auto-growing height, and Cmd+Enter to send.
struct InputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var font: NSFont = .systemFont(ofSize: 14)
    var onCommit: () -> Void = {}
    var onImagePaste: ((NSImage) -> Void)?

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
        textView.onImagePaste = onImagePaste
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
        textView.onImagePaste = onImagePaste

        // Auto focus
        DispatchQueue.main.async {
            if let window = textView.window, window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InputTextView
        weak var textView: PaneTextView?

        init(_ parent: InputTextView) {
            self.parent = parent
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
    var onImagePaste: ((NSImage) -> Void)?

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general

        // Explicitly check for image pasteboard types
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        if let bestType = pb.availableType(from: imageTypes),
           let data = pb.data(forType: bestType),
           let image = NSImage(data: data),
           image.isValid {
            onImagePaste?(image)
            return
        }

        super.paste(sender)
    }

    override func keyDown(with event: NSEvent) {
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
                .font: font ?? NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let placeholder = NSAttributedString(string: "Message...", attributes: attrs)
            placeholder.draw(at: NSPoint(x: textContainerInset.width, y: textContainerInset.height))
        }
    }
}
