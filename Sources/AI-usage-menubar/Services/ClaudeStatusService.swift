import Foundation
import os

private let claudeStatusLogger = Logger(subsystem: "com.diegominetti.ai-usage-menubar", category: "ClaudeStatusService")

enum ClaudeCLIStatus: String, Sendable {
    case notInstalled     = "Not installed"
    case notAuthenticated = "Not authenticated"
    case connected        = "Connected"
}

@MainActor
final class ClaudeStatusService {
    nonisolated(unsafe) private var timer: Timer?
    private(set) var status: ClaudeCLIStatus = .notInstalled
    /// Called on the main actor whenever the status changes (or on first detection).
    var onStatusChange: ((ClaudeCLIStatus) -> Void)?

    deinit {
        timer?.invalidate()
    }

    func start() {
        checkOnce()
        timer?.invalidate()
        // CLI installation / auth state changes rarely — check every 5 minutes.
        timer = Timer.scheduledTimer(timeInterval: 300, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() { checkOnce() }

    private func checkOnce() {
        Task { [weak self] in
            let s = await Task.detached { Self.detectStatus() }.value
            guard let self else { return }
            let changed = self.status != s
            self.status = s
            if changed {
                claudeStatusLogger.debug("Claude CLI status → \(s.rawValue, privacy: .public)")
            }
            self.onStatusChange?(s)
        }
    }

    // MARK: - Detection (nonisolated — runs off the main actor)

    nonisolated static func detectStatus() -> ClaudeCLIStatus {
        guard let path = runAndCapture("/usr/bin/which", ["claude"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else { return .notInstalled }

        // API key in environment → treat as connected immediately
        if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil { return .connected }

        // Quick CLI smoke-test
        if runAndCapture(path, ["--version"]) != nil { return .connected }
        return .notAuthenticated
    }

    nonisolated static func runAndCapture(_ launchPath: String, _ arguments: [String]) -> String? {
        let p = Process()
        if launchPath.contains("/") {
            p.executableURL = URL(fileURLWithPath: launchPath)
            p.arguments = arguments
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = [launchPath] + arguments
        }
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
