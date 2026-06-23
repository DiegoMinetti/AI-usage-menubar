import SwiftUI

struct ProviderSummaryView: View {
    let summary: ProviderUsageSummary
    let tint: Color
    let now: Date
    var percentageMode: PercentageDisplayMode = .used

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.periodLabel)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if let pct = displayPercentage {
                    Text(String(format: "%.0f%% %@", pct, percentageMode.displayName.lowercased()))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(percentColor(displayUsedPercentage ?? pct))
                } else {
                    Text(summary.status)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            if let pct = displayUsedPercentage {
                UsageBar(value: min(max(pct / 100, 0), 1), color: percentColor(pct))
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    metric("Used", value: formatted(summary.used))
                    metric("Remaining", value: formatted(summary.remaining))
                    metric("Limit", value: formatted(summary.limit))
                }
                GridRow {
                    metric("Start", value: formattedDate(summary.periodStart))
                    metric("Reset", value: formattedDate(summary.resetDate ?? summary.periodEnd))
                    metric("Updated", value: formattedTime(summary.updatedAt))
                }
            }
        }
    }

    private var displayPercentage: Double? {
        switch percentageMode {
        case .used:
            return summary.percentageUsed
        case .remaining:
            if let remaining = summary.remaining, let limit = summary.limit, limit > 0 {
                return min(max((remaining / limit) * 100, 0), 100)
            }
            if let used = summary.percentageUsed {
                return min(max(100 - used, 0), 100)
            }
            return nil
        }
    }

    private var displayUsedPercentage: Double? {
        if let used = summary.percentageUsed { return used }
        if let remaining = displayPercentage, percentageMode == .remaining {
            return min(max(100 - remaining, 0), 100)
        }
        return nil
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "-" }
        switch summary.unit {
        case .tokens:
            return compact(Int(value.rounded()))
        case .percent:
            return String(format: "%.1f%%", value)
        case .credits, .requests:
            return compact(Int(value.rounded()))
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }

    private func formattedTime(_ date: Date?) -> String {
        guard let date else { return "-" }
        if abs(date.timeIntervalSince(now)) < 86_400 {
            let df = DateFormatter()
            df.locale = Locale.current
            df.timeStyle = .short
            df.dateStyle = .none
            return df.string(from: date)
        }
        return formattedDate(date)
    }

    private func compact(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private func percentColor(_ pct: Double) -> Color {
        switch pct {
        case ..<70: return tint
        case ..<90: return .orange
        default: return .red
        }
    }
}
