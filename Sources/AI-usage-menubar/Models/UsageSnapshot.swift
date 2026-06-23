import Foundation

struct UsageSnapshot: Codable, Sendable {
    struct ChartPoint: Codable, Sendable, Identifiable {
        var id: String { label }
        let label: String
        let value: Double
        let projected: Bool

        init(label: String, value: Double, projected: Bool = false) {
            self.label = label
            self.value = value
            self.projected = projected
        }
    }

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
        let chartPoints: [ChartPoint]

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case detail
            case usedLabel
            case percentage
            case status
            case tintHex
            case resetLabel
            case usedValue
            case remainingValue
            case limitValue
            case unit
            case periodLabel
            case periodStart
            case periodEnd
            case resetAt
            case updatedAt
            case chartPoints
        }

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
            updatedAt: Date? = nil,
            chartPoints: [ChartPoint] = []
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
            self.chartPoints = chartPoints
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            detail = try container.decode(String.self, forKey: .detail)
            usedLabel = try container.decode(String.self, forKey: .usedLabel)
            percentage = try container.decodeIfPresent(Double.self, forKey: .percentage)
            status = try container.decode(String.self, forKey: .status)
            tintHex = try container.decode(String.self, forKey: .tintHex)
            resetLabel = try container.decodeIfPresent(String.self, forKey: .resetLabel)
            usedValue = try container.decodeIfPresent(Double.self, forKey: .usedValue)
            remainingValue = try container.decodeIfPresent(Double.self, forKey: .remainingValue)
            limitValue = try container.decodeIfPresent(Double.self, forKey: .limitValue)
            unit = try container.decodeIfPresent(String.self, forKey: .unit)
            periodLabel = try container.decodeIfPresent(String.self, forKey: .periodLabel)
            periodStart = try container.decodeIfPresent(Date.self, forKey: .periodStart)
            periodEnd = try container.decodeIfPresent(Date.self, forKey: .periodEnd)
            resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            chartPoints = try container.decodeIfPresent([ChartPoint].self, forKey: .chartPoints) ?? []
        }
    }

    let generatedAt: Date
    let services: [Service]

    static var empty: UsageSnapshot {
        UsageSnapshot(generatedAt: Date(), services: [])
    }
}
