import Foundation

@MainActor
final class MenuViewModel: ObservableObject {
    @Published var claudeUsage: ClaudeUsage   = .empty
    @Published var claudeStatus: ClaudeCLIStatus = .notInstalled
    @Published var copilotUsage: CopilotUsage?  = nil
    @Published var isGitHubConnected: Bool       = CookieStorage.load() != nil
    // Called by the UI when the user requests a manual refresh
    var onRefresh: (() -> Void)?
}
