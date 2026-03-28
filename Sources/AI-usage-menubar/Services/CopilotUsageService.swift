import Foundation
import os

private let logger = Logger(subsystem: "com.diegominetti.ai-usage-menubar", category: "CopilotUsageService")

@MainActor
final class CopilotUsageService {
    nonisolated private static let targetURL = URL(string: "https://github.com/settings/copilot")!
    private let cacheFileName = "copilot_usage.json"
    nonisolated(unsafe) private var timer: Timer?
    private(set) var cachedUsage: CopilotUsage?

    var onUpdate: ((CopilotUsage) -> Void)?

    init() {
        cachedUsage = loadCached()
        logger.debug("CopilotUsageService initialized; cachedExists=\(self.cachedUsage != nil, privacy: .public)")
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        cachedUsage = loadCached()
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 21_600, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() { refresh() }

    func refresh() {
        Task { [weak self] in
            guard let self else { return }
            if let usage = await Self.fetchUsageNetwork() {
                self.saveCached(usage)
                self.onUpdate?(usage)
            } else if let cached = self.cachedUsage {
                self.onUpdate?(cached)
            }
        }
    }

    // MARK: - Network fetch

    nonisolated static func fetchUsageNetwork() async -> CopilotUsage? {
        guard let cookieHeader = CookieStorage.load() else {
            logger.debug("No cookies; skipping fetch")
            return nil
        }

        var config = URLSessionConfiguration.default
        config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest  = 15
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)

        var req = URLRequest(url: targetURL)
        req.httpMethod = "GET"
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await session.data(for: req)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            logger.debug("Fetched Copilot HTML; length=\(html.count, privacy: .public)")
            if let usage = parse(html: html) {
                logger.debug("Parsed: \(usage.percentage, privacy: .public)% reset=\(usage.resetDate, privacy: .public)")
                return usage
            }
            logger.debug("Parsing returned nil")
            return nil
        } catch {
            logger.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - HTML parsing

    nonisolated static func parse(html: String) -> CopilotUsage? {
        let lower = html.lowercased()
        // Prefer percentage near "Premium requests"
        if let range = lower.range(of: "premium requests") {
            let nsrange = NSRange(range, in: lower)
            let radius = 300
            let s = max(0, nsrange.location - radius)
            let e = min(lower.utf16.count, nsrange.location + nsrange.length + radius)
            let ctx = (html as NSString).substring(with: NSRange(location: s, length: e - s))
            if let pct = extractPercentage(from: ctx) {
                return CopilotUsage(
                    percentage: pct,
                    resetDate: extractResetDate(from: html) ?? Date().addingTimeInterval(30 * 86_400)
                )
            }
        }
        if let pct = extractPercentage(from: html) {
            return CopilotUsage(
                percentage: pct,
                resetDate: extractResetDate(from: html) ?? Date().addingTimeInterval(30 * 86_400)
            )
        }
        return nil
    }

    nonisolated private static func extractPercentage(from text: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: "([0-9]{1,3}(?:\\.[0-9])?)\\s*%") else { return nil }
        let full = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: full),
              let r = Range(m.range(at: 1), in: text),
              let v = Double(String(text[r]).replacingOccurrences(of: ",", with: ""))
        else { return nil }
        return min(max((v * 10).rounded() / 10, 0), 100)
    }

    nonisolated private static func extractResetDate(from text: String) -> Date? {
        guard let re = try? NSRegularExpression(
            pattern: "Allowance resets\\s*([A-Za-z]+\\s+\\d{1,2},\\s*\\d{4})",
            options: .caseInsensitive
        ) else { return nil }
        let full = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: full),
              let r = Range(m.range(at: 1), in: text)
        else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MMMM d, yyyy"
        return df.date(from: String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Cache

    private var cacheURL: URL {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(cacheFileName)
        }
        let dir = support.appendingPathComponent("AI-usage-menubar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(cacheFileName)
    }

    private func saveCached(_ usage: CopilotUsage) {
        do {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            try enc.encode(usage).write(to: cacheURL, options: .atomic)
            cachedUsage = usage
        } catch {
            logger.error("Failed to save cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadCached() -> CopilotUsage? {
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL)
        else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let usage = try? dec.decode(CopilotUsage.self, from: data)
        if let u = usage { cachedUsage = u }
        return usage
    }
}
