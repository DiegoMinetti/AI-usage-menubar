import Foundation

struct BillingCycle: Codable {
    var id: String
    var name: String?
    // dates stored as yyyy-MM-dd
    var startDate: String
    var endDate: String

    func startDateObject() -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: startDate)
    }

    func endDateObject() -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: endDate)
    }
}
