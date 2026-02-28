import SwiftUI

/// Floating panel above the composer for AskUserQuestion responses.
/// Modeled after Cursor's question panel: questions with lettered options,
/// Skip/Continue actions.
struct QuestionPanel: View {
    @Bindable var conversation: ConversationState

    @State private var selectedAnswers: [String: String] = [:]  // question text → selected label

    var body: some View {
        guard let pq = conversation.pendingQuestion else { return AnyView(EmptyView()) }
        return AnyView(panelContent(pq))
    }

    private func panelContent(_ pq: PendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Questions
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(pq.questions.enumerated()), id: \.offset) { qIdx, q in
                        questionSection(qIdx: qIdx, item: q)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 300)

            Divider()

            // Actions: Skip / Continue
            HStack {
                Spacer()
                Button(action: { conversation.skipQuestion() }) {
                    HStack(spacing: 4) {
                        Text("Skip")
                            .font(.system(size: 12))
                        Text("Esc")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)

                Button(action: { submitAnswers() }) {
                    HStack(spacing: 4) {
                        Text("Continue")
                            .font(.system(size: 12, weight: .medium))
                        Text("↵")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func questionSection(qIdx: Int, item: PendingQuestion.QuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Question number + header + text
            HStack(spacing: 6) {
                Text("\(qIdx + 1).")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if !item.header.isEmpty {
                    Text(item.header)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            Text(item.question)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            if item.multiSelect {
                Text("(可多选)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            // Options
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(item.options.enumerated()), id: \.offset) { optIdx, opt in
                    optionRow(
                        letter: String(UnicodeScalar(65 + optIdx)!),  // A, B, C, D...
                        option: opt,
                        isSelected: selectedAnswers[item.question] == opt.label,
                        action: { selectedAnswers[item.question] = opt.label }
                    )
                }
                // "Other..." option
                optionRow(
                    letter: String(UnicodeScalar(65 + item.options.count)!),
                    option: PendingQuestion.OptionItem(label: "Other...", description: ""),
                    isSelected: selectedAnswers[item.question] == "Other...",
                    action: { selectedAnswers[item.question] = "Other..." }
                )
            }
        }
    }

    private func optionRow(
        letter: String,
        option: PendingQuestion.OptionItem,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(letter)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 20, height: 20)
                    .background(isSelected ? Color.accentColor : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.separator), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func submitAnswers() {
        conversation.answerQuestion(answers: selectedAnswers)
        selectedAnswers = [:]
    }
}
