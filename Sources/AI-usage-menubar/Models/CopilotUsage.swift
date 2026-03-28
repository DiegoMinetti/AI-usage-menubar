import Foundation

/// Persisted Copilot usage (current % + reset date).
/// Computed fields (projection, days remaining) are derived at runtime.
public struct CopilotUsage: Codable, Sendable {
    public let percentage: Double
    public let resetDate: Date

    // MARK: - Computed (always fresh, not cached)

    /// Days remaining until the allowance resets.
    public var daysRemaining: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let reset = cal.startOfDay(for: resetDate)
        return max(cal.dateComponents([.day], from: today, to: reset).day ?? 0, 0)
    }

    /// Days elapsed since the start of the current cycle.
    /// Uses the reset date to estimate a 30-day cycle start.
    public var daysElapsed: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let reset = cal.startOfDay(for: resetDate)
        // Estimate cycle start as (reset − 30 days), then clamp to at least 1.
        let estimatedStart = cal.date(byAdding: .day, value: -30, to: reset) ?? reset
        return max(cal.dateComponents([.day], from: estimatedStart, to: today).day ?? 0, 1)
    }

    /// Total days in the estimated cycle.
    public var daysInCycle: Int { daysElapsed + daysRemaining }

    /// Whether there's enough history to make a meaningful projection
    /// (at least 3 days into the cycle).
    public var hasProjectionData: Bool { daysElapsed >= 3 }

    /// Estimated total % consumed by the end of the current cycle,
    /// based on the current burn rate. Returns nil if not enough data.
    public var projectedEndPercentage: Double? {
        guard hasProjectionData, daysElapsed > 0 else { return nil }
        let dailyRate = percentage / Double(daysElapsed)
        let projected = dailyRate * Double(daysInCycle)
        // Cap display at 300 to keep it legible
        return min((projected * 10).rounded() / 10, 300.0)
    }

    /// Synthetic daily data points for the current cycle (actual + projected),
    /// suitable for rendering a cumulative area/line chart.
    public func monthlySeries() -> [CopilotDataPoint] {
        guard daysInCycle > 0 else { return [] }
        let dailyRate = daysElapsed > 0 ? percentage / Double(daysElapsed) : 0

        var points: [CopilotDataPoint] = []
        var cumulative = 0.0
        for day in 1...max(daysInCycle, 1) {
            let isProjected = day > daysElapsed
            if !isProjected { cumulative += dailyRate }
            else             { cumulative += dailyRate }  // uniform projection
            points.append(CopilotDataPoint(day: day, cumPct: cumulative, isProjected: isProjected))
        }
        return points
    }
}

public struct CopilotDataPoint: Sendable {
    public let day: Int
    public let cumPct: Double   // cumulative %
    public let isProjected: Bool
}
