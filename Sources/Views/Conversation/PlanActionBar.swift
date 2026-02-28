import SwiftUI

// MARK: - Plan Mode Banner

/// Shown at the top of the conversation area when plan mode is active.
struct PlanModeBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("‖")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            Text("Plan Mode")
                .font(.system(size: 11, weight: .semibold))
            Text("—")
                .foregroundStyle(.tertiary)
            Text("Read-only exploration & design")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.blue.opacity(0.06))
    }
}

// MARK: - Plan Action Bar

/// Shown above the composer after a plan response completes.
/// Offers quick actions to execute the plan or provide feedback.
struct PlanActionBar: View {
    var onExecute: (InteractionMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ready to code?")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(spacing: 4) {
                actionButton(
                    label: "Execute",
                    detail: "auto-approve edits",
                    icon: "play.fill",
                    mode: .acceptEdits
                )
                actionButton(
                    label: "Execute",
                    detail: "review each edit",
                    icon: "play",
                    mode: .normal
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.blue.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func actionButton(label: String, detail: String, icon: String, mode: InteractionMode) -> some View {
        Button(action: { onExecute(mode) }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.blue.opacity(0.001)) // hit target
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
