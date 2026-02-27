import SwiftUI
import AppKit

@main
struct PaneApp: App {
    @State private var paneState: PaneState
    @State private var settings = AppSettings()

    init() {
        // SPM executable needs manual activation to show windows and dock icon
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let provider = ProviderState()
        _paneState = State(initialValue: PaneState(providerState: provider))
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(paneState)
                .environment(settings)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Thread") {
                    // TODO: new thread
                }
                .keyboardShortcut("n")
            }
            CommandMenu("View") {
                Button("Cycle Width Mode") {
                    settings.widthMode = settings.widthMode.next()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Divider()

                Button("Split Right") {
                    // TODO: split horizontal
                }
                .keyboardShortcut("d")

                Button("Split Down") {
                    // TODO: split vertical
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            Text("Settings")
                .frame(width: 400, height: 300)
        }
    }
}
