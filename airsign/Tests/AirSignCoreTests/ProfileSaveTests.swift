import Foundation
import Testing
@testable import AirSignCore

@Test func theProfileFileHasItsFinalPermissionsBeforeItReplacesTheOldOne() throws {
    let fm = FileManager.default, dir = tempDir(), secrets = InMemorySecretStore()
    let old = try testProfile("UID-A"), fresh = try testProfile("UID-B")
    try ProfileStore(directory: dir, secrets: secrets).createProfile(old)
    var stagedMode: Int?, stagedFolder: String?, profileAtThatMoment: Profile?
    let store = ProfileStore(directory: dir, secrets: secrets) { staged in
        stagedMode = (try fm.attributesOfItem(atPath: staged.path)[.posixPermissions] as? NSNumber)?.intValue
        stagedFolder = staged.deletingLastPathComponent().standardizedFileURL.path
        profileAtThatMoment = try ProfileStore(directory: dir, secrets: secrets).load()
    }
    try store.save(fresh)
    #expect(stagedMode == 0o600)
    #expect(stagedFolder == dir.standardizedFileURL.path)
    #expect(profileAtThatMoment == old)
    #expect(try store.load() == fresh)
    let url = dir.appendingPathComponent("profile.bin")
    #expect((try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(try fm.contentsOfDirectory(atPath: dir.path) == ["profile.bin"])
}

@Test func aSaveThatFailsBeforeTheReplaceKeepsTheOldProfileAndLeavesNothingBehind() throws {
    struct Stop: Error {}
    let dir = tempDir(), secrets = InMemorySecretStore()
    let old = try testProfile("UID-A")
    try ProfileStore(directory: dir, secrets: secrets).createProfile(old)
    let failing = ProfileStore(directory: dir, secrets: secrets) { _ in throw Stop() }
    #expect(throws: Stop.self) { try failing.save(try testProfile("UID-B")) }
    #expect(try ProfileStore(directory: dir, secrets: secrets).load() == old)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["profile.bin"])
}
