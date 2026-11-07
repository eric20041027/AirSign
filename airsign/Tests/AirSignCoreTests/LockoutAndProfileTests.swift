import Foundation
import Testing
@testable import AirSignCore

@Test func inMemorySecretStoreRoundTrips() throws {
    let store = InMemorySecretStore()
    try store.save(Data([1, 2, 3]), as: "k")
    #expect(try store.load("k") == Data([1, 2, 3]))
    try store.delete("k")
    #expect(try store.load("k") == nil)
}
