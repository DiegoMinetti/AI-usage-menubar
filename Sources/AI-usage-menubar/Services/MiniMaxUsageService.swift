import Foundation
import os

private let minimaxLogger = Logger(subsystem: "com.diegominetti.ai-usage-menubar", category: "MiniMaxUsageService")

@MainActor
final class MiniMaxUsageService {
    nonisolated static let defaultEndpoint = "https://www.minimax.io/v1/token_plan/remains"
    nonisolated private static let apiKeyKey = "minimax_token_plan_api_key"

    nonisolated(unsafe) private var timer: Timer?
    private(set) var cachedUsage: MiniMaxUsage = .empty

    var onUpdate: ((MiniMaxUsage) -> Void)?

    nonisolated static var hasAPIKey: Bool {
        guard let value = try? KeychainStorage.get(apiKeyKey) else { return false }
        return !value.isEmpty
    }

    nonisolated static func saveAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try KeychainStorage.delete(apiKeyKey)
        } else {
            try KeychainStorage.set(trimmed, forKey: apiKeyKey)
        }
    }

    nonisolated static func clearAPIKey() throws {
        try KeychainStorage.delete(apiKeyKey)
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 300, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() { refresh() }

    func refresh() {
        Task { [weak self] in
            let usage = await Self.fetchUsage()
            guard let self else { return }
            self.cachedUsage = usage
            self.onUpdate?(usage)
        }
    }

    nonisolated static func fetchUsage() async -> MiniMaxUsage {
        guard let apiKey = try? KeychainStorage.get(apiKeyKey), !apiKey.isEmpty else {
            return .empty
        }

        guard let url = URL(string: defaultEndpoint) else { return .empty }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return failure("No HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                return failure("HTTP \(http.statusCode)")
            }
            let json = try JSONSerialization.jsonObject(with: data)
            if let error = responseError(from: json) {
                return failure(error)
            }
            let windows = extractWindows(from: json)
            return MiniMaxUsage(
                windows: windows,
                fetchedAt: Date(),
                status: windows.isEmpty ? "No quota data" : "Connected",
                errorMessage: nil,
                sourceURL: defaultEndpoint
            )
        } catch {
            minimaxLogger.error("MiniMax usage fetch failed: \(error.localizedDescription, privacy: .public)")
            return failure(error.localizedDescription)
        }
    }

    nonisolated private static func failure(_ message: String) -> MiniMaxUsage {
        MiniMaxUsage(
            windows: [],
            fetchedAt: Date(),
            status: "Error",
            errorMessage: message,
            sourceURL: defaultEndpoint
        )
    }

    nonisolated private static func responseError(from json: Any) -> String? {
        guard let root = json as? [String: Any],
              let base = root["base_resp"] as? [String: Any] else { return nil }
        let statusCode = intValue(base["status_code"]) ?? 0
        guard statusCode != 0 else { return nil }
        return stringValue(base["status_msg"]) ?? "MiniMax status \(statusCode)"
    }

    nonisolated private static func extractWindows(from json: Any) -> [MiniMaxLimitWindow] {
        var windows: [MiniMaxLimitWindow] = []

        if let root = json as? [String: Any] {
            let models = arrayValue(root["model_remains"])
                ?? arrayValue(root["models"])
                ?? arrayValue(root["data"])
                ?? []

            for item in models {
                guard let object = item as? [String: Any] else { continue }
                windows.append(contentsOf: windowsFromModelObject(object))
            }

            if windows.isEmpty {
                windows.append(contentsOf: windowsFromModelObject(root))
            }
        }

        return deduplicate(windows)
    }

    nonisolated private static func windowsFromModelObject(_ object: [String: Any]) -> [MiniMaxLimitWindow] {
        let modelName = stringValue(object["model_name"])
            ?? stringValue(object["modelName"])
            ?? stringValue(object["name"])
            ?? "general"

        var windows: [MiniMaxLimitWindow] = []

        if let window = buildWindow(
            object: object,
            modelName: modelName,
            periodLabel: "5 h",
            usedKeys: ["current_interval_used_count", "interval_used_count", "used_count"],
            remainingKeys: ["current_interval_remaining_count", "current_interval_usage_count", "interval_remaining_count", "remaining_count"],
            limitKeys: ["current_interval_total_count", "interval_total_count", "total_count"],
            usedPercentKeys: ["current_interval_used_percent", "interval_used_percent", "used_percent"],
            remainingPercentKeys: ["current_interval_remaining_percent", "interval_remaining_percent", "remaining_percent"],
            resetKeys: ["current_interval_reset_at", "interval_reset_at", "reset_at", "resetAt"]
        ) {
            windows.append(window)
        }

        if let window = buildWindow(
            object: object,
            modelName: modelName,
            periodLabel: "Weekly",
            usedKeys: ["current_weekly_used_count", "weekly_used_count"],
            remainingKeys: ["current_weekly_remaining_count", "current_weekly_usage_count", "weekly_remaining_count"],
            limitKeys: ["current_weekly_total_count", "weekly_total_count"],
            usedPercentKeys: ["current_weekly_used_percent", "weekly_used_percent"],
            remainingPercentKeys: ["current_weekly_remaining_percent", "weekly_remaining_percent"],
            resetKeys: ["current_weekly_reset_at", "weekly_reset_at", "reset_at", "resetAt"]
        ) {
            windows.append(window)
        }

        return windows
    }

    nonisolated private static func buildWindow(
        object: [String: Any],
        modelName: String,
        periodLabel: String,
        usedKeys: [String],
        remainingKeys: [String],
        limitKeys: [String],
        usedPercentKeys: [String],
        remainingPercentKeys: [String],
        resetKeys: [String]
    ) -> MiniMaxLimitWindow? {
        let limit = firstNumber(object, keys: limitKeys)
        let remaining = firstNumber(object, keys: remainingKeys)
        let rawUsed = firstNumber(object, keys: usedKeys)
        let used = rawUsed ?? {
            guard let limit, let remaining else { return nil }
            return max(limit - remaining, 0)
        }()
        let remainingPercent = firstNumber(object, keys: remainingPercentKeys)
        let usedPercent = firstNumber(object, keys: usedPercentKeys) ?? remainingPercent.map { max(100 - $0, 0) }
        let resetAt = firstNumber(object, keys: resetKeys).map(dateFromEpoch)

        guard limit != nil || remaining != nil || used != nil || remainingPercent != nil || usedPercent != nil else {
            return nil
        }

        return MiniMaxLimitWindow(
            modelName: modelName,
            periodLabel: periodLabel,
            used: used,
            remaining: remaining,
            limit: limit,
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
            resetAt: resetAt
        )
    }

    nonisolated private static func deduplicate(_ windows: [MiniMaxLimitWindow]) -> [MiniMaxLimitWindow] {
        var byKey: [String: MiniMaxLimitWindow] = [:]
        for window in windows {
            let key = "\(window.modelName)-\(window.periodLabel)"
            byKey[key] = window
        }
        return byKey.values.sorted {
            if $0.modelName == $1.modelName { return $0.periodLabel < $1.periodLabel }
            return $0.modelName < $1.modelName
        }
    }

    nonisolated private static func firstNumber(_ object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = numberValue(object[key]) { return value }
        }
        return nil
    }

    nonisolated private static func numberValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    nonisolated private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        return nil
    }

    nonisolated private static func arrayValue(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    nonisolated private static func dateFromEpoch(_ value: Double) -> Date {
        if value > 10_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000.0)
        }
        return Date(timeIntervalSince1970: value)
    }
}
