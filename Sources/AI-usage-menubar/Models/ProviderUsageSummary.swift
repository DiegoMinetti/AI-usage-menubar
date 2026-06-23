import Foundation

struct ProviderUsageSummary: Identifiable, Sendable {
    enum Unit: String, Sendable {
        case tokens
        case percent
        case credits
        case requests
    }

    let id: UsageProviderID
    let name: String
    let status: String
    let used: Double?
    let remaining: Double?
    let limit: Double?
    let unit: Unit
    let periodLabel: String
    let periodStart: Date?
    let periodEnd: Date?
    let resetDate: Date?
    let updatedAt: Date?
    let percentageUsed: Double?

    var hasLimit: Bool { limit != nil }
}
