import Foundation

struct MiniMaxLimitWindow: Codable, Sendable, Identifiable {
    var id: String { "\(modelName)-\(periodLabel)" }
    let modelName: String
    let periodLabel: String
    let used: Double?
    let remaining: Double?
    let limit: Double?
    let usedPercent: Double?
    let remainingPercent: Double?
    let resetAt: Date?

    var displayRemainingPercent: Double? {
        if let remainingPercent { return min(max(remainingPercent, 0), 100) }
        guard let remaining, let limit, limit > 0 else { return nil }
        return min(max((remaining / limit) * 100, 0), 100)
    }

    var displayUsedPercent: Double? {
        if let usedPercent { return min(max(usedPercent, 0), 100) }
        if let displayRemainingPercent { return min(max(100 - displayRemainingPercent, 0), 100) }
        guard let used, let limit, limit > 0 else { return nil }
        return min(max((used / limit) * 100, 0), 100)
    }
}

struct MiniMaxUsage: Codable, Sendable {
    let windows: [MiniMaxLimitWindow]
    let fetchedAt: Date?
    let status: String
    let errorMessage: String?
    let sourceURL: String

    var hasAPIKey: Bool { MiniMaxUsageService.hasAPIKey }
    var hasUsageData: Bool { !windows.isEmpty }

    var primaryWindow: MiniMaxLimitWindow? {
        windows.first(where: { $0.periodLabel.lowercased().contains("weekly") })
            ?? windows.first(where: { $0.periodLabel.lowercased().contains("5") })
            ?? windows.first
    }

    static var empty: MiniMaxUsage {
        MiniMaxUsage(
            windows: [],
            fetchedAt: nil,
            status: MiniMaxUsageService.hasAPIKey ? "Configured" : "Not configured",
            errorMessage: nil,
            sourceURL: MiniMaxUsageService.defaultEndpoint
        )
    }
}
