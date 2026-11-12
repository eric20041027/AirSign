import Foundation
import Testing
@testable import AirSignCore

@Test func sweepRemovesOnlyAirSignScratchFolders() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    let mine = try Scratch.makeTemporaryFolder(in: base)
    try Data("zip".utf8).write(to: mine.appendingPathComponent("folder.zip"))
    let others = ["airsign-venv", "airsign-scratch-not-a-uuid", "airsign-\(UUID().uuidString)", "other"]
    for name in others { try fm.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: false) }
    #expect(mine.lastPathComponent.hasPrefix("airsign-scratch-"))
    #expect((try fm.attributesOfItem(atPath: mine.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    #expect(Scratch.sweepTemporaryFolders(in: base) == 1)
    #expect(try fm.contentsOfDirectory(atPath: base.path).sorted() == others.sorted())
}
