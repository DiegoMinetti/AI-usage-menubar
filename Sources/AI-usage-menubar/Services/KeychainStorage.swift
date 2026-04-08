
import Foundation
import Security

enum KeychainError: Error {
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData
}

enum KeychainStorage {
    private static let service = "AI-usage-menubar"

    /// Store a string value securely in the Keychain for the given key.
    /// Throws KeychainError on failure.
    static func set(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        // Try to add first; if duplicate, update the existing item
        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            return
        }
        if status == errSecDuplicateItem {
            let updateQuery: [CFString: Any] = [
                kSecValueData: data
            ]
            let statusUpdate = SecItemUpdate(query as CFDictionary, updateQuery as CFDictionary)
            if statusUpdate == errSecSuccess { return }
            throw KeychainError.unexpectedStatus(statusUpdate)
        }
        throw KeychainError.unexpectedStatus(status)
    }

    /// Retrieve a stored string for the given key, or nil if not present.
    static func get(_ key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: kCFBooleanTrue as Any,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, let str = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return str
        }
        if status == errSecItemNotFound {
            return nil
        }
        throw KeychainError.unexpectedStatus(status)
    }

    /// Delete a key from the Keychain. No-op if item not found.
    static func delete(_ key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw KeychainError.unexpectedStatus(status)
    }

    /// Check if a key exists in the Keychain
    static func exists(_ key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnAttributes: kCFBooleanTrue as Any,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }
}
