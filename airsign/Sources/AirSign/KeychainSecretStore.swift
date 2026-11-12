import AirSignCore
import Foundation
import Security

enum KeychainError: Error {
    case status(OSStatus)
}

/// A separate service keeps lab sandbox secrets away from the installed app's keys.
final class KeychainSecretStore: SecretStore {
    private let service: String

    init(service: String = "com.makeuc.airsign") {
        self.service = service
    }

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
