import Foundation
import os

private let claudeLogger = Logger(subsystem: "com.diegominetti.ai-usage-menubar", category: "ClaudeUsageService")

// MARK: - JSONL entry structures (Decodable for efficient parsing)

private struct JSONLEntry: Decodable {
    let type: String
    let uuid: String?
    let timestamp: String?
    let message: JSONLMessage?
}

private struct JSONLMessage: Decodable {
    let usage: JSONLUsage?
}

private struct JSONLUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
}

// MARK: - Service

@MainActor
final class ClaudeUsageService {
    private let storageFileName = "claude.json"
    private let configFileName  = "config.json"
    nonisolated(unsafe) private var timer: Timer?
    private(set) var records: [ClaudeRecord] = []

    var onUpdate: ((ClaudeUsage) -> Void)?
    var onAnomalies: (([ClaudeAnomaly]) -> Void)?

    init() {
        _ = loadConfig()
        self.records = loadRecords()
        claudeLogger.debug("Initialized; records=\(self.records.count, privacy: .public)")
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        claudeLogger.debug("Starting ClaudeUsageService")
        timer?.invalidate()
        refresh()
        timer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    func stop() {
        claudeLogger.debug("Stopping ClaudeUsageService")
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() { refresh() }

    func refresh() {
        records = loadRecords()
        let usage = computeCurrentUsage()
        onUpdate?(usage)
        let anomalies = detectAnomalies()
        if !anomalies.isEmpty { onAnomalies?(anomalies) }
    }

    /// Manual record entry (kept for backward compatibility / testing).
    func addRecord(tokens: Int, date: Date = Date(), project: String? = nil) {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let rec = ClaudeRecord(
            date: df.string(from: date),
            tokens: tokens,
            project: project,
            timestamp: ISO8601DateFormatter().string(from: date)
        )
        records.append(rec)
        saveManualRecords(records.filter { $0.inputTokens == nil })
        onUpdate?(computeCurrentUsage())
    }

    // MARK: - Token parser (kept for any shell-output parsing use cases)

    nonisolated static func parseTokenString(_ input: String) -> Int? {
        guard let re = try? NSRegularExpression(
            pattern: #"↓?\s*([0-9]+(?:\.[0-9])?)\s*([kKmM]?)\s*tokens"#,
            options: .caseInsensitive
        ) else { return nil }

        let full = NSRange(input.startIndex..., in: input)
        guard let m = re.firstMatch(in: input, range: full),
              m.numberOfRanges >= 2,
              let numRange = Range(m.range(at: 1), in: input),
              let value = Double(String(input[numRange]).replacingOccurrences(of: ",", with: ""))
        else { return nil }

        var multiplier = 1.0
        if m.numberOfRanges >= 3, let sfxRange = Range(m.range(at: 2), in: input) {
            switch String(input[sfxRange]).lowercased() {
            case "k": multiplier = 1_000
            case "m": multiplier = 1_000_000
            default: break
            }
        }
        return Int((value * multiplier).rounded())
    }

    // MARK: - Primary: load from ~/.claude/projects/ JSONL files

    /// Reads all assistant usage entries from Claude Code's native JSONL session files.
    /// Falls back to the legacy custom JSON file if no JSONL data is found.
    private func loadRecords() -> [ClaudeRecord] {
        let jsonlRecords = loadRecordsFromCLIJSONL()
        if !jsonlRecords.isEmpty {
            claudeLogger.debug("Loaded \(jsonlRecords.count, privacy: .public) records from JSONL")
            return jsonlRecords
        }
        // Fallback to legacy custom wrapper file
        let legacy = loadLegacyRecords()
        claudeLogger.debug("Loaded \(legacy.count, privacy: .public) legacy records")
        return legacy
    }

    nonisolated private func loadRecordsFromCLIJSONL() -> [ClaudeRecord] {
        let fm = FileManager.default
        let projectsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard fm.fileExists(atPath: projectsDir.path) else { return [] }

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var records: [ClaudeRecord] = []
        var seenUUIDs = Set<String>()

        let decoder = JSONDecoder()

        for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }

            let projectName = projectDir.lastPathComponent

            guard let files = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { continue }

            let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }

            for jsonlFile in jsonlFiles {
                guard let content = try? String(contentsOf: jsonlFile, encoding: .utf8) else { continue }

                for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard let data = line.data(using: .utf8),
                          let entry = try? decoder.decode(JSONLEntry.self, from: data),
                          entry.type == "assistant",
                          let uuid = entry.uuid,
                          !seenUUIDs.contains(uuid),
                          let usage = entry.message?.usage,
                          let outputTokens = usage.output_tokens,
                          outputTokens > 0,
                          let timestamp = entry.timestamp,
                          timestamp.count >= 10
                    else { continue }

                    seenUUIDs.insert(uuid)

                    let inputTokens        = usage.input_tokens ?? 0
                    let cacheCreation      = usage.cache_creation_input_tokens ?? 0
                    let cacheRead          = usage.cache_read_input_tokens ?? 0
                    let date               = String(timestamp.prefix(10))   // "yyyy-MM-dd"

                    records.append(ClaudeRecord(
                        date: date,
                        project: projectName,
                        timestamp: timestamp,
                        inputTokens: inputTokens,
                        outputTokens: outputTokens,
                        cacheCreationTokens: cacheCreation,
                        cacheReadTokens: cacheRead
                    ))
                }
            }
        }

        return records
    }

    // MARK: - Legacy storage (custom JSON wrapper, fallback)

    private var storageURL: URL {
        let fm = FileManager.default
        do {
            let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent("ai-usage-tracker", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent(storageFileName)
        } catch {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(storageFileName)
        }
    }

    var storageFilePath: String { storageURL.path }

    private var configURL: URL {
        let fm = FileManager.default
        do {
            let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent("ai-usage-tracker", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent(configFileName)
        } catch {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(configFileName)
        }
    }

    private func loadLegacyRecords() -> [ClaudeRecord] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        do {
            let recs = try JSONDecoder().decode([ClaudeRecord].self, from: Data(contentsOf: storageURL))
            return recs
        } catch {
            claudeLogger.error("Failed to load legacy records: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func saveManualRecords(_ manualRecords: [ClaudeRecord]) {
        do {
            let enc = JSONEncoder(); enc.outputFormatting = .prettyPrinted
            try enc.encode(manualRecords).write(to: storageURL, options: .atomic)
        } catch {
            claudeLogger.error("Failed to save records: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Config

    private func loadConfig() -> ClaudeConfig {
        if FileManager.default.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let cfg  = try? JSONDecoder().decode(ClaudeConfig.self, from: data) {
            return cfg
        }
        let def = ClaudeConfig.default()
        let enc = JSONEncoder(); enc.outputFormatting = .prettyPrinted
        try? enc.encode(def).write(to: configURL, options: .atomic)
        return def
    }

    private func saveConfig(_ cfg: ClaudeConfig) {
        do {
            let enc = JSONEncoder(); enc.outputFormatting = .prettyPrinted
            try enc.encode(cfg).write(to: configURL, options: .atomic)
        } catch {
            claudeLogger.error("Failed to save config: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Billing cycles

    func listBillingCycles() -> [BillingCycle] { loadConfig().billing_cycles ?? [] }

    @discardableResult
    func addBillingCycle(start: Date, end: Date, name: String? = nil) -> BillingCycle {
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
        let s = df.string(from: start); let e = df.string(from: end)
        let cycle = BillingCycle(id: name ?? "cycle_\(s)_\(e)", name: name, startDate: s, endDate: e)
        var cfg = loadConfig()
        var cycles = cfg.billing_cycles ?? []; cycles.append(cycle)
        cfg.billing_cycles = cycles; saveConfig(cfg)
        return cycle
    }

    @discardableResult
    func removeBillingCycle(id: String) -> Bool {
        var cfg = loadConfig()
        guard var cycles = cfg.billing_cycles else { return false }
        let before = cycles.count; cycles.removeAll { $0.id == id }
        cfg.billing_cycles = cycles; saveConfig(cfg)
        return cycles.count < before
    }

    // MARK: - Daily grouping

    func groupedByDay() -> [(String, Int)] {
        var dict: [String: Int] = [:]
        for r in records { dict[r.date, default: 0] += r.tokens }
        return dict.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    func dailyTotalsArray(lookbackDays: Int = 90) -> [(String, Int)] {
        let cal = Calendar.current
        let df  = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
        guard let start = cal.date(byAdding: .day, value: -(lookbackDays - 1), to: cal.startOfDay(for: Date()))
        else { return [] }
        return (0..<lookbackDays).compactMap { i -> (String, Int)? in
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { return nil }
            let s = df.string(from: d)
            let tokens = records.filter { $0.date == s }.reduce(0) { $0 + $1.tokens }
            return (s, tokens)
        }
    }

    // MARK: - Anomaly detection

    func detectAnomalies(lookbackDays: Int = 90, sigmaThreshold: Double = 3.0, prevMultiplier: Double = 3.0) -> [ClaudeAnomaly] {
        let totals = dailyTotalsArray(lookbackDays: lookbackDays)
        let values = totals.map { Double($0.1) }
        guard !values.isEmpty else { return [] }
        let mean = values.reduce(0, +) / Double(values.count)
        let std  = sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count))

        return totals.enumerated().compactMap { i, entry in
            let t = Double(entry.1)
            var reasons: [String] = []
            if std > 0 && t > mean + sigmaThreshold * std {
                reasons.append(String(format: "exceeds mean+%.1fσ", sigmaThreshold))
            }
            if i > 0 {
                let prev = Double(totals[i - 1].1)
                if prev > 0 && t > prev * prevMultiplier {
                    reasons.append(String(format: ">%.1fx previous day", prevMultiplier))
                }
            }
            guard !reasons.isEmpty else { return nil }
            return ClaudeAnomaly(
                date: entry.0, tokens: entry.1,
                reason: reasons.joined(separator: "; "),
                factor: mean > 0 ? t / mean : nil
            )
        }
    }

    // MARK: - 5-hour session window

    private func computeSessionWindow(cfg: ClaudeConfig) -> (tokens: Int, windowEnd: Date?, percentage: Double, limit: Int) {
        let windowDuration: TimeInterval = 5 * 3600
        let cutoff = Date().addingTimeInterval(-windowDuration)

        let inWindow: [(record: ClaudeRecord, date: Date)] = records.compactMap { r in
            guard let dt = parseRecordDateTime(r), dt >= cutoff else { return nil }
            return (r, dt)
        }

        let limit = cfg.effectiveSessionTokenLimit
        guard !inWindow.isEmpty else { return (0, nil, 0, limit) }

        let sessionTokens = inWindow.reduce(0) { $0 + $1.record.tokens }
        let windowStart   = inWindow.map { $0.date }.min()!
        let windowEnd     = windowStart.addingTimeInterval(windowDuration)

        let pct = (Double(sessionTokens) / Double(limit) * 100.0 * 10).rounded() / 10
        return (sessionTokens, windowEnd, pct, limit)
    }

    // MARK: - Weekly + monthly history

    private func computeWeeklyStats(cfg: ClaudeConfig) -> (tokens: Int, percentage: Double, limit: Int) {
        let raw   = dailyTotalsArray(lookbackDays: 7)
        let total = raw.reduce(0) { $0 + $1.1 }
        let weeklyLimit = cfg.effectiveWeeklyTokenLimit
        let pct = (Double(total) / Double(weeklyLimit) * 100 * 10).rounded() / 10
        return (total, pct, weeklyLimit)
    }

    private func computeDailyHistory() -> [DailyTokens] {
        dailyTotalsArray(lookbackDays: 30).map { DailyTokens(date: $0.0, tokens: $0.1) }
    }

    // MARK: - Current usage (main public API)

    func computeCurrentUsage(for cycle: BillingCycle? = nil) -> ClaudeUsage {
        let cfg = loadConfig()

        let cycleToUse: BillingCycle
        if let c = cycle {
            cycleToUse = c
        } else if let found = cfg.billing_cycles?.first(where: { cy in
            guard let s = dateFromYMD(cy.startDate), let e = dateFromYMD(cy.endDate) else { return false }
            let today = Calendar.current.startOfDay(for: Date())
            return today >= s && today <= e
        }) {
            cycleToUse = found
        } else {
            cycleToUse = currentMonthCycle()
        }

        let total = computeUsage(for: cycleToUse)
        let start = dateFromYMD(cycleToUse.startDate) ?? Calendar.current.startOfDay(for: Date())
        let cal   = Calendar.current
        let daysElapsed = max((cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: Date())).day ?? 0) + 1, 1)
        let dailyAvg    = (Double(total) / Double(daysElapsed) * 10).rounded() / 10
        let limit       = cfg.monthly_token_limit
        let monthlyPct  = limit > 0 ? min((Double(total) / Double(limit) * 100 * 10).rounded() / 10, 100.0) : 0.0

        let (sessionTokens, windowEnd, sessionPct, sessionLimit) = computeSessionWindow(cfg: cfg)
        let (weeklyTokens, weeklyPct, weeklyLimit) = computeWeeklyStats(cfg: cfg)
        let history = computeDailyHistory()

        // Monthly renewal date: first day after the current cycle ends
        let cycleEnd = dateFromYMD(cycleToUse.endDate) ?? start
        let renewalDate = Calendar.current.date(byAdding: .day, value: 1, to: cycleEnd) ?? cycleEnd

        return ClaudeUsage(
            totalTokens:        total,
            monthlyPercentage:  monthlyPct,
            dailyAverage:       dailyAvg,
            monthlyLimit:       cfg.monthly_token_limit,
            monthlyRenewalDate: renewalDate,
            sessionTokens:      sessionTokens,
            sessionPercentage:  sessionPct,
            sessionLimit:       sessionLimit,
            sessionWindowEnd:   windowEnd,
            dailyHistory:       history,
            weeklyTokens:       weeklyTokens,
            weeklyPercentage:   weeklyPct,
            weeklyLimit:        weeklyLimit
        )
    }

    func computeUsage(for cycle: BillingCycle) -> Int {
        guard let start = dateFromYMD(cycle.startDate), let end = dateFromYMD(cycle.endDate) else { return 0 }
        return records.reduce(0) { sum, r in
            guard let d = dateFromYMD(r.date), d >= start, d <= end else { return sum }
            return sum + r.tokens
        }
    }

    func estimatedRemainingDays(for usage: ClaudeUsage) -> Double? {
        let limit = loadConfig().monthly_token_limit
        let remaining = max(0, limit - usage.totalTokens)
        guard usage.dailyAverage > 0 else { return nil }
        return Double(remaining) / usage.dailyAverage
    }

    // MARK: - Last-activity helpers

    func lastRecordDateTime() -> Date? {
        records.compactMap { parseRecordDateTime($0) }.max()
    }

    func hasUsageWithin(hours: Int) -> Bool {
        guard let last = lastRecordDateTime() else { return false }
        return Date().timeIntervalSince(last) <= Double(hours * 3600)
    }

    // MARK: - Private date helpers

    private func currentMonthCycle() -> BillingCycle {
        let cal = Calendar.current; let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        var comps = DateComponents(); comps.month = 1; comps.day = -1
        let end = cal.date(byAdding: comps, to: start) ?? now
        return BillingCycle(id: "current_month", name: "Current Month", startDate: ymdString(from: start), endDate: ymdString(from: end))
    }

    private func dateFromYMD(_ s: String) -> Date? {
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)
    }

    private func ymdString(from d: Date) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
        return df.string(from: d)
    }

    private func parseRecordDateTime(_ r: ClaudeRecord) -> Date? {
        if let ts = r.timestamp {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: ts) { return d }
            // Fallback without fractional seconds
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: ts) { return d }
        }
        guard let base = dateFromYMD(r.date) else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: base)
        comps.hour = 12; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps)
    }
}
