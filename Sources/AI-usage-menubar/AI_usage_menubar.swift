import AppKit
import SwiftUI
import WidgetKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - Core objects
    private var statusItem: NSStatusItem!
    private let vm = MenuViewModel()

    private var copilotService:     CopilotUsageService!
    private var claudeService:      ClaudeUsageService!
    private var claudeStatusService: ClaudeStatusService!
    private var codexService:       ChatGPTCodexUsageService!
    private let updateService = AppUpdateService()

    private var loginWindow: GitHubLoginWindow?
    private var hostingMenuItem: NSMenuItem!
    private var hostingView: NSHostingView<MenuContentView>!
    private var desktopWidgetWindow: NSPanel?
    private var desktopWidgetMenuItem: NSMenuItem!

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        startServices()
    }

    // MARK: - Status item construction

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()

        let menu = NSMenu()
        menu.delegate = self

        // SwiftUI content pane
        let content = MenuContentView(vm: vm)
        hostingView = NSHostingView(rootView: content)
        hostingView.wantsLayer = true
        // Width fixed; height computed on menu open via menuWillOpen
        hostingView.frame = NSRect(x: 0, y: 0, width: 290, height: 290)

        hostingMenuItem = NSMenuItem()
        hostingMenuItem.view = hostingView
        menu.addItem(hostingMenuItem)

        menu.addItem(.separator())

        desktopWidgetMenuItem = NSMenuItem(title: "Show Desktop Widget", action: #selector(toggleDesktopWidget), keyEquivalent: "")
        desktopWidgetMenuItem.target = self
        menu.addItem(desktopWidgetMenuItem)

        let openCodexUsage = NSMenuItem(title: "Open Codex Usage", action: #selector(openCodexUsage), keyEquivalent: "")
        openCodexUsage.target = self
        menu.addItem(openCodexUsage)

        let openCodex = NSMenuItem(title: "Open Codex", action: #selector(openCodex), keyEquivalent: "")
        openCodex.target = self
        menu.addItem(openCodex)

        menu.addItem(.separator())

        let connect = NSMenuItem(title: "Connect GitHub", action: #selector(connectGitHub), keyEquivalent: "")
        connect.target = self
        menu.addItem(connect)

        let disconnect = NSMenuItem(title: "Disconnect GitHub", action: #selector(disconnectGitHub), keyEquivalent: "")
        disconnect.target = self
        menu.addItem(disconnect)

        menu.addItem(.separator())

        let update = NSMenuItem(title: "Update from main", action: #selector(updateFromMain), keyEquivalent: "")
        update.target = self
        menu.addItem(update)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func configureButton() {
        guard let btn = statusItem.button else { return }
        btn.title = "–"
        btn.font  = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }

    // MARK: - NSMenuDelegate — resize before open

    func menuWillOpen(_ menu: NSMenu) {
        let ideal = hostingView.fittingSize
        let height = max(ideal.height, 120)
        hostingView.frame = NSRect(x: 0, y: 0, width: 290, height: height)
        hostingMenuItem.view = hostingView
        desktopWidgetMenuItem.title = desktopWidgetWindow?.isVisible == true ? "Hide Desktop Widget" : "Show Desktop Widget"
    }

    // MARK: - Services wiring

    private func startServices() {
        // ── Copilot ──────────────────────────────────────────────
        copilotService = CopilotUsageService()
        if let cached = copilotService.cachedUsage {
            vm.copilotUsage = cached
        }
        copilotService.onUpdate = { [weak self] usage in
            self?.vm.copilotUsage = usage
            self?.vm.isGitHubConnected = true
            self?.updateStatusBar()
            self?.saveSnapshot()
        }
        copilotService.start()

        // ── Claude status ─────────────────────────────────────────
        claudeStatusService = ClaudeStatusService()
        claudeStatusService.onStatusChange = { [weak self] status in
            self?.vm.claudeStatus = status
            self?.updateStatusBar()
        }
        claudeStatusService.start()

        // ── Claude usage ──────────────────────────────────────────
        claudeService = ClaudeUsageService()
        vm.claudeUsage = claudeService.computeCurrentUsage()

        claudeService.onUpdate = { [weak self] usage in
            self?.vm.claudeUsage = usage
            self?.updateStatusBar()
            self?.saveSnapshot()
        }
        claudeService.start()

        // ── ChatGPT / Codex local usage ───────────────────────────
        codexService = ChatGPTCodexUsageService()
        vm.codexUsage = codexService.cachedUsage
        codexService.onUpdate = { [weak self] usage in
            self?.vm.codexUsage = usage
            self?.updateStatusBar()
            self?.saveSnapshot()
        }
        codexService.start()

        // Manual refresh from UI
        vm.onRefresh = { [weak self] in
            guard let self = self else { return }
            self.copilotService.refresh()
            self.claudeService.refresh()
            self.codexService.refresh()
            // trigger a quick status check for Claude CLI
            self.claudeStatusService.start()
            self.updateStatusBar()
            self.saveSnapshot()
        }

        vm.onSettingsChanged = { [weak self] in
            guard let self else { return }
            self.updateStatusBar()
            self.saveSnapshot()
            self.updateService.startIfEnabled(self.vm.settings.autoUpdateFromMain)
        }

        updateService.startIfEnabled(vm.settings.autoUpdateFromMain)
        saveSnapshot()
    }

    // MARK: - Status bar title

    private func updateStatusBar() {
        guard let btn = statusItem.button else { return }
        let providers = UsageProviderID.allCases.filter { vm.settings.showsProviderInMenuBar($0) }
        btn.image = nil
        btn.title = ""

        guard !providers.isEmpty else {
            btn.image = NSImage(systemSymbolName: "circle.grid.cross", accessibilityDescription: "AI Usage")
            btn.imagePosition = .imageOnly
            return
        }

        let parts = providers.map { provider -> String in
            switch provider {
            case .claude:
                return "Cl \(String(format: "%.0f%%", min(vm.claudeUsage.sessionPercentage, 100.0)))"
            case .copilot:
                return "Co \(vm.copilotUsage.map { String(format: "%.0f%%", $0.percentage) } ?? "-")"
            case .codex:
                if let fiveHour = vm.codexUsage.fiveHourWindow {
                    return "Cx \(String(format: "%.0f%%", fiveHour.remainingPercent))"
                }
                if let weekly = vm.codexUsage.weeklyWindow {
                    return "Cx \(String(format: "%.0f%%", weekly.remainingPercent))"
                }
                if let monthly = vm.codexUsage.monthlyLimit {
                    return "Cx \(String(format: "%.0f%%", monthly.remainingPercent))"
                }
                return "Cx \(formatCount(vm.codexUsage.weeklyTokens))"
            }
        }

        btn.imagePosition = .noImage
        btn.title = parts.joined(separator: " · ")
        btn.font  = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    }

    private func saveSnapshot() {
        let claudeSummary = vm.summary(for: .claude)
        let copilotSummary = vm.summary(for: .copilot)
        let codexSummary = vm.summary(for: .codex)

        UsageSnapshotStore.save(UsageSnapshot(
            generatedAt: Date(),
            services: [
                UsageSnapshot.Service(
                    id: "claude",
                    name: "Claude Code",
                    detail: "\(formatCount(vm.claudeUsage.weeklyTokens)) last 7d",
                    usedLabel: "\(formatCount(vm.claudeUsage.sessionTokens)) session",
                    percentage: min(max(vm.claudeUsage.sessionPercentage, 0), 100),
                    status: vm.claudeStatus.rawValue,
                    tintHex: "#DA7756",
                    resetLabel: vm.claudeUsage.sessionWindowEnd.map { "Session resets \(relativeTime(to: $0))" },
                    usedValue: claudeSummary.used,
                    remainingValue: claudeSummary.remaining,
                    limitValue: claudeSummary.limit,
                    unit: claudeSummary.unit.rawValue,
                    periodLabel: claudeSummary.periodLabel,
                    periodStart: claudeSummary.periodStart,
                    periodEnd: claudeSummary.periodEnd,
                    resetAt: claudeSummary.resetDate,
                    updatedAt: claudeSummary.updatedAt
                ),
                UsageSnapshot.Service(
                    id: "copilot",
                    name: "GitHub Copilot",
                    detail: vm.copilotUsage.map { "\(String(format: "%.1f", $0.remainingPercentage))% available" } ?? "Not connected",
                    usedLabel: vm.copilotUsage.map { String(format: "%.1f%% used", $0.percentage) } ?? "No data",
                    percentage: vm.copilotUsage?.percentage,
                    status: vm.isGitHubConnected ? "Connected" : "Not connected",
                    tintHex: "#8534F3",
                    resetLabel: vm.copilotUsage.map { "Resets \(relativeTime(to: $0.resetDate))" },
                    usedValue: copilotSummary.used,
                    remainingValue: copilotSummary.remaining,
                    limitValue: copilotSummary.limit,
                    unit: copilotSummary.unit.rawValue,
                    periodLabel: copilotSummary.periodLabel,
                    periodStart: copilotSummary.periodStart,
                    periodEnd: copilotSummary.periodEnd,
                    resetAt: copilotSummary.resetDate,
                    updatedAt: copilotSummary.updatedAt
                ),
                UsageSnapshot.Service(
                    id: "codex",
                    name: "ChatGPT / Codex",
                    detail: codexSnapshotDetail(vm.codexUsage),
                    usedLabel: codexSnapshotUsedLabel(vm.codexUsage),
                    percentage: codexSnapshotPercentage(vm.codexUsage),
                    status: vm.codexUsage.hasQuotaData ? "Usage" : (vm.codexUsage.lastModel ?? "Local"),
                    tintHex: "#10A37F",
                    resetLabel: codexSnapshotResetLabel(vm.codexUsage),
                    usedValue: codexSummary.used,
                    remainingValue: codexSummary.remaining,
                    limitValue: codexSummary.limit,
                    unit: codexSummary.unit.rawValue,
                    periodLabel: codexSummary.periodLabel,
                    periodStart: codexSummary.periodStart,
                    periodEnd: codexSummary.periodEnd,
                    resetAt: codexSummary.resetDate,
                    updatedAt: codexSummary.updatedAt
                )
            ].filter { service in
                guard let provider = UsageProviderID(rawValue: service.id) else { return true }
                return vm.settings.showsProvider(provider)
            }
        ))
        WidgetCenter.shared.reloadTimelines(ofKind: "AIUsageWidget")
    }

    // MARK: - Actions

    @objc private func connectGitHub() {
        loginWindow = GitHubLoginWindow { [weak self] cookieHeader in
            CookieStorage.save(cookieHeader: cookieHeader)
            self?.vm.isGitHubConnected = true
            self?.copilotService.refresh()
            self?.loginWindow = nil
        }
        loginWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func disconnectGitHub() {
        CookieStorage.clear()
        vm.copilotUsage        = nil
        vm.isGitHubConnected   = false
        updateStatusBar()
        saveSnapshot()
    }

    @objc private func toggleDesktopWidget() {
        if desktopWidgetWindow?.isVisible == true {
            desktopWidgetWindow?.orderOut(nil)
            desktopWidgetMenuItem.title = "Show Desktop Widget"
            return
        }

        if desktopWidgetWindow == nil {
            let content = DesktopWidgetView(vm: vm)
            let panel = NSPanel(
                contentRect: NSRect(x: 80, y: 80, width: 320, height: 210),
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "AI Usage Widget"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: content)
            desktopWidgetWindow = panel
        }

        desktopWidgetWindow?.makeKeyAndOrderFront(nil)
        desktopWidgetMenuItem.title = "Hide Desktop Widget"
    }

    @objc private func openCodexUsage() {
        if let url = URL(string: "codex://settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openCodex() {
        let appURL = URL(fileURLWithPath: "/Applications/Codex.app")
        NSWorkspace.shared.open(appURL)
    }

    @objc private func updateFromMain() {
        updateService.installFromMain(interactive: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private func formatCount(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
    return "\(value)"
}

private func relativeTime(to date: Date) -> String {
    let delta = date.timeIntervalSinceNow
    let seconds = abs(Int(delta))
    let suffix = delta >= 0 ? "in" : "ago"
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60

    let value: String
    if days > 0 { value = hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
    else if hours > 0 { value = "\(hours)h \(minutes)m" }
    else if minutes > 0 { value = "\(minutes)m" }
    else { value = "now" }

    return delta >= 0 ? "\(suffix) \(value)" : "\(value) \(suffix)"
}

private func codexSnapshotUsedLabel(_ usage: ChatGPTCodexUsage) -> String {
    if let fiveHour = usage.fiveHourWindow {
        return String(format: "%.0f%% 5h left", fiveHour.remainingPercent)
    }
    if let weekly = usage.weeklyWindow {
        return String(format: "%.0f%% weekly left", weekly.remainingPercent)
    }
    if let monthly = usage.monthlyLimit {
        return String(format: "%.0f%% monthly left", monthly.remainingPercent)
    }
    return "\(formatCount(usage.weeklyTokens)) last 7d"
}

private func codexSnapshotDetail(_ usage: ChatGPTCodexUsage) -> String {
    if let fiveHour = usage.fiveHourWindow, let weekly = usage.weeklyWindow {
        return String(format: "5h %.0f%% · Weekly %.0f%%", fiveHour.remainingPercent, weekly.remainingPercent)
    }
    if let monthly = usage.monthlyLimit {
        return "Monthly \(formatCount(Int(monthly.remaining))) remaining"
    }
    return "\(usage.activeThreads) active threads"
}

private func codexSnapshotPercentage(_ usage: ChatGPTCodexUsage) -> Double? {
    if let fiveHour = usage.fiveHourWindow { return fiveHour.usedPercent }
    if let weekly = usage.weeklyWindow { return weekly.usedPercent }
    if let monthly = usage.monthlyLimit { return monthly.usedPercent }
    return nil
}

private func codexSnapshotResetLabel(_ usage: ChatGPTCodexUsage) -> String? {
    if let reset = usage.fiveHourWindow?.resetAt {
        return "5h resets \(relativeTime(to: reset))"
    }
    if let reset = usage.weeklyWindow?.resetAt {
        return "Weekly resets \(relativeTime(to: reset))"
    }
    if let reset = usage.monthlyLimit?.resetAt {
        return "Monthly resets \(relativeTime(to: reset))"
    }
    return usage.lastUpdated.map { "Updated \(relativeTime(to: $0))" }
}

// MARK: - App entry point

@main
@MainActor
struct AppMain {
    static func main() {
        let app      = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
