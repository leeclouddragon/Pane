import SwiftUI

/// Settings panel for managing provider API keys.
/// Opened via Cmd+, (macOS Settings scene).
struct SettingsView: View {
    let providerState: ProviderState
    @State private var config: PaneConfig
    @State private var saved = false

    init(providerState: ProviderState) {
        self.providerState = providerState
        _config = State(initialValue: providerState.configManager.load())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Providers")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    providerSection("Cloud", category: .cloud)
                    providerSection("Bedrock", category: .bedrock)
                    providerSection("Local", category: .local)
                    providerSection("Native", category: .native)
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                if saved {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Save") {
                    providerState.configManager.save(config)
                    providerState.discover()
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        saved = false
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 480)
    }

    @ViewBuilder
    private func providerSection(_ title: String, category: ProviderEntry.Category) -> some View {
        let entries = config.providers.filter { $0.category == category }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ForEach(entries) { entry in
                    providerRow(entry)
                }
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ entry: ProviderEntry) -> some View {
        if let idx = config.providers.firstIndex(where: { $0.id == entry.id }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.displayName)
                        .font(.system(size: 13, weight: .medium))

                    if let model = entry.env?["ANTHROPIC_MODEL"] ?? entry.env?["CLAUDE_MODEL_ID"] {
                        Text(model)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    // Status indicator
                    Circle()
                        .fill(providerState.isAvailable(entry) ? .green : .gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }

                switch entry.category {
                case .cloud:
                    SecureField("API Key", text: binding(for: idx))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                case .bedrock:
                    HStack(spacing: 8) {
                        TextField("AWS Profile", text: envBinding(for: idx, key: "AWS_PROFILE"))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        TextField("Region", text: envBinding(for: idx, key: "AWS_REGION"))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 120)
                    }

                case .local:
                    if let port = entry.localPort {
                        Text("localhost:\(port)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                case .native:
                    Text("Uses claude CLI's built-in authentication")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Binding for cloud provider API key.
    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { config.providers[index].apiKey ?? "" },
            set: { config.providers[index].apiKey = $0.isEmpty ? nil : $0 }
        )
    }

    /// Binding for an env var value within a provider.
    private func envBinding(for index: Int, key: String) -> Binding<String> {
        Binding(
            get: { config.providers[index].env?[key] ?? "" },
            set: { newValue in
                if config.providers[index].env == nil {
                    config.providers[index].env = [:]
                }
                config.providers[index].env?[key] = newValue.isEmpty ? nil : newValue
            }
        )
    }
}
