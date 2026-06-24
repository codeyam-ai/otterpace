import Foundation
import Security

// Keychain-backed `TokenStoring` for the Apple user identifier. A small wrapper
// over the Security framework's generic-password items. Used in production; tests
// inject an in-memory store instead, so this is never exercised in the unit suite.
public struct KeychainTokenStore: TokenStoring {
    public init() {}

    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.otterpace.app",
         kSecAttrAccount as String: account]
    }

    public func read(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    public func save(_ value: String, account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
        var add = baseQuery(account)
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    public func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
