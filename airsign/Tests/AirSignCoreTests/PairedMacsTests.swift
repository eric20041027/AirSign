import Foundation
import Testing
@testable import AirSignCore

@Test func pairedMacsReportsTheCountWhenTheKeysCanBeRead() throws {
    let store = ProfileStore(directory: tempDir(), secrets: InMemorySecretStore())
    #expect(store.pairedMacs() == .readable(count: 0) && !store.pairedMacs().canForget)
    try store.addPairedRecoveryKey(RecoveryCode.privateKey(for: RecoveryCode.generate()))
    #expect(store.pairedMacs() == .readable(count: 1) && store.pairedMacs().canForget)
}

@Test func pairingKeysTheKeychainWillNotReadCanStillBeForgotten() throws {
    let secrets = FailingSecretStore()
    let store = ProfileStore(directory: tempDir(), secrets: secrets)
    try store.addPairedRecoveryKey(RecoveryCode.privateKey(for: RecoveryCode.generate()))
    secrets.failingLoads = ["paired-recovery-keys"]
    #expect(store.pairedMacs() == .unreadable && store.pairedMacs().canForget)
    try store.forgetPairedMacs()
    #expect(store.pairedMacs() == .readable(count: 0))
    #expect(try secrets.inner.load("paired-recovery-keys") == nil)
}

@Test func storedBytesThatAreNotKeysCountAsUnreadableAndCanBeForgotten() throws {
    let secrets = InMemorySecretStore()
    let store = ProfileStore(directory: tempDir(), secrets: secrets)
    for junk in [Data("junk".utf8), try JSONEncoder().encode([Data([1, 2, 3])])] {
        try secrets.save(junk, as: "paired-recovery-keys")
        #expect(store.pairedMacs() == .unreadable && store.pairedMacs().canForget)
        try store.forgetPairedMacs()
        #expect(store.pairedMacs() == .readable(count: 0))
    }
}
