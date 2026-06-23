import Foundation

struct CodexDailyTokens: Codable, Sendable, Identifiable {
    var id: String { date }
    let date: String
    let tokens: Int
}

struct CodexLimitWindow: Codable, Sendable, Identifiable {
    var id: String { label }
    let label: String
    let windowMinutes: Double
    let usedPercent: Double
    let resetAt: Date?

    var remainingPercent: Double {
        min(max(100 - usedPercent, 0), 100)
    }

    var normalizedLabel: String {
        if abs(windowMinutes - 300) <= 1 { return "5 h" }
        if abs(windowMinutes - 10_080) <= 60 { return "Semanal" }
        if abs(windowMinutes - 43_200) <= 1_440 { return "Mensual" }
        if windowMinutes >= 1_440 { return "\(Int((windowMinutes / 1_440).rounded())) d" }
        if windowMinutes >= 60 { return "\(Int((windowMinutes / 60).rounded())) h" }
        return "\(Int(windowMinutes.rounded())) min"
    }
}

struct CodexMonthlyLimit: Codable, Sendable {
    let used: Double
    let limit: Double
    let resetAt: Date?

    var usedPercent: Double {
        guard limit > 0 else { return 100 }
        return min(max((used / limit) * 100, 0), 100)
    }

    var remainingPercent: Double {
        min(max(100 - usedPercent, 0), 100)
    }

    var remaining: Double {
        max(limit - used, 0)
    }
}

struct ChatGPTCodexUsage: Codable, Sendable {
    let totalTokens: Int
    let monthlyTokens: Int
    let weeklyTokens: Int
    let todayTokens: Int
    let activeThreads: Int
    let archivedThreads: Int
    let lastUpdated: Date?
    let lastModel: String?
    let dailyHistory: [CodexDailyTokens]
    let sourcePath: String
    let limitWindows: [CodexLimitWindow]
    let monthlyLimit: CodexMonthlyLimit?
    let quotaFetchedAt: Date?
    let quotaStatus: String?

    var hasUsageData: Bool { totalTokens > 0 || monthlyTokens > 0 || hasQuotaData }
    var hasQuotaData: Bool { !limitWindows.isEmpty || monthlyLimit != nil }

    var fiveHourWindow: CodexLimitWindow? {
        limitWindows.first { abs($0.windowMinutes - 300) <= 1 }
    }

    var weeklyWindow: CodexLimitWindow? {
        limitWindows.first { abs($0.windowMinutes - 10_080) <= 60 }
    }

    var monthlyWindow: CodexLimitWindow? {
        limitWindows.first { abs($0.windowMinutes - 43_200) <= 1_440 }
    }

    static var empty: ChatGPTCodexUsage {
        ChatGPTCodexUsage(
            totalTokens: 0,
            monthlyTokens: 0,
            weeklyTokens: 0,
            todayTokens: 0,
            activeThreads: 0,
            archivedThreads: 0,
            lastUpdated: nil,
            lastModel: nil,
            dailyHistory: [],
            sourcePath: "~/.codex/state_5.sqlite",
            limitWindows: [],
            monthlyLimit: nil,
            quotaFetchedAt: nil,
            quotaStatus: nil
        )
    }
}
