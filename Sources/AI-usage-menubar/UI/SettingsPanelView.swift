import SwiftUI

struct SettingsPanelView: View {
    @ObservedObject var vm: MenuViewModel
    @State private var miniMaxAPIKey = ""
    @State private var miniMaxSaveStatus: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Control what appears in the menu panel, menu bar, widget snapshot, and update behavior.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                ForEach(vm.settings.providerOrder) { provider in
                    ProviderSettingsBlock(provider: provider, vm: vm)
                }

                SettingsGroup(title: "Charts") {
                    Text("Open the Charts tab to choose which graphs appear and change their order.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Button("Configure charts") {
                        vm.onOpenChartSettingsWindow?()
                    }
                }

                SettingsGroup(title: "MiniMax credentials") {
                    HStack {
                        SecureField("Token Plan API key", text: $miniMaxAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            if vm.saveMiniMaxAPIKey(miniMaxAPIKey) {
                                miniMaxAPIKey = ""
                                miniMaxSaveStatus = "MiniMax key saved."
                            } else {
                                miniMaxSaveStatus = "Could not save MiniMax key."
                            }
                        }
                        Button("Clear") {
                            if vm.clearMiniMaxAPIKey() {
                                miniMaxAPIKey = ""
                                miniMaxSaveStatus = "MiniMax key removed."
                            } else {
                                miniMaxSaveStatus = "Could not remove MiniMax key."
                            }
                        }
                    }

                    HStack {
                        Circle()
                            .fill(vm.isMiniMaxConfigured ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                        Text(vm.isMiniMaxConfigured ? "Configured in Keychain" : "No key configured")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button("Refresh MiniMax") { vm.onRefresh?() }
                    }

                    Text("Use the MiniMax Token Plan key. The app calls https://www.minimax.io/v1/token_plan/remains and stores the key in macOS Keychain.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let miniMaxSaveStatus {
                        Text(miniMaxSaveStatus)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                SettingsGroup(title: "Global updates") {
                    Picker("Primary quota period", selection: Binding(
                        get: { vm.settings.quotaPeriodDisplayMode },
                        set: { vm.setQuotaPeriodDisplayMode($0) }
                    )) {
                        ForEach(QuotaPeriodDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Percentage display", selection: Binding(
                        get: { vm.settings.percentageDisplayMode },
                        set: { vm.setPercentageDisplayMode($0) }
                    )) {
                        ForEach(PercentageDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Automatically update from main", isOn: Binding(
                        get: { vm.settings.autoUpdateFromMain },
                        set: { vm.setAutoUpdateFromMain($0) }
                    ))
                    Text("The app checks the remote main branch SHA and installs only when a new commit is available. Public distribution still needs Developer ID signing and notarization.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
        }
    }
}

private struct ProviderSettingsBlock: View {
    let provider: UsageProviderID
    @ObservedObject var vm: MenuViewModel

    var body: some View {
        SettingsGroup(title: provider.displayName) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Toggle("Show in menu panel", isOn: Binding(
                        get: { vm.settings.showsProvider(provider) },
                        set: { vm.setProvider(provider, visible: $0) }
                    ))
                    Toggle("Show in menu bar", isOn: Binding(
                        get: { vm.settings.showsProviderInMenuBar(provider) },
                        set: { vm.setMenuBarProvider(provider, visible: $0) }
                    ))
                }
                GridRow {
                    Toggle("Show in widgets", isOn: Binding(
                        get: { vm.settings.showsProviderInWidget(provider) },
                        set: { vm.setWidgetProvider(provider, visible: $0) }
                    ))
                    Text("Affects the desktop widget and native WidgetKit snapshot.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            providerHelp
        }
    }

    @ViewBuilder
    private var providerHelp: some View {
        switch provider {
        case .claude:
            Text("Claude reads local Claude Code JSONL usage and configured token limits.")
        case .copilot:
            Text("Copilot reads the local quota API when available, otherwise the GitHub settings session.")
        case .codex:
            Text("Codex reads local thread history and quota data from the Codex/ChatGPT session when available.")
        case .minimax:
            Text("MiniMax reads Token Plan quota remaining from the official remains endpoint using your Keychain-stored API key.")
        }
    }
}

struct CompactSettingsPanelView: View {
    @ObservedObject var vm: MenuViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Settings")
                .font(.system(size: 17, weight: .semibold))

            SettingsGroup(title: "Menu panel") {
                ForEach(vm.settings.providerOrder) { provider in
                    Toggle(provider.displayName, isOn: Binding(
                        get: { vm.settings.showsProvider(provider) },
                        set: { vm.setProvider(provider, visible: $0) }
                    ))
                }
            }

            SettingsGroup(title: "Menu bar") {
                ForEach(vm.settings.providerOrder) { provider in
                    Toggle(provider.displayName, isOn: Binding(
                        get: { vm.settings.showsProviderInMenuBar(provider) },
                        set: { vm.setMenuBarProvider(provider, visible: $0) }
                    ))
                }
                Text("If none are selected, the menu bar shows only the app icon.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            SettingsGroup(title: "Widgets") {
                ForEach(vm.settings.providerOrder) { provider in
                    Toggle(provider.displayName, isOn: Binding(
                        get: { vm.settings.showsProviderInWidget(provider) },
                        set: { vm.setWidgetProvider(provider, visible: $0) }
                    ))
                }
            }

            SettingsGroup(title: "Updates") {
                Picker("Quota period", selection: Binding(
                    get: { vm.settings.quotaPeriodDisplayMode },
                    set: { vm.setQuotaPeriodDisplayMode($0) }
                )) {
                    ForEach(QuotaPeriodDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Percentages", selection: Binding(
                    get: { vm.settings.percentageDisplayMode },
                    set: { vm.setPercentageDisplayMode($0) }
                )) {
                    ForEach(PercentageDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Automatically update from main", isOn: Binding(
                    get: { vm.settings.autoUpdateFromMain },
                    set: { vm.setAutoUpdateFromMain($0) }
                ))
                Text("Uses the repository main branch installer. Signed and notarized releases still require Apple credentials.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 310)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(.secondary)
            content
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}
