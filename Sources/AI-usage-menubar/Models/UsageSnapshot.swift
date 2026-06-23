import Foundation

struct UsageSnapshot: Codable, Sendable {
    struct Service: Codable, Sendable, Identifiable {
        let id: String
        let name: String
        let detail: String
        let usedLabel: String
        let percentage: Double?
        let status: String
        let tintHex: String
        let resetLabel: String?
        let usedValue: Double?
        let remainingValue: Double?
        let limitValue: Double?
        let unit: String?
        let periodLabel: String?
        let periodStart: Date?
        let periodEnd: Date?
        let resetAt: Date?
        let updatedAt: Date?

        init(
            id: String,
            name: String,
            detail: String,
            usedLabel: String,
            percentage: Double?,
            status: String,
            tintHex: String,
            resetLabel: String?,
            usedValue: Double? = nil,
            remainingValue: Double? = nil,
            limitValue: Double? = nil,
            unit: String? = nil,
            periodLabel: String? = nil,
            periodStart: Date? = nil,
            periodEnd: Date? = nil,
            resetAt: Date? = nil,
            updatedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.detail = detail
            self.usedLabel = usedLabel
            self.percentage = percentage
            self.status = status
            self.tintHex = tintHex
            self.resetLabel = resetLabel
            self.usedValue = usedValue
            self.remainingValue = remainingValue
            self.limitValue = limitValue
            self.unit = unit
            self.periodLabel = periodLabel
            self.periodStart = periodStart
            self.periodEnd = periodEnd
            self.resetAt = resetAt
            self.updatedAt = updatedAt
        }
    }

    let generatedAt: Date
    let services: [Service]

    static var empty: UsageSnapshot {
        UsageSnapshot(generatedAt: Date(), services: [])
    }
}
