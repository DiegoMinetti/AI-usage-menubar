import Foundation

@MainActor
final class MenuViewModel: ObservableObject {
    @Published var claudeUsage: ClaudeUsage   = .empty
    @Published var claudeStatus: ClaudeCLIStatus = .notInstalled
    @Published var copilotUsage: CopilotUsage?  = nil
    @Published var codexUsage: ChatGPTCodexUsage = .empty
    @Published var minimaxUsage: MiniMaxUsage = .empty
    @Published var isGitHubConnected: Bool       = CookieStorage.load() != nil
    @Published var isMiniMaxConfigured: Bool     = MiniMaxUsageService.hasAPIKey
    @Published var settings: AppSettings = AppSettingsStore.load()
    // Called by the UI when the user requests a manual refresh
    var onRefresh: (() -> Void)?
    var onSettingsChanged: (() -> Void)?
    var onOpenMainWindow: (() -> Void)?
    var onOpenSettingsWindow: (() -> Void)?
    var onOpenChartSettingsWindow: (() -> Void)?

    func setProvider(_ provider: UsageProviderID, visible: Bool) {
        settings.visibleProviders = toggled(settings.visibleProviders, provider: provider, enabled: visible)
        saveSettings()
    }

    func setMenuBarProvider(_ provider: UsageProviderID, visible: Bool) {
        settings.menuBarProviders = toggled(settings.menuBarProviders, provider: provider, enabled: visible)
        saveSettings()
    }

    func setWidgetProvider(_ provider: UsageProviderID, visible: Bool) {
        settings.widgetProviders = toggled(settings.widgetProviders, provider: provider, enabled: visible)
        saveSettings()
    }

    func setChartProvider(_ provider: UsageProviderID, visible: Bool) {
        settings.chartProviders = toggled(settings.chartProviders, provider: provider, enabled: visible)
        saveSettings()
    }

    func moveChartProvider(_ provider: UsageProviderID, direction: Int) {
        moveProvider(provider, direction: direction)
    }

    func moveProvider(_ provider: UsageProviderID, direction: Int) {
        guard let index = settings.providerOrder.firstIndex(of: provider) else { return }
        let newIndex = index + direction
        guard settings.providerOrder.indices.contains(newIndex) else { return }
        settings.providerOrder.swapAt(index, newIndex)
        saveSettings()
    }

    func setAutoUpdateFromMain(_ enabled: Bool) {
        settings.autoUpdateFromMain = enabled
        saveSettings()
    }

    func setPercentageDisplayMode(_ mode: PercentageDisplayMode) {
        settings.percentageDisplayMode = mode
        saveSettings()
    }

    func setQuotaPeriodDisplayMode(_ mode: QuotaPeriodDisplayMode) {
        settings.quotaPeriodDisplayMode = mode
        saveSettings()
    }

    func displayPercentage(for summary: ProviderUsageSummary) -> Double? {
        switch settings.percentageDisplayMode {
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

    func displayPercentageLabel(for summary: ProviderUsageSummary, includeMode: Bool = true) -> String {
        guard let pct = displayPercentage(for: summary) else { return "-" }
        let suffix = includeMode ? " \(settings.percentageDisplayMode.displayName.lowercased())" : ""
        return String(format: "%.0f%%%@", pct, suffix)
    }

    func displayCompactLabel(for provider: UsageProviderID) -> String {
        let summaries = summariesForDisplay(provider: provider)
        guard settings.quotaPeriodDisplayMode == .both, summaries.count > 1 else {
            return displayPercentageLabel(for: summary(for: provider), includeMode: false)
        }
        return summaries.map { summary in
            "\(shortPeriodLabel(summary.periodLabel)) \(displayPercentageLabel(for: summary, includeMode: false))"
        }.joined(separator: " · ")
    }

    func summariesForDisplay(provider: UsageProviderID, now: Date = Date()) -> [ProviderUsageSummary] {
        guard settings.quotaPeriodDisplayMode == .both else {
            return [summary(for: provider, now: now)]
        }

        switch provider {
        case .claude:
            return [claudeSummary(period: .fiveHour, now: now), claudeSummary(period: .weekly, now: now)]
        case .codex:
            return [
                codexSummary(period: .fiveHour, now: now),
                codexSummary(period: .weekly, now: now)
            ].filter { $0.percentageUsed != nil || $0.limit != nil || $0.status != "No data" }
        case .minimax:
            return [
                minimaxSummary(period: .fiveHour, now: now),
                minimaxSummary(period: .weekly, now: now)
            ].filter { $0.percentageUsed != nil || $0.limit != nil || $0.status != "Not configured" }
        case .copilot:
            return [copilotSummary(now: now)]
        }
    }

    func chartPoints(for provider: UsageProviderID) -> [UsageSnapshot.ChartPoint] {
        switch provider {
        case .claude:
            return claudeUsage.dailyHistory.map {
                UsageSnapshot.ChartPoint(label: String($0.date.suffix(5)), value: Double($0.tokens))
            }
        case .copilot:
            guard let copilotUsage else { return [] }
            return copilotUsage.monthlySeries().map {
                UsageSnapshot.ChartPoint(label: "\($0.day)", value: $0.cumPct, projected: $0.isProjected)
            }
        case .codex:
            return codexUsage.dailyHistory.map {
                UsageSnapshot.ChartPoint(label: String($0.date.suffix(5)), value: Double($0.tokens))
            }
        case .minimax:
            return minimaxUsage.windows.map {
                UsageSnapshot.ChartPoint(label: "\($0.modelName) \($0.periodLabel)", value: $0.displayUsedPercent ?? 0)
            }
        }
    }

    private func shortPeriodLabel(_ label: String) -> String {
        let lower = label.lowercased()
        if lower.contains("5") { return "5h" }
        if lower.contains("week") || lower.contains("seman") { return "W" }
        if lower.contains("month") || lower.contains("mens") { return "M" }
        return String(label.prefix(3))
    }

    func summary(for provider: UsageProviderID, now: Date = Date()) -> ProviderUsageSummary {
        switch provider {
        case .claude:
            return claudeSummary(period: settings.quotaPeriodDisplayMode, now: now)
        case .copilot:
            return copilotSummary(now: now)
        case .codex:
            return codexSummary(period: settings.quotaPeriodDisplayMode, now: now)
        case .minimax:
            return minimaxSummary(period: settings.quotaPeriodDisplayMode, now: now)
        }
    }

    func saveMiniMaxAPIKey(_ apiKey: String) -> Bool {
        do {
            try MiniMaxUsageService.saveAPIKey(apiKey)
            isMiniMaxConfigured = MiniMaxUsageService.hasAPIKey
            minimaxUsage = .empty
            onRefresh?()
            return true
        } catch {
            return false
        }
    }

    func clearMiniMaxAPIKey() -> Bool {
        do {
            try MiniMaxUsageService.clearAPIKey()
            isMiniMaxConfigured = false
            minimaxUsage = .empty
            onSettingsChanged?()
            return true
        } catch {
            return false
        }
    }

    private func saveSettings() {
        AppSettingsStore.save(settings)
        onSettingsChanged?()
    }

    private func toggled(_ providers: [UsageProviderID], provider: UsageProviderID, enabled: Bool) -> [UsageProviderID] {
        var result = providers
        if enabled, !result.contains(provider) {
            result.append(provider)
        } else if !enabled {
            result.removeAll { $0 == provider }
        }
        return result
    }

    private func claudeSummary(period: QuotaPeriodDisplayMode, now: Date) -> ProviderUsageSummary {
        if period == .weekly {
            let reset = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now)
            let remaining = max(Double(claudeUsage.weeklyLimit - claudeUsage.weeklyTokens), 0)
            return ProviderUsageSummary(
                id: .claude,
                name: UsageProviderID.claude.displayName,
                status: claudeStatus.rawValue,
                used: Double(claudeUsage.weeklyTokens),
                remaining: remaining,
                limit: Double(claudeUsage.weeklyLimit),
                unit: .tokens,
                periodLabel: "Weekly",
                periodStart: Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now)),
                periodEnd: reset,
                resetDate: reset,
                updatedAt: nil,
                percentageUsed: claudeUsage.weeklyPercentage
            )
        }

        let periodEnd = claudeUsage.sessionWindowEnd
        let periodStart = periodEnd.map { $0.addingTimeInterval(-5 * 3_600) }
        let remaining = max(Double(claudeUsage.sessionLimit - claudeUsage.sessionTokens), 0)
        return ProviderUsageSummary(
            id: .claude,
            name: UsageProviderID.claude.displayName,
            status: claudeStatus.rawValue,
            used: Double(claudeUsage.sessionTokens),
            remaining: remaining,
            limit: Double(claudeUsage.sessionLimit),
            unit: .tokens,
            periodLabel: "5 hours",
            periodStart: periodStart,
            periodEnd: periodEnd,
            resetDate: periodEnd,
            updatedAt: nil,
            percentageUsed: claudeUsage.sessionPercentage
        )
    }

    private func copilotSummary(now: Date) -> ProviderUsageSummary {
        guard let usage = copilotUsage else {
            return ProviderUsageSummary(
                id: .copilot,
                name: UsageProviderID.copilot.displayName,
                status: isGitHubConnected ? "Fetching" : "Not connected",
                used: nil,
                remaining: nil,
                limit: nil,
                unit: .percent,
                periodLabel: "Monthly",
                periodStart: nil,
                periodEnd: nil,
                resetDate: nil,
                updatedAt: nil,
                percentageUsed: nil
            )
        }

        let periodStart = Calendar.current.date(byAdding: .day, value: -max(usage.daysElapsed, 1), to: Calendar.current.startOfDay(for: now))
        return ProviderUsageSummary(
            id: .copilot,
            name: UsageProviderID.copilot.displayName,
            status: "Connected",
            used: usage.percentage,
            remaining: usage.remainingPercentage,
            limit: 100,
            unit: .percent,
            periodLabel: "Premium requests",
            periodStart: periodStart,
            periodEnd: usage.resetDate,
            resetDate: usage.resetDate,
            updatedAt: usage.fetchedAt,
            percentageUsed: usage.percentage
        )
    }

    private func codexSummary(period: QuotaPeriodDisplayMode, now: Date) -> ProviderUsageSummary {
        if (period == .fiveHour || period == .both), let window = codexUsage.fiveHourWindow {
            return codexWindowSummary(window, now: now)
        }
        if period == .weekly, let window = codexUsage.weeklyWindow {
            return codexWindowSummary(window, now: now)
        }

        if let monthly = codexUsage.monthlyLimit {
            let start = monthly.resetAt.flatMap { Calendar.current.date(byAdding: .month, value: -1, to: $0) }
            return ProviderUsageSummary(
                id: .codex,
                name: UsageProviderID.codex.displayName,
                status: codexUsage.quotaStatus ?? "Usage",
                used: monthly.used,
                remaining: monthly.remaining,
                limit: monthly.limit,
                unit: .credits,
                periodLabel: "Monthly",
                periodStart: start,
                periodEnd: monthly.resetAt,
                resetDate: monthly.resetAt,
                updatedAt: codexUsage.quotaFetchedAt ?? codexUsage.lastUpdated,
                percentageUsed: monthly.usedPercent
            )
        }

        if let weekly = codexUsage.weeklyWindow ?? codexUsage.fiveHourWindow {
            return codexWindowSummary(weekly, now: now)
        }

        return ProviderUsageSummary(
            id: .codex,
            name: UsageProviderID.codex.displayName,
            status: codexUsage.hasUsageData ? (codexUsage.lastModel ?? "Local") : "No data",
            used: Double(codexUsage.monthlyTokens),
            remaining: nil,
            limit: nil,
            unit: .tokens,
            periodLabel: "Local month",
            periodStart: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)),
            periodEnd: nil,
            resetDate: nil,
            updatedAt: codexUsage.lastUpdated,
            percentageUsed: nil
        )
    }

    private func codexWindowSummary(_ window: CodexLimitWindow, now: Date) -> ProviderUsageSummary {
        ProviderUsageSummary(
            id: .codex,
            name: UsageProviderID.codex.displayName,
            status: codexUsage.quotaStatus ?? "Usage",
            used: window.usedPercent,
            remaining: window.remainingPercent,
            limit: 100,
            unit: .percent,
            periodLabel: window.normalizedLabel,
            periodStart: window.resetAt.flatMap { Calendar.current.date(byAdding: .minute, value: -Int(window.windowMinutes), to: $0) },
            periodEnd: window.resetAt,
            resetDate: window.resetAt,
            updatedAt: codexUsage.quotaFetchedAt ?? codexUsage.lastUpdated,
            percentageUsed: window.usedPercent
        )
    }

    private func minimaxSummary(period: QuotaPeriodDisplayMode, now: Date) -> ProviderUsageSummary {
        guard isMiniMaxConfigured else {
            return ProviderUsageSummary(
                id: .minimax,
                name: UsageProviderID.minimax.displayName,
                status: "Not configured",
                used: nil,
                remaining: nil,
                limit: nil,
                unit: .percent,
                periodLabel: "Token Plan",
                periodStart: nil,
                periodEnd: nil,
                resetDate: nil,
                updatedAt: nil,
                percentageUsed: nil
            )
        }

        let selectedWindow: MiniMaxLimitWindow?
        switch period {
        case .fiveHour:
            selectedWindow = minimaxUsage.windows.first { $0.periodLabel.lowercased().contains("5") } ?? minimaxUsage.primaryWindow
        case .weekly:
            selectedWindow = minimaxUsage.windows.first { $0.periodLabel.lowercased().contains("week") } ?? minimaxUsage.primaryWindow
        case .both:
            selectedWindow = minimaxUsage.primaryWindow
        }

        guard let window = selectedWindow else {
            return ProviderUsageSummary(
                id: .minimax,
                name: UsageProviderID.minimax.displayName,
                status: minimaxUsage.errorMessage ?? minimaxUsage.status,
                used: nil,
                remaining: nil,
                limit: nil,
                unit: .percent,
                periodLabel: "Token Plan",
                periodStart: nil,
                periodEnd: nil,
                resetDate: nil,
                updatedAt: minimaxUsage.fetchedAt,
                percentageUsed: nil
            )
        }

        return ProviderUsageSummary(
            id: .minimax,
            name: UsageProviderID.minimax.displayName,
            status: minimaxUsage.status,
            used: window.used ?? window.displayUsedPercent,
            remaining: window.remaining ?? window.displayRemainingPercent,
            limit: window.limit ?? 100,
            unit: window.limit == nil ? .percent : .requests,
            periodLabel: "\(window.modelName) \(window.periodLabel)",
            periodStart: nil,
            periodEnd: window.resetAt,
            resetDate: window.resetAt,
            updatedAt: minimaxUsage.fetchedAt,
            percentageUsed: window.displayUsedPercent
        )
    }
}
