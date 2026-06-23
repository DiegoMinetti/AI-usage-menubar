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
    private var minimaxService:     MiniMaxUsageService!
    private let updateService = AppUpdateService()

    private var loginWindow: GitHubLoginWindow?
    private var hostingMenuItem: NSMenuItem!
    private var hostingView: NSHostingView<MenuContentView>!
    private var desktopWidgetWindow: NSPanel?
    private var desktopWidgetMenuItem: NSMenuItem!
    private var mainWindow: NSWindow?
    private var mainWindowHostingView: NSHostingView<MainWindowView>?

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
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

        let openDashboard = NSMenuItem(title: "Open AI Usage", action: #selector(openMainWindow), keyEquivalent: "")
        openDashboard.target = self
        menu.addItem(openDashboard)

        let openSettings = NSMenuItem(title: "Settings", action: #selector(openSettingsWindow), keyEquivalent: ",")
        openSettings.target = self
        menu.addItem(openSettings)

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

        // ── MiniMax Token Plan usage ──────────────────────────────
        minimaxService = MiniMaxUsageService()
        vm.minimaxUsage = minimaxService.cachedUsage
        minimaxService.onUpdate = { [weak self] usage in
            self?.vm.minimaxUsage = usage
            self?.vm.isMiniMaxConfigured = MiniMaxUsageService.hasAPIKey
            self?.updateStatusBar()
            self?.saveSnapshot()
        }
        minimaxService.start()

        // Manual refresh from UI
        vm.onRefresh = { [weak self] in
            guard let self = self else { return }
            self.copilotService.refresh()
            self.claudeService.refresh()
            self.codexService.refresh()
            self.minimaxService.refresh()
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
        vm.onOpenMainWindow = { [weak self] in
            self?.showMainWindow(tab: .dashboard)
        }
        vm.onOpenSettingsWindow = { [weak self] in
            self?.showMainWindow(tab: .settings)
        }
        vm.onOpenChartSettingsWindow = { [weak self] in
            self?.showMainWindow(tab: .chartSettings)
        }

        updateService.startIfEnabled(vm.settings.autoUpdateFromMain)
        saveSnapshot()
    }

    // MARK: - Status bar title

    private func updateStatusBar() {
        guard let btn = statusItem.button else { return }
        let providers = vm.settings.orderedMenuBarProviders
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
                return "Cl \(vm.displayCompactLabel(for: .claude))"
            case .copilot:
                return "Co \(vm.displayCompactLabel(for: .copilot))"
            case .codex:
                return "Cx \(vm.displayCompactLabel(for: .codex))"
            case .minimax:
                return "Mx \(vm.displayCompactLabel(for: .minimax))"
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
        let minimaxSummary = vm.summary(for: .minimax)

        let services = [
                UsageSnapshot.Service(
                    id: "claude",
                    name: "Claude Code",
                    detail: "\(formatCount(vm.claudeUsage.weeklyTokens)) last 7d",
                    usedLabel: vm.displayCompactLabel(for: .claude),
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
                    updatedAt: claudeSummary.updatedAt,
                    chartPoints: vm.chartPoints(for: .claude)
                ),
                UsageSnapshot.Service(
                    id: "copilot",
                    name: "GitHub Copilot",
                    detail: vm.copilotUsage.map { "\(String(format: "%.1f", $0.remainingPercentage))% available" } ?? "Not connected",
                    usedLabel: vm.displayCompactLabel(for: .copilot),
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
                    updatedAt: copilotSummary.updatedAt,
                    chartPoints: vm.chartPoints(for: .copilot)
                ),
                UsageSnapshot.Service(
                    id: "codex",
                    name: "ChatGPT / Codex",
                    detail: codexSnapshotDetail(vm.codexUsage),
                    usedLabel: vm.displayCompactLabel(for: .codex),
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
                    updatedAt: codexSummary.updatedAt,
                    chartPoints: vm.chartPoints(for: .codex)
                ),
                UsageSnapshot.Service(
                    id: "minimax",
                    name: "MiniMax",
                    detail: minimaxSnapshotDetail(vm.minimaxUsage),
                    usedLabel: vm.displayCompactLabel(for: .minimax),
                    percentage: vm.minimaxUsage.primaryWindow?.displayUsedPercent,
                    status: vm.isMiniMaxConfigured ? vm.minimaxUsage.status : "Not configured",
                    tintHex: "#2563EB",
                    resetLabel: vm.minimaxUsage.primaryWindow?.resetAt.map { "Resets \(relativeTime(to: $0))" },
                    usedValue: minimaxSummary.used,
                    remainingValue: minimaxSummary.remaining,
                    limitValue: minimaxSummary.limit,
                    unit: minimaxSummary.unit.rawValue,
                    periodLabel: minimaxSummary.periodLabel,
                    periodStart: minimaxSummary.periodStart,
                    periodEnd: minimaxSummary.periodEnd,
                    resetAt: minimaxSummary.resetDate,
                    updatedAt: minimaxSummary.updatedAt,
                    chartPoints: vm.chartPoints(for: .minimax)
                )
            ].filter { service in
                guard let provider = UsageProviderID(rawValue: service.id) else { return true }
                return vm.settings.showsProviderInWidget(provider)
            }
        let byID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
        let orderedServices = vm.settings.orderedWidgetProviders.compactMap { byID[$0.rawValue] }

        UsageSnapshotStore.save(UsageSnapshot(
            generatedAt: Date(),
            services: orderedServices
        ))
        WidgetCenter.shared.reloadTimelines(ofKind: "AIUsageWidget")
        WidgetCenter.shared.reloadAllTimelines()
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

    @objc private func openMainWindow() {
        showMainWindow(tab: .dashboard)
    }

    @objc private func openSettingsWindow() {
        showMainWindow(tab: .settings)
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: rawURL) else {
            showMainWindow(tab: .dashboard)
            return
        }

        switch url.host {
        case "charts":
            showMainWindow(tab: .chartSettings)
        case "settings":
            showMainWindow(tab: .settings)
        default:
            showMainWindow(tab: .dashboard)
        }
    }

    private func showMainWindow(tab: MainWindowTab) {
        if mainWindow == nil {
            let content = MainWindowView(vm: vm, selectedTab: tab)
            let hosting = NSHostingView(rootView: content)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "AI Usage"
            window.center()
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            mainWindow = window
            mainWindowHostingView = hosting
        } else {
            mainWindowHostingView?.rootView = MainWindowView(vm: vm, selectedTab: tab)
        }

        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

private func minimaxSnapshotDetail(_ usage: MiniMaxUsage) -> String {
    guard usage.hasUsageData else {
        return usage.errorMessage ?? usage.status
    }

    let parts = usage.windows.prefix(3).map { window -> String in
        if let remainingPercent = window.displayRemainingPercent {
            return "\(window.periodLabel) \(String(format: "%.0f%%", remainingPercent))"
        }
        if let remaining = window.remaining {
            return "\(window.periodLabel) \(formatCount(Int(remaining))) left"
        }
        return window.periodLabel
    }
    return parts.joined(separator: " · ")
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
