import SwiftUI
import AppKit

/// Composer: single bordered container with text input + toolbar inside.
/// In welcome mode, toolbar shows folder/provider selectors.
struct ComposerView: View {
    @Bindable var conversation: ConversationState
    var isWelcome: Bool = false

    @State private var attachments: [AttachmentItem] = []
    @State private var textHeight: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Attachments (above text input, like ChatGPT)
            if !attachments.isEmpty {
                AttachmentBar(attachments: $attachments)
                    .padding(.bottom, 6)
            }

            // Text input (auto-growing)
            InputTextView(
                text: $conversation.draftText,
                height: $textHeight,
                onCommit: sendMessage,
                onImagePaste: handleImagePaste
            )
            .frame(height: textHeight)

            // Toolbar
            HStack(spacing: 6) {
                Button(action: { /* TODO: attachment picker */ }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach files")

                if isWelcome {
                    // Folder selector (welcome only)
                    Button(action: pickFolder) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text(shortPath(conversation.workingDirectory))
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Choose working directory")
                }

                // Provider selector (always visible)
                if let ps = conversation.providerState, !ps.providers.isEmpty {
                    Menu {
                        ForEach(ps.providers) { provider in
                            Button(provider.id) {
                                ps.activeProviderID = provider.id
                            }
                        }
                    } label: {
                        Text(ps.activeProviderID)
                            .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                Spacer()

                if conversation.isStreaming {
                    Button(action: { conversation.stop() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(canSend ? .secondary : .quaternary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
        )
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            let hasContent = providers.contains {
                $0.hasItemConformingToTypeIdentifier("public.file-url")
                || $0.canLoadObject(ofClass: NSImage.self)
            }
            if hasContent { handleDrop(providers) }
            return hasContent
        }
    }

    private var canSend: Bool {
        !conversation.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !attachments.isEmpty
    }

    private func sendMessage() {
        let text = conversation.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        let urls = attachments.map(\.url)
        conversation.send(text, attachments: urls)
        attachments.removeAll()
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: conversation.workingDirectory)
        panel.prompt = "Select"
        panel.message = "Choose working directory"
        if panel.runModal() == .OK, let url = panel.url {
            conversation.workingDirectory = url.path
            conversation.refreshGitBranch()
        }
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            let relative = String(path.dropFirst(home.count))
            // Show last 2 components max
            let parts = relative.split(separator: "/").suffix(2)
            if parts.count < relative.split(separator: "/").count {
                return "~/.." + "/" + parts.joined(separator: "/")
            }
            return "~" + relative
        }
        return path
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            // Try file URL first (e.g. dragging a file from Finder)
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url") { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                    else { return }
                    DispatchQueue.main.async {
                        self.attachments.append(AttachmentItem(url: url))
                    }
                }
            // Fall back to raw image data (e.g. dragging from browser/Preview)
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    DispatchQueue.main.async {
                        self.handleImagePaste(image)
                    }
                }
            }
        }
    }

    private func handleImagePaste(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return }

        let filename = "pane_paste_\(UUID().uuidString.prefix(8)).png"
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)

        do {
            try pngData.write(to: tmpURL)
            attachments.append(AttachmentItem(url: tmpURL))
        } catch {
            // Silently ignore write failures
        }
    }
}

// MARK: - Attachments

struct AttachmentItem: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "webp"].contains(url.pathExtension.lowercased())
    }
}

struct AttachmentBar: View {
    @Binding var attachments: [AttachmentItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { item in
                    attachmentChip(item)
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentChip(_ item: AttachmentItem) -> some View {
        if item.isImage, let nsImage = NSImage(contentsOf: item.url) {
            // Image attachment: thumbnail with remove button, click to preview
            ZStack(alignment: .topTrailing) {
                Button(action: { NSWorkspace.shared.open(item.url) }) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button(action: { attachments.removeAll { $0.id == item.id } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
        } else {
            // Non-image attachment: icon + filename
            HStack(spacing: 4) {
                Image(systemName: "doc")
                    .font(.system(size: 10))
                Text(item.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Button(action: { attachments.removeAll { $0.id == item.id } }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
