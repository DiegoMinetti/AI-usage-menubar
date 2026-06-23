import Foundation

enum UsageProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case copilot
    case codex
    case minimax

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .copilot: return "GitHub Copilot"
        case .codex: return "ChatGPT / Codex"
        case .minimax: return "MiniMax"
        }
    }

    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .copilot: return "Copilot"
        case .codex: return "Codex"
        case .minimax: return "MiniMax"
        }
    }
}

enum PercentageDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case used
    case remaining

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .used: return "Used"
        case .remaining: return "Remaining"
        }
    }
}

enum QuotaPeriodDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fiveHour
    case weekly
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fiveHour: return "5 hours"
        case .weekly: return "Weekly"
        case .both: return "Both"
        }
    }
}

struct AppSettings: Codable, Sendable {
    var providerOrder: [UsageProviderID]
    var visibleProviders: [UsageProviderID]
    var menuBarProviders: [UsageProviderID]
    var widgetProviders: [UsageProviderID]
    var chartProviders: [UsageProviderID]
    var percentageDisplayMode: PercentageDisplayMode
    var quotaPeriodDisplayMode: QuotaPeriodDisplayMode
    var autoUpdateFromMain: Bool

    enum CodingKeys: String, CodingKey {
        case providerOrder
        case visibleProviders
        case menuBarProviders
        case widgetProviders
        case chartProviders
        case percentageDisplayMode
        case quotaPeriodDisplayMode
        case autoUpdateFromMain
    }

    static var `default`: AppSettings {
        AppSettings(
            providerOrder: UsageProviderID.allCases,
            visibleProviders: UsageProviderID.allCases,
            menuBarProviders: [.claude, .copilot],
            widgetProviders: UsageProviderID.allCases,
            chartProviders: UsageProviderID.allCases,
            percentageDisplayMode: .used,
            quotaPeriodDisplayMode: .fiveHour,
            autoUpdateFromMain: false
        )
    }

    init(
        providerOrder: [UsageProviderID],
        visibleProviders: [UsageProviderID],
        menuBarProviders: [UsageProviderID],
        widgetProviders: [UsageProviderID],
        chartProviders: [UsageProviderID],
        percentageDisplayMode: PercentageDisplayMode,
        quotaPeriodDisplayMode: QuotaPeriodDisplayMode,
        autoUpdateFromMain: Bool
    ) {
        self.providerOrder = Self.normalizedOrder(providerOrder)
        self.visibleProviders = Self.normalizedProviders(visibleProviders)
        self.menuBarProviders = Self.normalizedProviders(menuBarProviders)
        self.widgetProviders = Self.normalizedProviders(widgetProviders)
        self.chartProviders = Self.normalizedProviders(chartProviders)
        self.percentageDisplayMode = percentageDisplayMode
        self.quotaPeriodDisplayMode = quotaPeriodDisplayMode
        self.autoUpdateFromMain = autoUpdateFromMain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasSettingsPayload = container.contains(.providerOrder)
            || container.contains(.visibleProviders)
            || container.contains(.menuBarProviders)
            || container.contains(.widgetProviders)
            || container.contains(.chartProviders)
            || container.contains(.percentageDisplayMode)
            || container.contains(.quotaPeriodDisplayMode)
            || container.contains(.autoUpdateFromMain)

        guard hasSettingsPayload else {
            throw DecodingError.dataCorruptedError(
                forKey: .visibleProviders,
                in: container,
                debugDescription: "App settings file does not contain settings keys."
            )
        }

        visibleProviders = Self.normalizedProviders(try container.decodeIfPresent([UsageProviderID].self, forKey: .visibleProviders) ?? UsageProviderID.allCases)
        menuBarProviders = Self.normalizedProviders(try container.decodeIfPresent([UsageProviderID].self, forKey: .menuBarProviders) ?? [.claude, .copilot])
        widgetProviders = Self.normalizedProviders(try container.decodeIfPresent([UsageProviderID].self, forKey: .widgetProviders) ?? visibleProviders)
        chartProviders = Self.normalizedProviders(try container.decodeIfPresent([UsageProviderID].self, forKey: .chartProviders) ?? visibleProviders)
        let migratedOrder = try container.decodeIfPresent([UsageProviderID].self, forKey: .providerOrder) ?? chartProviders
        providerOrder = Self.normalizedOrder(migratedOrder)
        percentageDisplayMode = try container.decodeIfPresent(PercentageDisplayMode.self, forKey: .percentageDisplayMode) ?? .used
        quotaPeriodDisplayMode = try container.decodeIfPresent(QuotaPeriodDisplayMode.self, forKey: .quotaPeriodDisplayMode) ?? .fiveHour
        autoUpdateFromMain = try container.decodeIfPresent(Bool.self, forKey: .autoUpdateFromMain) ?? false
    }

    func showsProvider(_ provider: UsageProviderID) -> Bool {
        visibleProviders.contains(provider)
    }

    func showsProviderInMenuBar(_ provider: UsageProviderID) -> Bool {
        menuBarProviders.contains(provider)
    }

    func showsProviderInWidget(_ provider: UsageProviderID) -> Bool {
        widgetProviders.contains(provider)
    }

    func showsProviderChart(_ provider: UsageProviderID) -> Bool {
        chartProviders.contains(provider)
    }

    func orderedProviders(matching providers: [UsageProviderID]) -> [UsageProviderID] {
        providerOrder.filter { providers.contains($0) }
    }

    var orderedVisibleProviders: [UsageProviderID] {
        orderedProviders(matching: visibleProviders)
    }

    var orderedMenuBarProviders: [UsageProviderID] {
        orderedProviders(matching: menuBarProviders)
    }

    var orderedWidgetProviders: [UsageProviderID] {
        orderedProviders(matching: widgetProviders)
    }

    var orderedChartProviders: [UsageProviderID] {
        orderedProviders(matching: chartProviders)
    }

    private static func normalizedOrder(_ providers: [UsageProviderID]) -> [UsageProviderID] {
        normalizedProviders(providers) + UsageProviderID.allCases.filter { !providers.contains($0) }
    }

    private static func normalizedProviders(_ providers: [UsageProviderID]) -> [UsageProviderID] {
        var result: [UsageProviderID] = []
        for provider in providers where !result.contains(provider) {
            result.append(provider)
        }
        return result.filter { UsageProviderID.allCases.contains($0) }
    }
}
