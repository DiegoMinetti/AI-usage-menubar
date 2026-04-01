import Foundation

struct ClaudeUsage: Sendable {
    // MARK: - Monthly billing cycle
    let totalTokens: Int
    let monthlyPercentage: Double
    let dailyAverage: Double
    let monthlyLimit: Int
    /// First day of the next billing cycle (= renewal date).
    let monthlyRenewalDate: Date

    // MARK: - 5-hour session window
    let sessionTokens: Int
    /// % of the configured session allowance consumed in the current 5h window.
    let sessionPercentage: Double
    let sessionLimit: Int
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
    let weeklyLimit: Int

    /// Time until the rolling 7-day window refreshes (next midnight).
    var timeUntilWeeklyRefresh: TimeInterval {
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        return max(tomorrow.timeIntervalSinceNow, 0)
    }

    // MARK: - Monthly renewal countdown
    var timeUntilMonthlyReset: TimeInterval {
        max(monthlyRenewalDate.timeIntervalSinceNow, 0)
    }

    var daysUntilMonthlyReset: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let reset = cal.startOfDay(for: monthlyRenewalDate)
        return max(cal.dateComponents([.day], from: today, to: reset).day ?? 0, 0)
    }

    // MARK: - Projection to end of month
    /// Estimated total tokens at end of the current billing cycle,
    /// based on the current daily average.
    var projectedMonthlyTokens: Int {
        guard dailyAverage > 0 else { return totalTokens }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let daysLeft = max(cal.dateComponents([.day], from: today, to: monthlyRenewalDate).day ?? 0, 0)
        return totalTokens + Int(dailyAverage * Double(daysLeft))
    }

    var hasUsageData: Bool { totalTokens > 0 }

    // MARK: - Convenience
    static var empty: ClaudeUsage {
        let cal = Calendar.current
        let renewal = cal.nextDate(after: Date(), matching: DateComponents(day: 1), matchingPolicy: .nextTime) ?? Date()
        return ClaudeUsage(
            totalTokens: 0, monthlyPercentage: 0, dailyAverage: 0, monthlyLimit: 500_000,
            monthlyRenewalDate: renewal,
            sessionTokens: 0, sessionPercentage: 0, sessionLimit: max(500_000 / 30, 1), sessionWindowEnd: nil,
            dailyHistory: [], weeklyTokens: 0, weeklyPercentage: 0, weeklyLimit: max(500_000 * 7 / 30, 1)
        )
    }
}
