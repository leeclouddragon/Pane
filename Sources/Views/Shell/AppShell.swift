import SwiftUI

/// Root view. Title bar + conversation (with composer + status bar inside).
struct AppShell: View {
    @Environment(PaneState.self) private var paneState
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            TitleBarView()
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            PaneContainer(node: paneState.root)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
