import SwiftUI

struct SettingsPanelView: View {
    @ObservedObject var vm: MenuViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))

            SettingsGroup(title: "Menu panel") {
                ForEach(UsageProviderID.allCases) { provider in
                    Toggle(provider.displayName, isOn: Binding(
                        get: { vm.settings.showsProvider(provider) },
                        set: { vm.setProvider(provider, visible: $0) }
                    ))
                }
            }

            SettingsGroup(title: "Menu bar") {
                ForEach(UsageProviderID.allCases) { provider in
                    Toggle(provider.displayName, isOn: Binding(
                        get: { vm.settings.showsProviderInMenuBar(provider) },
                        set: { vm.setMenuBarProvider(provider, visible: $0) }
                    ))
                }
                Text("If none are selected, the menu bar shows only the app icon.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            SettingsGroup(title: "Updates") {
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

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(.secondary)
            content
        }
    }
}
