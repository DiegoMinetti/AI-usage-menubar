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
        // Prefer percentage near likely anchors (try multiple phrases)
        let anchors = ["premium requests", "premium request", "copilot requests", "copilot usage", "copilot premium", "allowance", "your allowance"]
        for anchor in anchors {
            if let range = lower.range(of: anchor) {
                let nsrange = NSRange(range, in: lower)
                let radius = 300
                let s = max(0, nsrange.location - radius)
                let e = min(lower.utf16.count, nsrange.location + nsrange.length + radius)
                let ctx = (html as NSString).substring(with: NSRange(location: s, length: e - s))
                if let pct = extractPercentage(from: ctx) {
                    // gather feature flags
                    let inlineStatus = extractFeatureStatus(from: html, feature: "Inline Suggestions")
                    let chatStatus = extractFeatureStatus(from: html, feature: "Chat messages")
                    let paidEnabled = extractPaidPremiumFlag(from: lower)
                    let manageURL = extractManagePaidURL(from: html)
                    return CopilotUsage(
                        percentage: pct,
                        resetDate: extractResetDate(from: ctx) ?? extractResetDate(from: html) ?? Date().addingTimeInterval(30 * 86_400),
                        resetDisplayString: extractResetDisplayString(from: ctx) ?? extractResetDisplayString(from: html),
                        fetchedAt: Date(),
                        inlineSuggestionsStatus: inlineStatus,
                        chatMessagesStatus: chatStatus,
                        paidPremiumRequestsEnabled: paidEnabled,
                        managePaidURL: manageURL
                    )
                }
            }
        }

        // Try heuristics over the whole document
        if let pct = extractPercentage(from: html) {
            let inlineStatus = extractFeatureStatus(from: html, feature: "Inline Suggestions")
            let chatStatus = extractFeatureStatus(from: html, feature: "Chat messages")
            let paidEnabled = extractPaidPremiumFlag(from: lower)
            let manageURL = extractManagePaidURL(from: html)
            return CopilotUsage(
                percentage: pct,
                resetDate: extractResetDate(from: html) ?? Date().addingTimeInterval(30 * 86_400),
                resetDisplayString: extractResetDisplayString(from: html),
                fetchedAt: Date(),
                inlineSuggestionsStatus: inlineStatus,
                chatMessagesStatus: chatStatus,
                paidPremiumRequestsEnabled: paidEnabled,
                managePaidURL: manageURL
            )
        }

        // Save HTML for debugging when parse fails
        saveRawHTMLForDebug(html)
        return nil
    }

    nonisolated private static func extractPercentage(from text: String) -> Double? {
        let full = NSRange(text.startIndex..., in: text)

        func value(from pattern: String) -> Double? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            guard let m = re.firstMatch(in: text, range: full), m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: text) else { return nil }
            let raw = String(text[r]).replacingOccurrences(of: ",", with: "")
            return Double(raw)
        }

        // 1) Percent sign matches (e.g. "83.6%")
        if let v = value(from: "([0-9]{1,3}(?:\\.[0-9])?)\\s*%") {
            return min(max((v * 10).rounded() / 10, 0), 100)
        }

        // 2) Look for progress-style attributes / inline styles
        let patterns = [
            "width\\s*:\\s*([0-9]{1,3}(?:\\.[0-9])?)%",
            "aria-valuenow\\s*=\\s*['\"]([0-9]{1,3}(?:\\.[0-9])?)['\"]",
            "data-percent\\s*=\\s*['\"]([0-9]{1,3}(?:\\.[0-9])?)['\"]",
            "data-value\\s*=\\s*['\"]([0-9]{1,3}(?:\\.[0-9])?)['\"]",
            "value\\s*=\\s*['\"]([0-9]{1,3}(?:\\.[0-9])?)['\"]"
        ]
        for p in patterns {
            if let v = value(from: p) {
                return min(max((v * 10).rounded() / 10, 0), 100)
            }
        }

        // 3) Try to find any standalone number that looks like a percent near words like "used" or "available"
        if let re = try? NSRegularExpression(pattern: "(used|available|remaining)\\D{0,20}([0-9]{1,3}(?:\\.[0-9])?)\\s*%", options: .caseInsensitive) {
            if let m = re.firstMatch(in: text, range: full), m.numberOfRanges >= 3, let r = Range(m.range(at: 2), in: text), let v = Double(String(text[r]).replacingOccurrences(of: ",", with: "")) {
                return min(max((v * 10).rounded() / 10, 0), 100)
            }
        }

        return nil
    }

    // MARK: - Feature parsing

    nonisolated private static func extractFeatureStatus(from text: String, feature: String) -> String? {
        let lower = text.lowercased()
        guard let range = lower.range(of: feature.lowercased()) else { return nil }
        let nsrange = NSRange(range, in: lower)
        let radius = 120
        let s = max(0, nsrange.location - radius)
        let e = min(lower.utf16.count, nsrange.location + nsrange.length + radius)
        let ctx = (lower as NSString).substring(with: NSRange(location: s, length: e - s))
        if ctx.contains("not included") { return "Not included" }
        if ctx.contains("included") { return "Included" }
        if ctx.contains("disabled") { return "Disabled" }
        if ctx.contains("enabled") { return "Enabled" }
        return nil
    }

    nonisolated private static func extractPaidPremiumFlag(from lowerHtml: String) -> Bool? {
        if lowerHtml.contains("additional paid premium requests") {
            if lowerHtml.contains("disabled") { return false }
            if lowerHtml.contains("enabled") { return true }
        }
        // Try nearby wording
        if let re = try? NSRegularExpression(pattern: "additional\\s+paid\\s+premium\\s+requests\\W{0,40}(disabled|enabled)", options: .caseInsensitive) {
            let full = NSRange(lowerHtml.startIndex..., in: lowerHtml)
            if let m = re.firstMatch(in: lowerHtml, range: full), m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: lowerHtml) {
                let v = String(lowerHtml[r])
                return v.contains("enabled")
            }
        }
        return nil
    }

    nonisolated private static func extractManagePaidURL(from html: String) -> URL? {
        guard let re = try? NSRegularExpression(pattern: "<a[^>]*href=[\"']([^\"']+)[\"'][^>]*>\\s*Manage paid premium requests\\s*</a>", options: .caseInsensitive) else { return nil }
        let full = NSRange(html.startIndex..., in: html)
        if let m = re.firstMatch(in: html, range: full), m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: html) {
            var href = String(html[r])
            href = href.trimmingCharacters(in: .whitespacesAndNewlines)
            if href.hasPrefix("/") { href = "https://github.com\(href)" }
            return URL(string: href)
        }
        return nil
    }

    nonisolated private static func extractResetDisplayString(from text: String) -> String? {
        var t = text
        // Normalize entities
        t = t.replacingOccurrences(of: "&nbsp;", with: " ")
        t = t.replacingOccurrences(of: "\u{00A0}", with: " ")

        let full = NSRange(t.startIndex..., in: t)

        // 1) If there's a <time> element, prefer its inner text (this is usually localized)
        if let reTime = try? NSRegularExpression(pattern: "<time[^>]*>([^<]+)</time>", options: .caseInsensitive),
           let m = reTime.firstMatch(in: t, range: full), let r = Range(m.range(at: 1), in: t) {
            let s = String(t[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.rangeOfCharacter(from: .decimalDigits) != nil { return s }
        }

        // 2) Find anchor words and take the following text snippet, then strip tags
        let lower = t.lowercased()
        let anchors = ["allowance resets", "allowance reset", "resets", "resete", "renueva", "renews"]
        if let found = anchors.compactMap({ lower.range(of: $0) }).first {
            let start = found.upperBound
            let end = t.index(start, offsetBy: 180, limitedBy: t.endIndex) ?? t.endIndex
            var candidate = String(t[start..<end])
            // strip HTML tags
            if let tagRe = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive) {
                candidate = tagRe.stringByReplacingMatches(in: candidate, options: [], range: NSRange(candidate.startIndex..., in: candidate), withTemplate: "")
            }
            candidate = candidate.replacingOccurrences(of: "&nbsp;", with: " ")
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            // remove leading punctuation or colon
            while let first = candidate.unicodeScalars.first, CharacterSet.whitespacesAndNewlines.contains(first) || CharacterSet.punctuationCharacters.contains(first) {
                candidate.removeFirst()
            }
            // If we can detect a date substring via NSDataDetector, return that substring
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
                let fullC = NSRange(candidate.startIndex..., in: candidate)
                if let m = detector.firstMatch(in: candidate, range: fullC), let r = Range(m.range, in: candidate) {
                    return String(candidate[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            // Else, take up to the first punctuation or newline
            if let idx = candidate.firstIndex(where: { $0 == "\n" || $0 == "." || $0 == "," }) {
                let s = candidate[..<idx]
                return String(s).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return candidate.isEmpty ? nil : candidate
        }

        return nil
    }

    // Save raw HTML for debugging when parsing fails or for inspection
    nonisolated private static func saveRawHTMLForDebug(_ html: String) {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return }
        let dir = support.appendingPathComponent("AI-usage-menubar", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let main = dir.appendingPathComponent("copilot_last_fetch.html")
            try html.data(using: .utf8)?.write(to: main, options: .atomic)
            let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = df.string(from: Date())
            let rot = dir.appendingPathComponent("copilot_fetch_\(stamp).html")
            try html.data(using: .utf8)?.write(to: rot, options: .atomic)
            logger.debug("Saved raw Copilot HTML for debug at \(dir.path, privacy: .public)")
        } catch {
            logger.error("Failed to save raw HTML: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private static func extractResetDate(from text: String) -> Date? {
        // Normalize whitespace and HTML entities that commonly appear in markup
        var t = text.replacingOccurrences(of: "&nbsp;", with: " ")
        t = t.replacingOccurrences(of: "\u{00A0}", with: " ")
        t = t.replacingOccurrences(of: "\u{202F}", with: " ")
        let full = NSRange(t.startIndex..., in: t)

        // 1) Prefer machine-readable <time datetime=>
        if let reTime = try? NSRegularExpression(pattern: "<time[^>]*datetime=[\"']([^\"']+)[\"'][^>]*>", options: .caseInsensitive),
           let m = reTime.firstMatch(in: t, range: full),
           let r = Range(m.range(at: 1), in: t) {
            let s = String(t[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let d = ISO8601DateFormatter().date(from: s) { return d }
            if let d = parseFlexibleDateString(s) { return d }
        }

        // 2) Use NSDataDetector to find all date-like substrings and pick the one
        //    nearest to the word 'reset' (or its variants). This is robust to
        //    minor changes in surrounding markup.
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detector.matches(in: t, options: [], range: full)
            if !matches.isEmpty {
                // collect anchor positions for reset-like words
                let lower = t.lowercased()
                let anchorWords = ["allowance resets", "allowance reset", "resets", "reset", "renews", "renueva", "renovación", "resete"]
                var anchors: [Int] = []
                for a in anchorWords {
                    var searchRange = lower.startIndex..<lower.endIndex
                    while let r = lower.range(of: a, options: .caseInsensitive, range: searchRange) {
                        let pos = lower.distance(from: lower.startIndex, to: r.lowerBound)
                        anchors.append(pos)
                        searchRange = r.upperBound..<lower.endIndex
                    }
                }

                // If we found anchors, choose the date match with minimal distance
                if !anchors.isEmpty {
                    var bestMatch: (NSTextCheckingResult, Int)? = nil
                    for m in matches {
                        guard m.resultType == .date else { continue }
                        guard let range = Range(m.range, in: t) else { continue }
                        // use start position as proxy for distance
                        let pos = t.distance(from: t.startIndex, to: range.lowerBound)
                        let dist = anchors.map { abs($0 - pos) }.min() ?? Int.max
                        if bestMatch == nil || dist < bestMatch!.1 { bestMatch = (m, dist) }
                    }
                    if let chosen = bestMatch?.0, let d = chosen.date { return d }
                } else {
                    // No anchors available — prefer a nearby future date, else first match
                    let now = Date()
                    if let future = matches.first(where: { $0.date != nil && $0.date! > now.addingTimeInterval(-60 * 60 * 24) }), let d = future.date { return d }
                    if let first = matches.first, let d = first.date { return d }
                }
            }
        }

        // 3) Try to find ISO 8601 timestamp anywhere in the document
        if let reIso = try? NSRegularExpression(pattern: "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z") {
            if let m = reIso.firstMatch(in: t, range: full), let r = Range(m.range(at: 0), in: t) {
                if let d = ISO8601DateFormatter().date(from: String(t[r])) { return d }
            }
        }

        // 4) Try explicit "Allowance resets <Month d, yyyy at h:mm AM/PM>" which includes time
        if let reAllowanceTime = try? NSRegularExpression(
            pattern: "Allowance resets\\s*([A-Za-z]+\\s+\\d{1,2},\\s*\\d{4}\\s*(?:at|,)\\s*\\d{1,2}:\\d{2}(?::\\d{2})?\\s*(?:AM|PM|am|pm|a\\.?m\\.?|p\\.?m\\.?))",
            options: .caseInsensitive
        ), let m = reAllowanceTime.firstMatch(in: t, range: full), let r = Range(m.range(at: 1), in: t) {
            let candidate = String(t[r])
            if let d = parseFlexibleDateString(candidate) { return d }
        }

        // 5) Existing fallback without time: "Allowance resets <Month d, yyyy>"
        if let reAllowance = try? NSRegularExpression(
            pattern: "Allowance resets\\s*([A-Za-z]+\\s+\\d{1,2},\\s*\\d{4})",
            options: .caseInsensitive
        ), let m2 = reAllowance.firstMatch(in: t, range: full), let r2 = Range(m2.range(at: 1), in: t) {
            if let d = parseFlexibleDateString(String(t[r2])) { return d }
        }

        // 6) Generic "resets (on) <date...>" patterns — include abbreviated months and commas
        if let reGeneric = try? NSRegularExpression(pattern: "resets\\s*(?:on\\s*)?([A-Za-z]{3,9}\\.?\\s+\\d{1,2}(?:,\\s*\\d{4})?(?:\\s*(?:at|,)\\s*\\d{1,2}:\\d{2}(?:\\s*[ap]\\.?m\\.?)?)?)", options: .caseInsensitive),
           let m = reGeneric.firstMatch(in: t, range: full),
           let r = Range(m.range(at: 1), in: t) {
            let s = String(t[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let d = parseFlexibleDateString(s) { return d }
            // try with current year if missing
            let thisYear = Calendar.current.component(.year, from: Date())
            let sWithYear = s + ", \(thisYear)"
            if let d = parseFlexibleDateString(sWithYear) {
                if d < Date(), let next = Calendar.current.date(byAdding: .year, value: 1, to: d) { return next }
                return d
            }
        }

        // 7) "resets in N days" style (relative)
        if let reInDays = try? NSRegularExpression(pattern: "resets\\s*(?:in)\\s*(\\d{1,3})\\s*days?", options: .caseInsensitive),
           let m3 = reInDays.firstMatch(in: t, range: full),
           let r3 = Range(m3.range(at: 1), in: t),
           let days = Int(t[r3]) {
            return Calendar.current.date(byAdding: .day, value: days, to: Date())
        }

        // 8) Final fallback: try NSDataDetector anywhere and return a parsed date if present
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detector.matches(in: t, options: [], range: full)
            if let match = matches.first, let d = match.date { return d }
        }

        return nil
    }

    nonisolated private static func parseFlexibleDateString(_ s: String) -> Date? {
        var trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove surrounding HTML tags if any and collapse whitespace
        if let tagRe = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive) {
            let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
            trimmed = tagRe.stringByReplacingMatches(in: trimmed, options: [], range: fullRange, withTemplate: "")
        }
        trimmed = trimmed.replacingOccurrences(of: "&nbsp;", with: " ")
        trimmed = trimmed.replacingOccurrences(of: "\u{00A0}", with: " ")
        // Normalize common AM/PM variants (a.m., p.m.) to AM/PM for parsers
        trimmed = trimmed.replacingOccurrences(of: "a.m.", with: "AM", options: .caseInsensitive)
        trimmed = trimmed.replacingOccurrences(of: "p.m.", with: "PM", options: .caseInsensitive)
        trimmed = trimmed.replacingOccurrences(of: "a.m", with: "AM", options: .caseInsensitive)
        trimmed = trimmed.replacingOccurrences(of: "p.m", with: "PM", options: .caseInsensitive)
        trimmed = trimmed.replacingOccurrences(of: "am.", with: "AM", options: .caseInsensitive)
        trimmed = trimmed.replacingOccurrences(of: "pm.", with: "PM", options: .caseInsensitive)

        // 1) ISO8601 try
        if let d = ISO8601DateFormatter().date(from: trimmed) { return d }

        // 2) Try a set of formats across English and Spanish locales
        let df = DateFormatter()
        let formats = [
            "MMMM d, yyyy",
            "MMM d, yyyy",
            "MMMM d",
            "MMM d",
            "d MMMM yyyy",
            "d MMM yyyy",
            "d MMM",
            // with time
            "MMMM d, yyyy 'at' h:mm a",
            "MMMM d, yyyy, h:mm a",
            "MMM d, yyyy 'at' h:mm a",
            "MMM d, yyyy, h:mm a",
            "d MMM yyyy, h:mm a",
            "d MMM yyyy h:mm a",
            "d MMM, yyyy h:mm a",
            "d MMM yyyy, H:mm",
            "d MMM yyyy, h:mm a"
        ]
        let locales = [Locale(identifier: "en_US_POSIX"), Locale(identifier: "es_ES")]
        for locale in locales {
            df.locale = locale
            for f in formats {
                df.dateFormat = f
                if let d = df.date(from: trimmed) { return d }
            }
        }

        // 3) Spanish conversational formats like "d 'de' MMMM 'de' yyyy" and with time
        df.locale = Locale(identifier: "es_ES")
        let spFormats = ["d 'de' MMMM 'de' yyyy", "d 'de' MMMM", "d 'de' MMMM 'de' yyyy 'a las' H:mm", "d 'de' MMMM 'de' yyyy 'a las' H:mm:ss"]
        for f in spFormats { df.dateFormat = f; if let d = df.date(from: trimmed) { return d } }

        // 4) NSDataDetector fallback
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let full = NSRange(trimmed.startIndex..., in: trimmed)
            if let m = detector.firstMatch(in: trimmed, range: full), let d = m.date { return d }
        }

        return nil
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
