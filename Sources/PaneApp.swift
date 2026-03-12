import SwiftUI
import AppKit

@main
struct PaneApp: App {
    @State private var paneState: PaneState
    @State private var settings = AppSettings()
    /// Menu bar status item — must be retained for the lifetime of the app.
    private let menuBarManager = MenuBarManager()
    /// Global quick-input panel — Option+Space to toggle.
    private let quickInputPanel = QuickInputPanel()

    init() {
        // SPM executable needs manual activation to show windows and dock icon
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.applicationIconImage = AppIconArtwork.makeImage()
        NSApplication.shared.activate(ignoringOtherApps: true)

        let provider = ProviderState()
        let ps = PaneState(providerState: provider)
        _paneState = State(initialValue: ps)

        // Register global hotkey immediately — not deferred to .onAppear
        quickInputPanel.setup(paneState: ps)
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(paneState)
                .environment(settings)
                .onAppear {
                    menuBarManager.setup(paneState: paneState)
                    RemoteControlServer.shared.startIfPossible(paneState: paneState)
                }
        }
        .windowToolbarStyle(.unifiedCompact)
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

                Button("Zoom In") {
                    settings.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    settings.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    settings.zoomReset()
                }
                .keyboardShortcut("0", modifiers: .command)

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
            SettingsView(providerState: paneState.providerState)
        }
    }
}
