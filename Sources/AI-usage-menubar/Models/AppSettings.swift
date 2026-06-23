import Foundation

enum UsageProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case copilot
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .copilot: return "GitHub Copilot"
        case .codex: return "ChatGPT / Codex"
        }
    }

    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .copilot: return "Copilot"
        case .codex: return "Codex"
        }
    }
}

struct AppSettings: Codable, Sendable {
    var visibleProviders: [UsageProviderID]
    var menuBarProviders: [UsageProviderID]
    var autoUpdateFromMain: Bool

    static var `default`: AppSettings {
        AppSettings(
            visibleProviders: UsageProviderID.allCases,
            menuBarProviders: [.claude, .copilot],
            autoUpdateFromMain: false
        )
    }

    func showsProvider(_ provider: UsageProviderID) -> Bool {
        visibleProviders.contains(provider)
    }

    func showsProviderInMenuBar(_ provider: UsageProviderID) -> Bool {
        menuBarProviders.contains(provider)
    }
}
