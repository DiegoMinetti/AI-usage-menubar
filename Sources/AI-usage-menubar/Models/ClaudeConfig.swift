import Foundation

struct ClaudeConfig: Codable {
    var monthly_token_limit: Int
    /// Optional explicit per-session token limit.
    /// nil → derived as monthly / 90 (≈ 3 sessions/day × 30 days).
    var session_token_limit: Int?
    var billing_cycles: [BillingCycle]?

    static func `default`() -> ClaudeConfig {
        ClaudeConfig(monthly_token_limit: 500_000, session_token_limit: nil, billing_cycles: nil)
    }

    /// Token limit used to compute session percentage (vs daily quota).
    var dailyTokenLimit: Int { max(monthly_token_limit / 30, 1) }
}
