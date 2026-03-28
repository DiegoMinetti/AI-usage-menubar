import Foundation
import Security

enum CookieStorage {
    private static let service = "com.diegominetti.ai-usage-menubar"
    private static let account = "GitHubCookie"

    /// Save the full `Cookie` header string into the Keychain
    static func save(cookieHeader: String) {
        let data = Data(cookieHeader.utf8)

        // Delete existing item first (Keychain rejects duplicates)
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Load the saved cookie header string from the Keychain
    static func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Build a Cookie header value from an array of HTTPCookie
    static func header(from cookies: [HTTPCookie]) -> String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}
