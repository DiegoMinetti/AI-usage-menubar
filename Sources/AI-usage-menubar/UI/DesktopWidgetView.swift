import SwiftUI

private let widgetClaudeColor = Color(red: 0xDA/255, green: 0x77/255, blue: 0x56/255)
private let widgetCopilotColor = Color(red: 0x85/255, green: 0x34/255, blue: 0xF3/255)
private let widgetCodexColor = Color(red: 0x10/255, green: 0xA3/255, blue: 0x7F/255)

struct DesktopWidgetView: View {
    @ObservedObject var vm: MenuViewModel
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var now = Date()

    var body: some View {
        let visible = UsageProviderID.allCases.filter { vm.settings.showsProvider($0) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI Usage")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Updated \(formatWidgetTime(now))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { vm.onRefresh?() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }

            if visible.isEmpty {
                Text("No providers selected.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(visible) { provider in
                    switch provider {
                    case .claude:
                        WidgetServiceRow(
                            name: "Claude",
                            value: String(format: "%.0f%%", min(max(vm.claudeUsage.sessionPercentage, 0), 100)),
                            detail: vm.claudeUsage.sessionWindowEnd.map { "Session resets \(countdown(to: $0, now: now))" } ?? "No active session",
                            color: widgetClaudeColor,
                            progress: min(max(vm.claudeUsage.sessionPercentage / 100, 0), 1)
                        )
                    case .copilot:
                        WidgetServiceRow(
                            name: "Copilot",
                            value: vm.copilotUsage.map { String(format: "%.0f%%", $0.percentage) } ?? "-",
                            detail: vm.copilotUsage.map { "Resets \(countdown(to: $0.resetDate, now: now))" } ?? "Not connected",
                            color: widgetCopilotColor,
                            progress: min(max((vm.copilotUsage?.percentage ?? 0) / 100, 0), 1)
                        )
                    case .codex:
                        WidgetServiceRow(
                            name: "Codex",
                            value: codexValue(vm.codexUsage),
                            detail: codexDetail(vm.codexUsage, now: now),
                            color: widgetCodexColor,
                            progress: codexProgress(vm.codexUsage)
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 320, height: max(125, 76 + CGFloat(max(visible.count, 1)) * 45))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onReceive(tick) { now = $0 }
    }

    private func codexProgress(_ usage: ChatGPTCodexUsage) -> Double {
        if let fiveHour = usage.fiveHourWindow {
            return min(max(fiveHour.usedPercent / 100, 0), 1)
        }
        if let weekly = usage.weeklyWindow {
            return min(max(weekly.usedPercent / 100, 0), 1)
        }
        if let monthly = usage.monthlyLimit {
            return min(max(monthly.usedPercent / 100, 0), 1)
        }
        let maxDay = max(usage.dailyHistory.map(\.tokens).max() ?? 0, 1)
        return min(Double(usage.todayTokens) / Double(maxDay), 1)
    }

    private func codexValue(_ usage: ChatGPTCodexUsage) -> String {
        if let fiveHour = usage.fiveHourWindow {
            return String(format: "%.0f%%", fiveHour.remainingPercent)
        }
        if let weekly = usage.weeklyWindow {
            return String(format: "%.0f%%", weekly.remainingPercent)
        }
        if let monthly = usage.monthlyLimit {
            return String(format: "%.0f%%", monthly.remainingPercent)
        }
        return compactCount(usage.weeklyTokens)
    }

    private func codexDetail(_ usage: ChatGPTCodexUsage, now: Date) -> String {
        var parts: [String] = []
        if let fiveHour = usage.fiveHourWindow {
            parts.append("5h \(String(format: "%.0f%%", fiveHour.remainingPercent)) left")
        }
        if let weekly = usage.weeklyWindow {
            parts.append("Weekly \(String(format: "%.0f%%", weekly.remainingPercent)) left")
        }
        if parts.isEmpty, let monthly = usage.monthlyLimit {
            parts.append("Monthly \(String(format: "%.0f%%", monthly.remainingPercent)) left")
        }
        if let reset = usage.fiveHourWindow?.resetAt ?? usage.weeklyWindow?.resetAt ?? usage.monthlyLimit?.resetAt {
            parts.append("resets \(countdown(to: reset, now: now))")
        }
        if parts.isEmpty {
            parts.append("\(usage.activeThreads) active threads")
        }
        return parts.joined(separator: " · ")
    }
}

private struct WidgetServiceRow: View {
    let name: String
    let value: String
    let detail: String
    let color: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.14))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(geo.size.width * progress, progress > 0 ? 4 : 0))
                }
            }
            .frame(height: 6)

            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

private func compactCount(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
    return "\(value)"
}

private func formatWidgetTime(_ date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale.current
    df.timeStyle = .short
    df.dateStyle = .none
    return df.string(from: date)
}

private func countdown(to date: Date, now: Date) -> String {
    let total = max(Int(date.timeIntervalSince(now)), 0)
    let days = total / 86_400
    let hours = (total % 86_400) / 3_600
    let minutes = (total % 3_600) / 60
    if days > 0 { return "in \(days)d \(hours)h" }
    if hours > 0 { return "in \(hours)h \(minutes)m" }
    if minutes > 0 { return "in \(minutes)m" }
    return "soon"
}
