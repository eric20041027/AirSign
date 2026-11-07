import AirSignCore
import Foundation
import Security

enum KeychainError: Error {
    case status(OSStatus)
}

/// Stores secrets as generic passwords under the service `com.makeuc.airsign`.
final class KeychainSecretStore: SecretStore {
    private let service = "com.makeuc.airsign"

    func load(_ name: String) throws -> Data? {
        var query = baseQuery(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return item as? Data
    }

    func save(_ data: Data, as name: String) throws {
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(baseQuery(name) as CFDictionary, update)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError.status(status) }
        var add = baseQuery(name)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    }

    func delete(_ name: String) throws {
        let status = SecItemDelete(baseQuery(name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    private func baseQuery(_ name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
    }
}
