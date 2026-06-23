import SwiftUI
import AppKit

// MARK: - Brand colors

/// Anthropic / Claude terra cotta  #DA7756
private let claudeColor  = Color(red: 0xDA/255, green: 0x77/255, blue: 0x56/255)
/// GitHub Copilot official purple  #8534F3
private let copilotColor = Color(red: 0x85/255, green: 0x34/255, blue: 0xF3/255)
/// OpenAI green #10A37F
private let codexColor = Color(red: 0x10/255, green: 0xA3/255, blue: 0x7F/255)

// MARK: - Root view

struct MenuContentView: View {
    @ObservedObject var vm: MenuViewModel
    /// Fires every 30 s so countdown labels stay fresh between service refreshes.
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var now = Date()
    @State private var isRefreshing = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Top-right refresh button
            HStack {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .regular))
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Settings")
                .popover(isPresented: $showSettings, arrowEdge: .top) {
                    SettingsPanelView(vm: vm)
                }

                Spacer()
                Button(action: {
                    isRefreshing = true
                    vm.onRefresh?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { isRefreshing = false }
                }) {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.6, anchor: .center)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .regular))
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Refresh now")
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            let visible = UsageProviderID.allCases.filter { vm.settings.showsProvider($0) }
            if visible.isEmpty {
                EmptyProvidersView()
            } else {
                ForEach(Array(visible.enumerated()), id: \.element) { index, provider in
                    if index > 0 { Divider().opacity(0.3) }
                    switch provider {
                    case .claude:
                        ClaudeSectionView(vm: vm, now: now)
                    case .copilot:
                        CopilotSectionView(vm: vm, now: now)
                    case .codex:
                        CodexSectionView(vm: vm, now: now)
                    }
                }
            }
        }
        .frame(width: 290)
        .background(Color.clear)
        .onReceive(tick) { self.now = $0 }
    }
}

private struct EmptyProvidersView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.grid.cross")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
            Text("No providers selected.")
                .font(.system(size: 11, weight: .medium))
            Text("Use Settings to show usage sections again.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 22)
    }
}

// MARK: - Claude section

private struct ClaudeSectionView: View {
    @ObservedObject var vm: MenuViewModel
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(
                title: "CLAUDE CODE",
                dotColor: vm.claudeStatus.dotColor,
                statusLabel: vm.claudeStatus.label
            )

            switch vm.claudeStatus {
            case .notInstalled:
                Text("Claude CLI not installed.\nInstall it at claude.ai/code to start tracking.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .notAuthenticated:
                Text("Claude CLI detected but not authenticated.\nRun `claude` to sign in.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .connected:
                ProviderSummaryView(summary: vm.summary(for: .claude, now: now), tint: claudeColor, now: now)
                Divider().opacity(0.2)
                SessionRowView(usage: vm.claudeUsage, now: now)
                Divider().opacity(0.2)
                WeeklyRowView(usage: vm.claudeUsage, now: now)
                Divider().opacity(0.2)
                ClaudeMonthlyChart(usage: vm.claudeUsage, now: now)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Session row (5h window)

private struct SessionRowView: View {
    let usage: ClaudeUsage
    let now: Date

    private var timeRemaining: TimeInterval? {
        guard let end = usage.sessionWindowEnd else { return nil }
        return max(end.timeIntervalSince(now), 0)
    }

    private var displayedPercentage: Double {
        min(max(usage.sessionPercentage, 0), 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Current session")
                        .font(.system(size: 11, weight: .medium))
                }
                Spacer()
                Text(formatPercentage(displayedPercentage))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(claudePctColor(displayedPercentage))
            }

            if usage.isInActiveSession, let remaining = timeRemaining {
                UsageBar(value: min(displayedPercentage / 100, 1), color: claudePctColor(displayedPercentage))

                HStack {
                    Text("\(formatTokens(usage.sessionTokens)) used")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Resets in \(formatDuration(remaining))")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(resetColor(remaining))
                }
            } else {
                Text("No activity in the last 5h")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                UsageBar(value: 0, color: claudeColor)
            }
        }
    }

    private func resetColor(_ remaining: TimeInterval) -> Color {
        if remaining < 1800 { return .red }
        if remaining < 3600 { return .orange }
        return .secondary
    }
}

// MARK: - Weekly row

private struct WeeklyRowView: View {
    let usage: ClaudeUsage
    let now: Date

    private var displayedPercentage: Double {
        min(max(usage.weeklyPercentage, 0), 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Weekly usage")
                        .font(.system(size: 11, weight: .medium))
                }
                Spacer()
                Text(formatPercentage(displayedPercentage))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(claudePctColor(displayedPercentage))
            }
            UsageBar(value: min(displayedPercentage / 100, 1), color: claudePctColor(displayedPercentage))

            HStack {
                Text("\(formatTokens(usage.weeklyTokens)) in last 7d")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Refreshes in \(formatDuration(usage.timeUntilWeeklyRefresh))")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Claude monthly chart

private struct ClaudeMonthlyChart: View {
    let usage: ClaudeUsage
    let now: Date

    private var timeUntilReset: TimeInterval {
        max(usage.monthlyRenewalDate.timeIntervalSince(now), 0)
    }

    var body: some View {
        let (actual, projected, limitY) = buildChartData()

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("This month")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if usage.hasUsageData {
                    Text(formatTokens(usage.totalTokens))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundColor(claudeColor)
                } else {
                    Text("Simulated")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            CumulativeLineChart(
                actualPoints: actual,
                projectedPoints: projected,
                referenceY: limitY,
                color: usage.hasUsageData ? claudeColor : claudeColor.opacity(0.4)
            )
            .frame(height: 52)

            if usage.hasUsageData && usage.dailyAverage > 0 {
                HStack {
                    Text("~\(formatTokens(Int(usage.dailyAverage)))/day avg")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    let proj = usage.projectedMonthlyTokens
                    Text("Proj. \(formatTokens(proj))")
                        .font(.system(size: 10))
                        .foregroundColor(proj > usage.monthlyLimit ? .orange : .secondary)
                }
            } else if !usage.hasUsageData {
                Text("No usage data recorded yet.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Monthly renewal row
            Divider().opacity(0.2)
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Resets")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formattedRenewalDate(usage.monthlyRenewalDate))
                        .font(.system(size: 11, weight: .semibold))
                    Text(countdownLabel(timeUntilReset))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(timeUntilReset < 86400 ? .orange : .secondary)
                }
            }
        }
    }

    private func buildChartData() -> (actual: [(CGFloat, CGFloat)], projected: [(CGFloat, CGFloat)], limitY: CGFloat) {
        let history = usage.dailyHistory
        guard usage.hasUsageData else {
            let n = 30
            var sim: [(CGFloat, CGFloat)] = []
            for i in 0..<n {
                sim.append((CGFloat(i) / CGFloat(max(n - 1, 1)), CGFloat(i + 1) / CGFloat(n)))
            }
            return ([], sim, 1.0)
        }

        let projectedEnd = max(usage.projectedMonthlyTokens, usage.totalTokens)
        let limit  = max(usage.monthlyLimit, 1)
        let yMax   = max(Double(limit), Double(projectedEnd)) * 1.05
        let todayStr = ymdToday()
        let todayIdx = history.firstIndex(where: { $0.date == todayStr }) ?? (history.count - 1)
        let n = history.count

        var cum = 0
        var actual: [(CGFloat, CGFloat)] = []
        for (i, day) in history.enumerated() {
            cum += day.tokens
            if i <= todayIdx {
                actual.append((CGFloat(i) / CGFloat(max(n - 1, 1)), CGFloat(cum) / CGFloat(yMax)))
            }
        }

        var projected: [(CGFloat, CGFloat)] = []
        if let last = actual.last {
            projected.append(last)
            var projCum = Double(cum)
            let remaining = n - 1 - todayIdx
            if remaining > 0 {
                for j in 1...remaining {
                    projCum += usage.dailyAverage
                    let x = CGFloat(todayIdx + j) / CGFloat(max(n - 1, 1))
                    projected.append((x, min(CGFloat(projCum / yMax), 1.4)))
                }
            }
        }

        return (actual, projected, CGFloat(Double(limit) / yMax))
    }

    private func ymdToday() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}

// MARK: - ChatGPT / Codex section

private struct CodexSectionView: View {
    @ObservedObject var vm: MenuViewModel
    let now: Date

    var body: some View {
        let usage = vm.codexUsage

        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(
                title: "CHATGPT / CODEX",
                dotColor: usage.hasUsageData ? .green : Color(NSColor.tertiaryLabelColor),
                statusLabel: usage.hasQuotaData ? "Usage" : (usage.lastModel ?? (usage.hasUsageData ? "Local" : "No data"))
            )

            if usage.hasUsageData {
                ProviderSummaryView(summary: vm.summary(for: .codex, now: now), tint: codexColor, now: now)
                Divider().opacity(0.2)

                if usage.hasQuotaData {
                    CodexRemainingView(usage: usage, now: now)
                    Divider().opacity(0.2)
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Local last 7d")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(formatTokens(usage.weeklyTokens))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundColor(codexColor)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Total")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(formatTokens(usage.totalTokens))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    }
                }

                CodexMiniChart(usage: usage)
                    .frame(height: 38)

                HStack {
                    Text("\(usage.activeThreads) active · \(usage.archivedThreads) archived")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let updated = usage.lastUpdated {
                        Text("Updated \(formatTime(updated))")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No Codex usage found at \(usage.sourcePath). Sign in to Codex Desktop to show remaining usage.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct CodexRemainingView: View {
    let usage: ChatGPTCodexUsage
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Uso restante")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if let fetched = usage.quotaFetchedAt {
                    Text("Updated \(formatTime(fetched))")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            if let fiveHour = usage.fiveHourWindow {
                CodexLimitRow(window: fiveHour, now: now)
            }
            if let weekly = usage.weeklyWindow {
                CodexLimitRow(window: weekly, now: now)
            }
            ForEach(extraWindows, id: \.id) { window in
                CodexLimitRow(window: window, now: now)
            }
            if let monthly = usage.monthlyLimit {
                CodexMonthlyLimitRow(monthly: monthly, now: now)
            } else if let monthlyWindow = usage.monthlyWindow {
                CodexLimitRow(window: monthlyWindow, now: now)
            }
        }
    }

    private var extraWindows: [CodexLimitWindow] {
        usage.limitWindows.filter { window in
            abs(window.windowMinutes - 300) > 1 &&
            abs(window.windowMinutes - 10_080) > 60 &&
            abs(window.windowMinutes - 43_200) > 1_440
        }
    }
}

private struct CodexLimitRow: View {
    let window: CodexLimitWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.normalizedLabel)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(String(format: "%.0f%%", window.remainingPercent))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(codexRemainingColor(window.remainingPercent))
                if let reset = window.resetAt {
                    Text(resetLabel(reset))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            UsageBar(value: min(max(window.usedPercent / 100, 0), 1), color: codexLimitColor(window.usedPercent))
        }
    }

    private func resetLabel(_ date: Date) -> String {
        if date.timeIntervalSince(now) < 86_400 {
            return formatTime(date)
        }
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }
}

private struct CodexMonthlyLimitRow: View {
    let monthly: CodexMonthlyLimit
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mensual")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(String(format: "%.0f%%", monthly.remainingPercent))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(codexRemainingColor(monthly.remainingPercent))
                if let reset = monthly.resetAt {
                    Text(countdownLabel(reset.timeIntervalSince(now)))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            UsageBar(value: min(max(monthly.usedPercent / 100, 0), 1), color: codexLimitColor(monthly.usedPercent))
            HStack {
                Text("\(formatCredits(monthly.remaining)) restantes")
                Spacer()
                Text("Limite \(formatCredits(monthly.limit))")
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundColor(.secondary)
        }
    }
}

private struct CodexMiniChart: View {
    let usage: ChatGPTCodexUsage

    var body: some View {
        let values = usage.dailyHistory.map(\.tokens)
        let maxValue = max(values.max() ?? 0, 1)

        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(usage.dailyHistory.enumerated()), id: \.offset) { _, day in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(day.tokens > 0 ? codexColor.opacity(0.85) : Color.secondary.opacity(0.14))
                    .frame(height: max(CGFloat(day.tokens) / CGFloat(maxValue) * 34, day.tokens > 0 ? 3 : 2))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

// MARK: - Copilot section

private struct CopilotSectionView: View {
    @ObservedObject var vm: MenuViewModel
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(
                title: "GITHUB COPILOT",
                dotColor: vm.isGitHubConnected ? .green : Color(NSColor.tertiaryLabelColor),
                statusLabel: vm.isGitHubConnected ? "Connected" : "Not connected"
            )

            if !vm.isGitHubConnected {
                Text("Connect your GitHub account to track Copilot usage.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let usage = vm.copilotUsage {
                ProviderSummaryView(summary: vm.summary(for: .copilot, now: now), tint: copilotColor, now: now)
                Divider().opacity(0.2)
                CopilotUsageRowView(usage: usage, now: now)
            } else {
                Text("Fetching usage…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Copilot usage row

private struct CopilotUsageRowView: View {
    let usage: CopilotUsage
    let now: Date

    private var projectedPct: Double? { usage.projectedEndPercentage }
    private var isOverBudget: Bool { (projectedPct ?? 0) > 100 }

    private var timeUntilReset: TimeInterval {
        max(usage.resetDate.timeIntervalSince(now), 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Used / Available header
            HStack {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Used")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", usage.percentage))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundColor(pctColor(usage.percentage))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Available")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", usage.remainingPercentage))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundColor(usage.remainingPercentage < 20 ? .red : copilotColor)
                    }
                }
                Spacer()
                Text("Premium requests")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            UsageBar(
                value: usage.percentage / 100,
                projectedValue: (projectedPct ?? usage.percentage) / 100,
                color: isOverBudget ? .orange : copilotColor
            )

            // Paid premium requests info + manage button
            if let paid = usage.paidPremiumRequestsEnabled {
                HStack {
                    Text(paid ? "Additional paid premium requests enabled." : "Additional paid premium requests disabled.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        let url = usage.managePaidURL ?? URL(string: "https://github.com/settings/copilot")!
                        NSWorkspace.shared.open(url)
                    }) {
                        Text("Manage paid premium requests")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }

            CopilotCumulativeChart(usage: usage)
                .frame(height: 52)

            // Projection row
            HStack {
                if let proj = projectedPct {
                    if isOverBudget {
                        Label(String(format: "Proj. %.0f%%", proj), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    } else {
                        Text(String(format: "Proj. %.0f%%", proj))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Not enough data yet")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            // Reset row — always prominent
            Divider().opacity(0.2)
            CopilotResetRow(usage: usage, timeUntilReset: timeUntilReset)
        }
    }

    private func pctColor(_ pct: Double) -> Color {
        switch pct {
        case ..<70: return copilotColor
        case ..<90: return .orange
        default:    return .red
        }
    }
}

// MARK: - Copilot reset row

private struct CopilotResetRow: View {
    let usage: CopilotUsage
    let timeUntilReset: TimeInterval

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("Resets")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(formattedResetDate)
                    .font(.system(size: 11, weight: .semibold))
                Text(countdownLabel(timeUntilReset))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(timeUntilReset < 86400 ? .orange : .secondary)
            }
        }
    }

    private var formattedResetDate: String {
        if let s = usage.resetDisplayString, !s.isEmpty {
            return s
        }
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: usage.resetDate)
    }
}

// MARK: - Copilot cumulative chart

private struct CopilotCumulativeChart: View {
    let usage: CopilotUsage

    private var chartData: (actual: [(CGFloat, CGFloat)], projected: [(CGFloat, CGFloat)], limitY: CGFloat) {
        let series = usage.monthlySeries()
        guard !series.isEmpty else { return ([], [(0, 0), (1, 0)], 1.0) }

        let yMax: CGFloat = 150
        var actual:    [(CGFloat, CGFloat)] = []
        var projected: [(CGFloat, CGFloat)] = []
        let total = CGFloat(series.count)

        for pt in series {
            let x = CGFloat(pt.day) / total
            let y = CGFloat(pt.cumPct) / yMax
            if !pt.isProjected { actual.append((x, y)) }
            else               { projected.append((x, min(y, 1.4))) }
        }
        if let bridge = actual.last { projected.insert(bridge, at: 0) }

        return (actual, projected, 100 / yMax)
    }

    var body: some View {
        let (actual, projected, limitY) = chartData
        CumulativeLineChart(actualPoints: actual, projectedPoints: projected, referenceY: limitY, color: copilotColor)
    }
}

// MARK: - Shared cumulative line chart (Canvas)

private struct CumulativeLineChart: View {
    let actualPoints:    [(CGFloat, CGFloat)]
    let projectedPoints: [(CGFloat, CGFloat)]
    var referenceY: CGFloat? = nil
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let dotStroke: Color = colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.15)
            let refColor:  Color = .red.opacity(colorScheme == .dark ? 0.50 : 0.40)

            let draw: [(CGFloat, CGFloat)]
            if actualPoints.count == 1, let pt = actualPoints.first, pt.0 > 0 {
                draw = [(0, 0), pt]
            } else {
                draw = actualPoints
            }

            // ── Reference line ────────────────────────────────────
            if let refY = referenceY, refY > 0, refY <= 1.2 {
                let ry = h - refY * h
                var p = Path(); p.move(to: CGPoint(x: 0, y: ry)); p.addLine(to: CGPoint(x: w, y: ry))
                ctx.stroke(p, with: .color(refColor), style: StrokeStyle(lineWidth: 0.75, dash: [3, 2]))
            }

            // ── Area fill ─────────────────────────────────────────
            if draw.count >= 2 {
                var fill = Path()
                fill.move(to: CGPoint(x: draw[0].0 * w, y: h))
                for (x, y) in draw { fill.addLine(to: CGPoint(x: x * w, y: h - y * h)) }
                fill.addLine(to: CGPoint(x: draw.last!.0 * w, y: h))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(color.opacity(colorScheme == .dark ? 0.15 : 0.10)))
            }

            // ── Solid line ────────────────────────────────────────
            if draw.count >= 2 {
                var line = Path()
                line.move(to: CGPoint(x: draw[0].0 * w, y: h - draw[0].1 * h))
                for (x, y) in draw.dropFirst() { line.addLine(to: CGPoint(x: x * w, y: h - y * h)) }
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }

            // ── Projected dashed line ─────────────────────────────
            if projectedPoints.count >= 2 {
                var line = Path()
                line.move(to: CGPoint(x: projectedPoints[0].0 * w, y: h - min(projectedPoints[0].1, 1.3) * h))
                for (x, y) in projectedPoints.dropFirst() {
                    line.addLine(to: CGPoint(x: x * w, y: h - min(y, 1.3) * h))
                }
                ctx.stroke(line, with: .color(color.opacity(0.40)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 3]))
            }

            // ── Today dot ─────────────────────────────────────────
            if let pt = draw.last ?? projectedPoints.first {
                let cx = pt.0 * w; let cy = h - min(pt.1, 1.3) * h
                let dot = Path(ellipseIn: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))
                ctx.fill(dot, with: .color(color))
                ctx.stroke(dot, with: .color(dotStroke), lineWidth: 1.5)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.08 : 0.06))
        )
    }
}

// MARK: - Shared primitives

struct UsageBar: View {
    let value: Double
    var projectedValue: Double? = nil
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12))
                if let proj = projectedValue, proj > value {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.20))
                        .frame(width: min(w * proj, w))
                }
                if value > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.gradient)
                        .frame(width: min(w * value, w))
                }
            }
        }
        .frame(height: 5)
    }
}

private struct SectionHeader: View {
    let title: String
    let dotColor: Color
    let statusLabel: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .tracking(0.5)
            Spacer()
            Circle().fill(dotColor).frame(width: 5, height: 5)
            Text(statusLabel)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Helpers

private func formatTokens(_ t: Int) -> String {
    if t >= 1_000_000 { return String(format: "%.1fM", Double(t) / 1_000_000) }
    if t >= 1_000     { return String(format: "%.1fK", Double(t) / 1_000) }
    return "\(t)"
}

private func formatCredits(_ value: Double) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return String(format: "%.0f", value)
}

private func formatPercentage(_ value: Double) -> String {
    String(format: "%.0f%% used", value)
}

private func formatDuration(_ t: TimeInterval) -> String {
    let total = max(Int(t), 0)
    let d = total / 86400
    let h = (total % 86400) / 3600
    let m = (total % 3600) / 60
    if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "<1m"
}

/// Countdown label: "in Xd Xh" / "in Xh Xm" / "soon"
private func countdownLabel(_ t: TimeInterval) -> String {
    let total = max(Int(t), 0)
    let d = total / 86400
    let h = (total % 86400) / 3600
    let m = (total % 3600) / 60
    if d > 1 { return "in \(d)d \(h)h" }
    if d == 1 { return "in 1d \(h)h" }
    if h > 0  { return "in \(h)h \(m)m" }
    if m > 0  { return "in \(m)m" }
    return "soon"
}

private func formatTime(_ date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale.current
    df.timeStyle = .short
    df.dateStyle = .none
    return df.string(from: date)
}

private func claudePctColor(_ pct: Double) -> Color {
    switch pct {
    case ..<70: return claudeColor
    case ..<90: return .orange
    default:    return .red
    }
}

private func codexLimitColor(_ usedPercent: Double) -> Color {
    switch usedPercent {
    case ..<70: return codexColor
    case ..<90: return .orange
    default:    return .red
    }
}

private func codexRemainingColor(_ remainingPercent: Double) -> Color {
    switch remainingPercent {
    case ..<10: return .red
    case ..<30: return .orange
    default:    return codexColor
    }
}

private func formattedRenewalDate(_ date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale.current
    df.dateFormat = "MMM d, yyyy"
    return df.string(from: date)
}

private extension ClaudeCLIStatus {
    var dotColor: Color {
        switch self {
        case .connected:        return .green
        case .notAuthenticated: return .orange
        case .notInstalled:     return Color(NSColor.tertiaryLabelColor)
        }
    }
    var label: String {
        switch self {
        case .connected:        return "Connected"
        case .notAuthenticated: return "Not auth."
        case .notInstalled:     return "Not installed"
        }
    }
}
