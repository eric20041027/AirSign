import Foundation

/// Secret storage abstraction: the app uses the Keychain, tests use memory.
public protocol SecretStore {
    func load(_ name: String) throws -> Data?
    func save(_ data: Data, as name: String) throws
    func delete(_ name: String) throws
}

public final class InMemorySecretStore: SecretStore {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func load(_ name: String) throws -> Data? {
        lock.withLock { items[name] }
    }

    public func save(_ data: Data, as name: String) throws {
        lock.withLock { items[name] = data }
    }

    public func delete(_ name: String) throws {
        lock.withLock { _ = items.removeValue(forKey: name) }
    }
}
