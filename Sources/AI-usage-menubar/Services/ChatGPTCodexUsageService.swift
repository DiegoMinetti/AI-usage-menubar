import Foundation
import os

private let codexLogger = Logger(subsystem: "com.diegominetti.ai-usage-menubar", category: "ChatGPTCodexUsageService")

@MainActor
final class ChatGPTCodexUsageService {
    nonisolated(unsafe) private var timer: Timer?
    private(set) var cachedUsage: ChatGPTCodexUsage = .empty

    var onUpdate: ((ChatGPTCodexUsage) -> Void)?

    deinit {
        timer?.invalidate()
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() { refresh() }

    func refresh() {
        Task { [weak self] in
            let usage = await Self.computeUsage()
            guard let self else { return }
            self.cachedUsage = usage
            self.onUpdate?(usage)
        }
    }

    nonisolated static func computeUsage(now: Date = Date()) async -> ChatGPTCodexUsage {
        let local = computeLocalUsage(now: now)
        let quota = await fetchQuota()
        return merge(local: local, quota: quota)
    }

    nonisolated static func computeLocalUsage(now: Date = Date()) -> ChatGPTCodexUsage {
        let db = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite")
        guard FileManager.default.fileExists(atPath: db.path) else {
            return .empty
        }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let startOfWeek = cal.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? startOfToday

        let rows = runSQLite(
            dbPath: db.path,
            sql: """
            SELECT
              COALESCE(id, ''),
              COALESCE(title, ''),
              COALESCE(tokens_used, 0),
              COALESCE(model, ''),
              COALESCE(updated_at_ms, updated_at * 1000, 0),
              COALESCE(created_at_ms, created_at * 1000, 0),
              COALESCE(archived, 0)
            FROM threads
            WHERE model_provider = 'openai';
            """
        )

        guard !rows.isEmpty else {
            return ChatGPTCodexUsage.empty
        }

        var totalTokens = 0
        var monthlyTokens = 0
        var weeklyTokens = 0
        var todayTokens = 0
        var activeThreads = 0
        var archivedThreads = 0
        var daily: [String: Int] = [:]
        var lastUpdatedMs = 0
        var lastModel: String?

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"

        for row in rows {
            guard row.count >= 7 else { continue }
            let tokens = Int(row[2]) ?? 0
            let model = row[3].isEmpty ? nil : row[3]
            let updatedMs = Int(row[4]) ?? 0
            let createdMs = Int(row[5]) ?? updatedMs
            let archived = (Int(row[6]) ?? 0) != 0

            totalTokens += tokens
            if archived { archivedThreads += 1 } else { activeThreads += 1 }

            if updatedMs > lastUpdatedMs {
                lastUpdatedMs = updatedMs
                lastModel = model
            }

            let attributionDate = Date(timeIntervalSince1970: Double(max(createdMs, updatedMs)) / 1000.0)
            let dayKey = df.string(from: attributionDate)
            daily[dayKey, default: 0] += tokens

            if attributionDate >= startOfMonth { monthlyTokens += tokens }
            if attributionDate >= startOfWeek { weeklyTokens += tokens }
            if attributionDate >= startOfToday { todayTokens += tokens }
        }

        let history = (0..<30).compactMap { offset -> CodexDailyTokens? in
            guard let day = cal.date(byAdding: .day, value: offset - 29, to: startOfToday) else { return nil }
            let key = df.string(from: day)
            return CodexDailyTokens(date: key, tokens: daily[key, default: 0])
        }

        return ChatGPTCodexUsage(
            totalTokens: totalTokens,
            monthlyTokens: monthlyTokens,
            weeklyTokens: weeklyTokens,
            todayTokens: todayTokens,
            activeThreads: activeThreads,
            archivedThreads: archivedThreads,
            lastUpdated: lastUpdatedMs > 0 ? Date(timeIntervalSince1970: Double(lastUpdatedMs) / 1000.0) : nil,
            lastModel: lastModel,
            dailyHistory: history,
            sourcePath: db.path,
            limitWindows: [],
            monthlyLimit: nil,
            quotaFetchedAt: nil,
            quotaStatus: nil
        )
    }

    nonisolated private static func merge(local: ChatGPTCodexUsage, quota: CodexQuotaFetch?) -> ChatGPTCodexUsage {
        ChatGPTCodexUsage(
            totalTokens: local.totalTokens,
            monthlyTokens: local.monthlyTokens,
            weeklyTokens: local.weeklyTokens,
            todayTokens: local.todayTokens,
            activeThreads: local.activeThreads,
            archivedThreads: local.archivedThreads,
            lastUpdated: local.lastUpdated,
            lastModel: local.lastModel,
            dailyHistory: local.dailyHistory,
            sourcePath: local.sourcePath,
            limitWindows: quota?.limitWindows ?? [],
            monthlyLimit: quota?.monthlyLimit,
            quotaFetchedAt: quota?.fetchedAt,
            quotaStatus: quota?.status
        )
    }

    // MARK: - Codex quota fetch

    nonisolated private struct CodexQuotaFetch: Sendable {
        let limitWindows: [CodexLimitWindow]
        let monthlyLimit: CodexMonthlyLimit?
        let fetchedAt: Date
        let status: String?
    }

    nonisolated private struct CodexAuth: Decodable {
        struct Tokens: Decodable {
            let accessToken: String?
            let accountId: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case accountId = "account_id"
            }
        }

        let tokens: Tokens?
    }

    nonisolated private static func fetchQuota() async -> CodexQuotaFetch? {
        guard let auth = loadCodexAuth(), let token = auth.tokens?.accessToken, !token.isEmpty else {
            return nil
        }

        let accountId = auth.tokens?.accountId

        let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 20
            return URLSession(configuration: config)
        }()

        var windows: [CodexLimitWindow] = []
        var monthly: CodexMonthlyLimit?

        let endpoints = [
            "https://chatgpt.com/backend-api/codex/wham/accounts/check",
            "https://chatgpt.com/backend-api/codex/wham/tasks/list?limit=1",
            "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27"
        ]

        for endpoint in endpoints {
            guard let url = URL(string: endpoint),
                  let json = await fetchJSON(url: url, token: token, accountId: accountId, session: session) else { continue }
            let foundWindows = extractLimitWindows(from: json)
            if !foundWindows.isEmpty { windows.append(contentsOf: foundWindows) }
            if monthly == nil { monthly = extractMonthlyLimit(from: json) }
        }

        if monthly == nil, let accountId, !accountId.isEmpty {
            let escaped = accountId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? accountId
            if let url = URL(string: "https://chatgpt.com/backend-api/accounts/\(escaped)/spend-controls/current-user/monthly-usage"),
               let json = await fetchJSON(url: url, token: token, accountId: accountId, session: session) {
                monthly = extractMonthlyLimit(from: json)
            }
        }

        if windows.isEmpty {
            windows = extractLimitWindowsFromLogs()
        }

        let deduped = deduplicate(windows: windows).sorted { $0.windowMinutes < $1.windowMinutes }
        guard !deduped.isEmpty || monthly != nil else { return nil }
        return CodexQuotaFetch(limitWindows: deduped, monthlyLimit: monthly, fetchedAt: Date(), status: "Codex quota")
    }

    nonisolated private static func loadCodexAuth() -> CodexAuth? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CodexAuth.self, from: data)
    }

    nonisolated private static func fetchJSON(url: URL, token: String, accountId: String?, session: URLSession) async -> Any? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "OAI-Language")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            codexLogger.debug("Codex quota fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    nonisolated private static func extractLimitWindows(from json: Any) -> [CodexLimitWindow] {
        var windows: [CodexLimitWindow] = []
        visitJSON(json) { object in
            guard object["used_percent"] != nil,
                  object["limit_window_seconds"] != nil || object["window_minutes"] != nil else { return }
            guard let used = numberValue(object["used_percent"]) else { return }
            let minutes = numberValue(object["window_minutes"]) ?? ((numberValue(object["limit_window_seconds"]) ?? 0) / 60)
            guard minutes > 0 else { return }
            let resetAt = numberValue(object["reset_at"]).map { Date(timeIntervalSince1970: $0) }
            windows.append(CodexLimitWindow(
                label: label(forWindowMinutes: minutes),
                windowMinutes: minutes,
                usedPercent: used,
                resetAt: resetAt
            ))
        }
        return windows
    }

    nonisolated private static func extractLimitWindowsFromLogs() -> [CodexLimitWindow] {
        let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/logs_2.sqlite")
        guard FileManager.default.fileExists(atPath: db.path) else { return [] }

        let rows = runSQLite(
            dbPath: db.path,
            sql: """
            SELECT replace(replace(COALESCE(feedback_log_body, ''), char(10), ' '), char(13), ' ')
            FROM logs
            WHERE feedback_log_body LIKE '%codex.rate_limits%'
              AND feedback_log_body LIKE '%used_percent%'
              AND feedback_log_body NOT LIKE '%SELECT %'
            ORDER BY ts DESC, ts_nanos DESC
            LIMIT 40;
            """
        )

        var windows: [CodexLimitWindow] = []
        for row in rows {
            guard let text = row.first else { continue }
            windows.append(contentsOf: extractLimitWindows(fromText: text))
        }
        return deduplicate(windows: windows)
    }

    nonisolated private static func extractLimitWindows(fromText text: String) -> [CodexLimitWindow] {
        let pattern = #"\{[^{}]*"used_percent"[^{}]*(?:"limit_window_seconds"|"window_minutes")[^{}]*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        return matches.compactMap { match in
            let object = ns.substring(with: match.range)
            guard let used = number(in: object, key: "used_percent"),
                  let minutes = number(in: object, key: "window_minutes") ?? number(in: object, key: "limit_window_seconds").map({ $0 / 60 }),
                  minutes > 0 else { return nil }
            let resetAt = number(in: object, key: "reset_at").map { Date(timeIntervalSince1970: $0) }
            return CodexLimitWindow(
                label: label(forWindowMinutes: minutes),
                windowMinutes: minutes,
                usedPercent: used,
                resetAt: resetAt
            )
        }
    }

    nonisolated private static func extractMonthlyLimit(from json: Any) -> CodexMonthlyLimit? {
        var result: CodexMonthlyLimit?
        visitJSON(json) { object in
            guard result == nil else { return }
            let current = numberValue(object["current_month_usage"])
            let directLimit = numberValue(object["monthly_limit"]) ?? numberValue(object["limit"])
            let nestedLimit: Double? = {
                guard let effective = object["effective_monthly_limit"] as? [String: Any] else { return nil }
                return numberValue(effective["limit"])
            }()
            guard let used = current ?? numberValue(object["used"]),
                  let limit = nestedLimit ?? directLimit,
                  limit >= 0 else { return }

            let resetAt = numberValue(object["reset_at"] ?? object["renewal_at"] ?? object["renews_at"])
                .map { Date(timeIntervalSince1970: $0) }
            result = CodexMonthlyLimit(used: used, limit: limit, resetAt: resetAt ?? nextMonthStart())
        }
        return result
    }

    nonisolated private static func visitJSON(_ value: Any, _ body: ([String: Any]) -> Void) {
        if let object = value as? [String: Any] {
            body(object)
            for child in object.values { visitJSON(child, body) }
        } else if let array = value as? [Any] {
            for child in array { visitJSON(child, body) }
        }
    }

    nonisolated private static func numberValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    nonisolated private static func number(in text: String, key: String) -> Double? {
        let pattern = #"""# + NSRegularExpression.escapedPattern(for: key) + #""\s*:\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return Double(ns.substring(with: match.range(at: 1)))
    }

    nonisolated private static func label(forWindowMinutes minutes: Double) -> String {
        if abs(minutes - 300) <= 1 { return "5 h" }
        if abs(minutes - 10_080) <= 60 { return "Semanal" }
        if abs(minutes - 43_200) <= 1_440 { return "Mensual" }
        if minutes >= 1_440 { return "\(Int((minutes / 1_440).rounded())) d" }
        if minutes >= 60 { return "\(Int((minutes / 60).rounded())) h" }
        return "\(Int(minutes.rounded())) min"
    }

    nonisolated private static func nextMonthStart() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: comps) ?? now
        return calendar.date(byAdding: .month, value: 1, to: start) ?? now
    }

    nonisolated private static func deduplicate(windows: [CodexLimitWindow]) -> [CodexLimitWindow] {
        var byLabel: [String: CodexLimitWindow] = [:]
        for window in windows {
            let key = window.normalizedLabel
            if let existing = byLabel[key] {
                byLabel[key] = window.usedPercent >= existing.usedPercent ? window : existing
            } else {
                byLabel[key] = window
            }
        }
        return Array(byLabel.values)
    }

    nonisolated private static func runSQLite(dbPath: String, sql: String) -> [[String]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-separator", "\t", dbPath, sql]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            codexLogger.error("Failed to launch sqlite3: \(error.localizedDescription, privacy: .public)")
            return []
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = error.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            codexLogger.error("sqlite3 failed: \(message, privacy: .public)")
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        }
    }
}
