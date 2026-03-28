import Foundation

struct ClaudeUsage: Sendable {
    // MARK: - Monthly billing cycle
    let totalTokens: Int
    let monthlyPercentage: Double
    let dailyAverage: Double
    let monthlyLimit: Int

    // MARK: - 5-hour session window
    let sessionTokens: Int
    /// % of daily quota (monthly/30) consumed this session. Can exceed 100.
    let sessionPercentage: Double
    /// When the current 5h window closes. nil = no active session.
    let sessionWindowEnd: Date?

    var isInActiveSession: Bool { sessionWindowEnd != nil }

    var timeRemainingInSession: TimeInterval? {
        guard let end = sessionWindowEnd else { return nil }
        return max(end.timeIntervalSinceNow, 0)
    }

    // MARK: - Daily history (last 30 days, ascending)
    /// Used for the monthly cumulative chart and the weekly bar chart.
    let dailyHistory: [DailyTokens]

    var last7Days: [DailyTokens] { Array(dailyHistory.suffix(7)) }

    // MARK: - Weekly stats
    let weeklyTokens: Int
    let weeklyPercentage: Double

    // MARK: - Projection to end of month
    /// Estimated total tokens at end of the current billing cycle,
    /// based on the current daily average.
    var projectedMonthlyTokens: Int {
        guard dailyAverage > 0 else { return totalTokens }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Days remaining in current calendar month
        let startOfNextMonth = cal.nextDate(
            after: today,
            matching: DateComponents(day: 1),
            matchingPolicy: .nextTime
        ) ?? today
        let daysLeft = max(cal.dateComponents([.day], from: today, to: startOfNextMonth).day ?? 0, 0)
        return totalTokens + Int(dailyAverage * Double(daysLeft))
    }

    var hasUsageData: Bool { totalTokens > 0 }

    // MARK: - Convenience
    static var empty: ClaudeUsage {
        ClaudeUsage(
            totalTokens: 0, monthlyPercentage: 0, dailyAverage: 0, monthlyLimit: 500_000,
            sessionTokens: 0, sessionPercentage: 0, sessionWindowEnd: nil,
            dailyHistory: [], weeklyTokens: 0, weeklyPercentage: 0
        )
    }
}
