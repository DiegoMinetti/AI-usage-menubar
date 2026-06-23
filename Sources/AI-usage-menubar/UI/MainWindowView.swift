import SwiftUI

private let mainClaudeColor = Color(red: 0xDA/255, green: 0x77/255, blue: 0x56/255)
private let mainCopilotColor = Color(red: 0x85/255, green: 0x34/255, blue: 0xF3/255)
private let mainCodexColor = Color(red: 0x10/255, green: 0xA3/255, blue: 0x7F/255)
private let mainMiniMaxColor = Color(red: 0x25/255, green: 0x63/255, blue: 0xEB/255)

struct MainWindowView: View {
    @ObservedObject var vm: MenuViewModel
    @State var selectedTab: MainWindowTab
    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Dashboard", systemImage: "chart.xyaxis.line")
                    .tag(MainWindowTab.dashboard)
                Label("Charts", systemImage: "slider.horizontal.3")
                    .tag(MainWindowTab.chartSettings)
                Label("Settings", systemImage: "gearshape")
                    .tag(MainWindowTab.settings)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 210)
        } detail: {
            switch selectedTab {
            case .dashboard:
                DashboardView(vm: vm, now: now)
            case .chartSettings:
                ChartSettingsView(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .settings:
                SettingsPanelView(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onReceive(tick) { now = $0 }
    }
}

enum MainWindowTab: Hashable {
    case dashboard
    case chartSettings
    case settings
}

private struct DashboardView: View {
    @ObservedObject var vm: MenuViewModel
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI Usage")
                            .font(.system(size: 28, weight: .semibold))
                        Text("Usage, limits, resets, and local history across providers.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { vm.onRefresh?() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    ForEach(vm.settings.orderedVisibleProviders) { provider in
                        overviewCard(for: provider)
                    }
                }

                ForEach(vm.settings.orderedChartProviders) { provider in
                    chartPanel(for: provider)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func overviewCard(for provider: UsageProviderID) -> some View {
        switch provider {
        case .claude:
            ProviderOverviewCard(summary: vm.summary(for: .claude, now: now), tint: mainClaudeColor, now: now, percentageMode: vm.settings.percentageDisplayMode)
        case .copilot:
            ProviderOverviewCard(summary: vm.summary(for: .copilot, now: now), tint: mainCopilotColor, now: now, percentageMode: vm.settings.percentageDisplayMode)
        case .codex:
            ProviderOverviewCard(summary: vm.summary(for: .codex, now: now), tint: mainCodexColor, now: now, percentageMode: vm.settings.percentageDisplayMode)
        case .minimax:
            ProviderOverviewCard(summary: vm.summary(for: .minimax, now: now), tint: mainMiniMaxColor, now: now, percentageMode: vm.settings.percentageDisplayMode)
        }
    }

    @ViewBuilder
    private func chartPanel(for provider: UsageProviderID) -> some View {
        switch provider {
        case .claude:
            ProviderChartPanel(
                title: "Claude Code",
                subtitle: "Daily token history and configured limits",
                tint: mainClaudeColor,
                values: vm.claudeUsage.dailyHistory.map { ChartValue(label: shortDate($0.date), value: Double($0.tokens)) },
                summary: vm.summary(for: .claude, now: now)
            )
        case .copilot:
            ProviderChartPanel(
                title: "GitHub Copilot",
                subtitle: "Estimated request burn across the current allowance cycle",
                tint: mainCopilotColor,
                values: copilotValues(vm.copilotUsage),
                summary: vm.summary(for: .copilot, now: now)
            )
        case .codex:
            ProviderChartPanel(
                title: "ChatGPT / Codex",
                subtitle: "Local thread token history plus quota data when available",
                tint: mainCodexColor,
                values: vm.codexUsage.dailyHistory.map { ChartValue(label: shortDate($0.date), value: Double($0.tokens)) },
                summary: vm.summary(for: .codex, now: now)
            )
        case .minimax:
            ProviderChartPanel(
                title: "MiniMax",
                subtitle: "Token Plan quota windows from the official remains endpoint",
                tint: mainMiniMaxColor,
                values: minimaxValues(vm.minimaxUsage),
                summary: vm.summary(for: .minimax, now: now)
            )
        }
    }

    private func copilotValues(_ usage: CopilotUsage?) -> [ChartValue] {
        guard let usage else { return [] }
        return usage.monthlySeries().map {
            ChartValue(label: "\($0.day)", value: $0.cumPct, projected: $0.isProjected)
        }
    }

    private func minimaxValues(_ usage: MiniMaxUsage) -> [ChartValue] {
        usage.windows.map {
            ChartValue(label: "\($0.modelName) \($0.periodLabel)", value: $0.displayUsedPercent ?? 0)
        }
    }

    private func shortDate(_ ymd: String) -> String {
        String(ymd.suffix(5))
    }
}

private struct ProviderOverviewCard: View {
    let summary: ProviderUsageSummary
    let tint: Color
    let now: Date
    let percentageMode: PercentageDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(summary.status)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let pct = displayPercentage {
                    Text(String(format: "%.0f%% %@", pct, percentageMode.displayName.lowercased()))
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                        .foregroundColor(percentColor(summary.percentageUsed ?? pct))
                }
            }

            if let pct = summary.percentageUsed {
                ProgressView(value: min(max(pct / 100, 0), 1))
                    .tint(percentColor(pct))
            }

            HStack(spacing: 12) {
                stat("Used", summary.used)
                stat("Left", summary.remaining)
                stat("Limit", summary.limit)
            }

            HStack {
                Label(summary.periodLabel, systemImage: "calendar")
                Spacer()
                Text(summary.resetDate.map { "Resets \(relative($0))" } ?? "No reset date")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
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

    private func stat(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(format(value))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "-" }
        switch summary.unit {
        case .percent:
            return String(format: "%.1f%%", value)
        case .tokens, .credits, .requests:
            let intValue = Int(value.rounded())
            if intValue >= 1_000_000 { return String(format: "%.1fM", Double(intValue) / 1_000_000) }
            if intValue >= 1_000 { return String(format: "%.1fK", Double(intValue) / 1_000) }
            return "\(intValue)"
        }
    }

    private func relative(_ date: Date) -> String {
        let total = max(Int(date.timeIntervalSince(now)), 0)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        if days > 0 { return "in \(days)d \(hours)h" }
        if hours > 0 { return "in \(hours)h" }
        return "soon"
    }

    private func percentColor(_ pct: Double) -> Color {
        switch pct {
        case ..<70: return tint
        case ..<90: return .orange
        default: return .red
        }
    }
}

struct ChartSettingsView: View {
    @ObservedObject var vm: MenuViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Chart Settings")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Choose which provider charts appear and reorder providers. This same order drives the menu bar, widgets, dashboard, and charts.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                SettingsGroup(title: "Provider visibility and display order") {
                    ForEach(vm.settings.providerOrder) { provider in
                        ChartProviderSettingsRow(provider: provider, vm: vm)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
        }
    }
}

private struct ChartProviderSettingsRow: View {
    let provider: UsageProviderID
    @ObservedObject var vm: MenuViewModel

    var body: some View {
        HStack(spacing: 10) {
            Toggle(provider.displayName, isOn: Binding(
                get: { vm.settings.showsProviderChart(provider) },
                set: { vm.setChartProvider(provider, visible: $0) }
            ))
            Spacer()
            Button(action: { vm.moveProvider(provider, direction: -1) }) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveUp)
            .help("Move chart up")

            Button(action: { vm.moveProvider(provider, direction: 1) }) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveDown)
            .help("Move chart down")
        }
    }

    private var canMoveUp: Bool {
        guard let index = vm.settings.providerOrder.firstIndex(of: provider) else { return false }
        return index > 0
    }

    private var canMoveDown: Bool {
        guard let index = vm.settings.providerOrder.firstIndex(of: provider) else { return false }
        return index < vm.settings.providerOrder.count - 1
    }
}

private struct ProviderChartPanel: View {
    let title: String
    let subtitle: String
    let tint: Color
    let values: [ChartValue]
    let summary: ProviderUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(summary.periodLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            AdvancedBarChart(values: values, tint: tint, reference: summary.limit)
                .frame(height: 170)

            HStack(spacing: 16) {
                chartMetric("Used", summary.used, unit: summary.unit)
                chartMetric("Remaining", summary.remaining, unit: summary.unit)
                chartMetric("Limit", summary.limit, unit: summary.unit)
                chartMetric("Reset", summary.resetDate)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func chartMetric(_ label: String, _ value: Double?, unit: ProviderUsageSummary.Unit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(format(value, unit: unit))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
    }

    private func chartMetric(_ label: String, _ value: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(value.map { dateFormatter.string(from: $0) } ?? "-")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
    }

    private func format(_ value: Double?, unit: ProviderUsageSummary.Unit) -> String {
        guard let value else { return "-" }
        if unit == .percent { return String(format: "%.1f%%", value) }
        let intValue = Int(value.rounded())
        if intValue >= 1_000_000 { return String(format: "%.1fM", Double(intValue) / 1_000_000) }
        if intValue >= 1_000 { return String(format: "%.1fK", Double(intValue) / 1_000) }
        return "\(intValue)"
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }
}

private struct AdvancedBarChart: View {
    let values: [ChartValue]
    let tint: Color
    let reference: Double?

    var body: some View {
        let maxValue = max(values.map(\.value).max() ?? 0, reference ?? 0, 1)

        GeometryReader { geo in
            VStack(spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.07))

                    if let reference, reference > 0 {
                        let y = geo.size.height * 0.78 * (1 - min(reference / maxValue, 1))
                        Path { path in
                            path.move(to: CGPoint(x: 8, y: y + 8))
                            path.addLine(to: CGPoint(x: geo.size.width - 8, y: y + 8))
                        }
                        .stroke(Color.red.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }

                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(values) { item in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item.projected ? tint.opacity(0.28) : tint.opacity(item.value > 0 ? 0.85 : 0.18))
                                .frame(height: max(CGFloat(item.value / maxValue) * (geo.size.height - 28), item.value > 0 ? 3 : 2))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }

                HStack {
                    Text(values.first?.label ?? "-")
                    Spacer()
                    Text(values.last?.label ?? "-")
                }
                .font(.system(size: 9).monospacedDigit())
                .foregroundColor(.secondary)
            }
        }
    }
}

private struct ChartValue: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    var projected: Bool = false
}
