import Foundation
import os

private let settingsLogger = Logger(subsystem: "com.diegominetti.ai-usage-menubar", category: "AppSettingsStore")

enum AppSettingsStore {
    private static let fileName = "app_settings.json"

    static var settingsURL: URL {
        let fm = FileManager.default
        do {
            let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent("AI Usage", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent(fileName)
        } catch {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        }
    }

    static func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL) else {
            let defaults = AppSettings.default
            save(defaults)
            return defaults
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            settingsLogger.error("Failed to load settings: \(error.localizedDescription, privacy: .public)")
            let defaults = AppSettings.default
            save(defaults)
            return defaults
        }
    }

    static func save(_ settings: AppSettings) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: settingsURL, options: .atomic)
        } catch {
            settingsLogger.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
