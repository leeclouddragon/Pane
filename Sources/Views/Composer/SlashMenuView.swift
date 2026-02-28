import SwiftUI

/// Floating slash command menu that appears above the composer.
struct SlashMenuView: View {
    let commands: [SlashCommand]
    let selectedIndex: Int
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search hint header
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("Search")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 8)

            // Command list
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                            SlashMenuRow(
                                command: command,
                                isSelected: index == selectedIndex
                            )
                            .id(command.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(command) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
                .onChange(of: selectedIndex) { _, newIndex in
                    guard newIndex >= 0, newIndex < commands.count else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(commands[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
    }
}

private struct SlashMenuRow: View {
    let command: SlashCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: command.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 20, alignment: .center)

            Text(command.name)
                .font(.system(size: 12, weight: .medium))

            Text(command.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(Rectangle())
    }
}
