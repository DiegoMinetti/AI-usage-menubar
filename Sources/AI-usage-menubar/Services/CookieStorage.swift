import Foundation

enum CookieStorage {
    private static let fileName = "github_cookie.txt"
    private static let appFolder = "AI-usage-menubar"

    private static func cookieFileURL() -> URL? {
        let fm = FileManager.default
        do {
            let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent(appFolder, isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [FileAttributeKey.posixPermissions: 0o700])
            }
            return dir.appendingPathComponent(fileName)
        } catch {
            return nil
        }
    }

    /// Save the full `Cookie` header string into a file inside Application Support.
    /// File is written atomically and permissions set to 600 (owner read/write).
    static func save(cookieHeader: String) {
        guard let url = cookieFileURL() else { return }
        let data = Data(cookieHeader.utf8)
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([FileAttributeKey.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // best-effort; avoid crashing
        }
    }

    /// Load the saved cookie header string from Application Support
    static func load() -> String? {
        guard let url = cookieFileURL(), FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        guard let url = cookieFileURL(), FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Build a Cookie header value from an array of HTTPCookie
    static func header(from cookies: [HTTPCookie]) -> String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}
