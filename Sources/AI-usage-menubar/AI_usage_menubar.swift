import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - Core objects
    private var statusItem: NSStatusItem!
    private let vm = MenuViewModel()

    private var copilotService:     CopilotUsageService!
    private var claudeService:      ClaudeUsageService!
    private var claudeStatusService: ClaudeStatusService!

    private var loginWindow: GitHubLoginWindow?
    private var hostingMenuItem: NSMenuItem!
    private var hostingView: NSHostingView<MenuContentView>!

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

        let connect = NSMenuItem(title: "Connect GitHub", action: #selector(connectGitHub), keyEquivalent: "")
        connect.target = self
        menu.addItem(connect)

        let disconnect = NSMenuItem(title: "Disconnect GitHub", action: #selector(disconnectGitHub), keyEquivalent: "")
        disconnect.target = self
        menu.addItem(disconnect)

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
        }
        claudeService.start()

        // Manual refresh from UI
        vm.onRefresh = { [weak self] in
            guard let self = self else { return }
            self.copilotService.refresh()
            self.claudeService.refresh()
            // trigger a quick status check for Claude CLI
            self.claudeStatusService.start()
            self.updateStatusBar()
        }
    }

    // MARK: - Status bar title

    private func updateStatusBar() {
        guard let btn = statusItem.button else { return }
        let usage = vm.claudeUsage

        // Claude: current 5h session % of monthly budget, capped at 100%
        let claudePct = String(format: "%.0f%%", min(usage.sessionPercentage, 100.0))

        // Copilot: current % if connected
        let copilotPct: String
        if let gu = vm.copilotUsage {
            copilotPct = String(format: "%.0f%%", gu.percentage)
        } else {
            copilotPct = "–"
        }

        btn.title = "\(claudePct) · \(copilotPct)"
        btn.font  = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
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
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
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
