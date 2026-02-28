import SwiftUI

struct ComposeIconView: View {
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: size * 0.8, weight: .medium))
            .frame(width: size, height: size)
    }
}

struct ClockIconView: View {
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: "clock")
            .font(.system(size: size * 0.8, weight: .medium))
            .frame(width: size, height: size)
    }
}

#Preview("Icons") {
    HStack(spacing: 24) {
        VStack(spacing: 8) {
            ComposeIconView(size: 32)
            Text("Compose").font(.caption)
        }
        VStack(spacing: 8) {
            ClockIconView(size: 32)
            Text("Recent").font(.caption)
        }
    }
    .foregroundStyle(.secondary)
    .padding(40)
}
