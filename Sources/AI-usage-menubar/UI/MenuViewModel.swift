import Foundation

@MainActor
final class MenuViewModel: ObservableObject {
    @Published var claudeUsage: ClaudeUsage   = .empty
    @Published var claudeStatus: ClaudeCLIStatus = .notInstalled
    @Published var copilotUsage: CopilotUsage?  = nil
    @Published var codexUsage: ChatGPTCodexUsage = .empty
    @Published var isGitHubConnected: Bool       = CookieStorage.load() != nil
    @Published var settings: AppSettings = AppSettingsStore.load()
    // Called by the UI when the user requests a manual refresh
    var onRefresh: (() -> Void)?
    var onSettingsChanged: (() -> Void)?

    func setProvider(_ provider: UsageProviderID, visible: Bool) {
        settings.visibleProviders = toggled(settings.visibleProviders, provider: provider, enabled: visible)
        saveSettings()
    }

    func setMenuBarProvider(_ provider: UsageProviderID, visible: Bool) {
        settings.menuBarProviders = toggled(settings.menuBarProviders, provider: provider, enabled: visible)
        saveSettings()
    }

    func setAutoUpdateFromMain(_ enabled: Bool) {
        settings.autoUpdateFromMain = enabled
        saveSettings()
    }

    func summary(for provider: UsageProviderID, now: Date = Date()) -> ProviderUsageSummary {
        switch provider {
        case .claude:
            return claudeSummary(now: now)
        case .copilot:
            return copilotSummary(now: now)
        case .codex:
            return codexSummary(now: now)
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
        return UsageProviderID.allCases.filter { result.contains($0) }
    }

    private func claudeSummary(now: Date) -> ProviderUsageSummary {
        let periodEnd = claudeUsage.monthlyRenewalDate
        let periodStart = Calendar.current.date(byAdding: .month, value: -1, to: periodEnd)
        let remaining = max(Double(claudeUsage.monthlyLimit - claudeUsage.totalTokens), 0)
        return ProviderUsageSummary(
            id: .claude,
            name: UsageProviderID.claude.displayName,
            status: claudeStatus.rawValue,
            used: Double(claudeUsage.totalTokens),
            remaining: remaining,
            limit: Double(claudeUsage.monthlyLimit),
            unit: .tokens,
            periodLabel: "Monthly",
            periodStart: periodStart,
            periodEnd: periodEnd,
            resetDate: periodEnd,
            updatedAt: nil,
            percentageUsed: claudeUsage.monthlyPercentage
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

    private func codexSummary(now: Date) -> ProviderUsageSummary {
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
            return ProviderUsageSummary(
                id: .codex,
                name: UsageProviderID.codex.displayName,
                status: codexUsage.quotaStatus ?? "Usage",
                used: weekly.usedPercent,
                remaining: weekly.remainingPercent,
                limit: 100,
                unit: .percent,
                periodLabel: weekly.normalizedLabel,
                periodStart: weekly.resetAt.flatMap { Calendar.current.date(byAdding: .minute, value: -Int(weekly.windowMinutes), to: $0) },
                periodEnd: weekly.resetAt,
                resetDate: weekly.resetAt,
                updatedAt: codexUsage.quotaFetchedAt ?? codexUsage.lastUpdated,
                percentageUsed: weekly.usedPercent
            )
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
}
