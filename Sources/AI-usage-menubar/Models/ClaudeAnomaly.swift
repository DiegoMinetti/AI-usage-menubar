import Foundation

struct ClaudeAnomaly: Codable {
    let date: String // yyyy-MM-dd
    let tokens: Int
    let reason: String
    let factor: Double?
}
