import Foundation

struct DailyTokens: Identifiable, Hashable, Sendable {
    var id: String { date }
    let date: String   // yyyy-MM-dd
    let tokens: Int

    /// Short weekday label: "Mo", "Tu", "We", …
    var dayLabel: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        guard let d = df.date(from: date) else { return String(date.suffix(2)) }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return String(fmt.string(from: d).prefix(2))
    }

    /// e.g. "12.3K" or "1.2M" or "850"
    var formatted: String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }
}
