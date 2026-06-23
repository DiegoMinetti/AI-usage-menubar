import AppKit
import Foundation
import os

private let updateLogger = Logger(subsystem: "com.diegominetti.ai-usage-menubar", category: "AppUpdateService")

@MainActor
final class AppUpdateService {
    nonisolated(unsafe) private var timer: Timer?
    private var isUpdating = false
    private let lastKnownMainSHAKey = "AIUsageLastKnownMainSHA"

    func startIfEnabled(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        timer = Timer.scheduledTimer(timeInterval: 21_600, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func installFromMain(interactive: Bool) {
        guard !isUpdating else { return }
        isUpdating = true

        Task {
            let result: UpdateResult
            if interactive {
                result = await Self.runInstallerFromMain()
            } else {
                result = await autoUpdateIfNeeded()
            }
            await MainActor.run {
                self.isUpdating = false
                if interactive || !result.success {
                    self.showResult(result)
                }
            }
        }
    }

    @objc private func timerFired() {
        installFromMain(interactive: false)
    }

    private func autoUpdateIfNeeded() async -> UpdateResult {
        guard let remoteSHA = await Self.fetchMainSHA(), !remoteSHA.isEmpty else {
            return UpdateResult(success: false, output: "Could not read remote main SHA.")
        }

        let currentSHA = Bundle.main.object(forInfoDictionaryKey: "AIUsageMainCommit") as? String
        let storedSHA = UserDefaults.standard.string(forKey: lastKnownMainSHAKey)
        let knownSHA = currentSHA?.isEmpty == false ? currentSHA : storedSHA

        guard knownSHA != remoteSHA else {
            return UpdateResult(success: true, output: "Already on main \(remoteSHA).")
        }

        if knownSHA == nil {
            UserDefaults.standard.set(remoteSHA, forKey: lastKnownMainSHAKey)
            return UpdateResult(success: true, output: "Recorded current main \(remoteSHA).")
        }

        let result = await Self.runInstallerFromMain()
        if result.success {
            UserDefaults.standard.set(remoteSHA, forKey: lastKnownMainSHAKey)
        }
        return result
    }

    nonisolated private static func fetchMainSHA() async -> String? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["ls-remote", "https://github.com/DiegoMinetti/AI-usage-menubar.git", "refs/heads/main"]

            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return text.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" }).first.map(String.init)
            } catch {
                updateLogger.debug("Failed to fetch main SHA: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    nonisolated private static func runInstallerFromMain() async -> UpdateResult {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            if let script = Bundle.main.url(forResource: "install_from_main", withExtension: "sh") {
                process.arguments = [script.path]
            } else {
                process.arguments = [
                    "-lc",
                    "curl -fsSL https://raw.githubusercontent.com/DiegoMinetti/AI-usage-menubar/main/scripts/install_from_main.sh | bash"
                ]
            }

            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error

            do {
                try process.run()
                process.waitUntilExit()
                let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return UpdateResult(success: process.terminationStatus == 0, output: stdout + stderr)
            } catch {
                return UpdateResult(success: false, output: error.localizedDescription)
            }
        }.value
    }

    private func showResult(_ result: UpdateResult) {
        let alert = NSAlert()
        alert.messageText = result.success ? "Update finished" : "Update failed"
        alert.informativeText = result.output.isEmpty ? "No output was returned." : String(result.output.suffix(1_500))
        alert.alertStyle = result.success ? .informational : .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct UpdateResult: Sendable {
    let success: Bool
    let output: String
}
