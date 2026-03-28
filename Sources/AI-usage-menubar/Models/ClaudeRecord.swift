import Foundation

struct ClaudeRecord: Codable {
    let date: String      // yyyy-MM-dd
    let tokens: Int       // aggregate: output + input + cacheCreation
    let project: String?
    let timestamp: String? // ISO8601 (e.g. 2026-03-27T14:05:00.000Z)

    // Token breakdown — present for JSONL-sourced records, nil for legacy JSON records
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationTokens: Int?
    let cacheReadTokens: Int?

    // Convenience init for legacy records (custom JSON wrapper, backward-compat)
    init(date: String, tokens: Int, project: String?, timestamp: String?) {
        self.date = date
        self.tokens = tokens
        self.project = project
        self.timestamp = timestamp
        self.inputTokens = nil
        self.outputTokens = nil
        self.cacheCreationTokens = nil
        self.cacheReadTokens = nil
    }

    // Init for JSONL-sourced records
    init(date: String, project: String?, timestamp: String?,
         inputTokens: Int, outputTokens: Int, cacheCreationTokens: Int, cacheReadTokens: Int) {
        self.date = date
        self.tokens = outputTokens + inputTokens + cacheCreationTokens
        self.project = project
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
    }
}
