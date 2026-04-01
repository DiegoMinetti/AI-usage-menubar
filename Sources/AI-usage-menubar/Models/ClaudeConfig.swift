import Foundation

struct ClaudeConfig: Codable {
    var monthly_token_limit: Int
    /// Optional explicit per-session token limit.
    /// nil → derived from the configured monthly allowance.
    var session_token_limit: Int?
    /// Optional explicit rolling 7-day token limit.
    /// nil → derived from the configured monthly allowance.
    var weekly_token_limit: Int?
    var billing_cycles: [BillingCycle]?

    static func `default`() -> ClaudeConfig {
        ClaudeConfig(monthly_token_limit: 500_000, session_token_limit: nil, weekly_token_limit: nil, billing_cycles: nil)
    }

    /// Daily allowance inferred from the configured monthly budget.
    var dailyTokenLimit: Int { max(monthly_token_limit / 30, 1) }

    /// Session allowance used for the current 5h window.
    var effectiveSessionTokenLimit: Int { max(session_token_limit ?? dailyTokenLimit, 1) }

    /// Rolling 7-day allowance used for weekly usage.
    var effectiveWeeklyTokenLimit: Int { max(weekly_token_limit ?? (monthly_token_limit * 7 / 30), 1) }
}
