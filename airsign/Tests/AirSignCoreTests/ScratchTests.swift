import Foundation
import Testing
@testable import AirSignCore

@Test func aFailedCleanUpKeepsTheMarkerSoALaterSweepFinishesIt() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let folder = try ScratchFolder(in: base, prefix: Scratch.partialPrefix)
    let payload = folder.url.appendingPathComponent("payload")
    try Data("plain".utf8).write(to: payload)
    struct Stop: Error {}
    #expect(folder.remove(removingItem: { _ in throw Stop() }) == false)
    #expect(fm.fileExists(atPath: folder.url.appendingPathComponent(".airsign-owner").path))
    #expect(fm.fileExists(atPath: payload.path))
    #expect(Scratch.sweepPartials(in: base) == 1)
    #expect(!fm.fileExists(atPath: folder.url.path))
}

@Test func cleanUpRemovesTheMarkerItselfAndLast() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let folder = try ScratchFolder(in: base)
    try Data("zip".utf8).write(to: folder.url.appendingPathComponent("folder.zip"))
    try fm.createDirectory(at: folder.url.appendingPathComponent("out/inner"), withIntermediateDirectories: true)
    var handed: [String] = [], markerWasThere: [Bool] = []
    let marker = folder.url.appendingPathComponent(".airsign-owner").path
    #expect(folder.remove(removingItem: {
        handed.append($0.lastPathComponent)
        markerWasThere.append(fm.fileExists(atPath: marker))
        try fm.removeItem(at: $0)
    }))
    #expect(handed.sorted() == ["folder.zip", "out"])
    #expect(markerWasThere == [true, true])
    #expect(!fm.fileExists(atPath: folder.url.path))
}

@Test func sweepRemovesOnlyFoldersAirSignOwnsAndIsNotUsing() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let stale = base.appendingPathComponent("airsign-scratch-\(UUID().uuidString)")
    try fm.createDirectory(at: stale, withIntermediateDirectories: false)
    try Data().write(to: stale.appendingPathComponent(".airsign-owner"))
    try Data("zip".utf8).write(to: stale.appendingPathComponent("folder.zip"))
    let live = try ScratchFolder(in: base)
    defer { live.remove() }
    let unowned = base.appendingPathComponent("airsign-scratch-\(UUID().uuidString)")
    try fm.createDirectory(at: unowned, withIntermediateDirectories: false)
    let file = base.appendingPathComponent("airsign-scratch-\(UUID().uuidString)")
    try Data("mine".utf8).write(to: file)
    let others = ["airsign-venv", "airsign-scratch-not-a-uuid", "other"]
    for name in others { try fm.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: false) }
    try Data().write(to: base.appendingPathComponent("airsign-scratch-not-a-uuid/.airsign-owner"))
    #expect(live.url.lastPathComponent.hasPrefix("airsign-scratch-"))
    #expect((try fm.attributesOfItem(atPath: live.url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    #expect(Scratch.sweepTemporaryFolders(in: base) == 1)
    #expect(!fm.fileExists(atPath: stale.path))
    for url in [live.url, unowned, file] + others.map({ base.appendingPathComponent($0) }) {
        #expect(fm.fileExists(atPath: url.path))
    }
    live.remove()
    #expect(!fm.fileExists(atPath: live.url.path))
}

@Test func sweepsNeverFollowFolderOrMarkerSymlinks() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let outside = base.appendingPathComponent("outside")
    try fm.createDirectory(at: outside, withIntermediateDirectories: false)
    try Data().write(to: outside.appendingPathComponent(".airsign-owner"))
    try Data("mine".utf8).write(to: outside.appendingPathComponent("payload"))
    let linkedFolder = base.appendingPathComponent("airsign-scratch-\(UUID().uuidString)")
    try fm.createSymbolicLink(at: linkedFolder, withDestinationURL: outside)
    let linkedMarker = base.appendingPathComponent("airsign-scratch-\(UUID().uuidString)")
    try fm.createDirectory(at: linkedMarker, withIntermediateDirectories: false)
    try fm.createSymbolicLink(at: linkedMarker.appendingPathComponent(".airsign-owner"),
                              withDestinationURL: outside.appendingPathComponent(".airsign-owner"))
    let directoryMarker = base.appendingPathComponent("airsign-scratch-\(UUID().uuidString)")
    try fm.createDirectory(at: directoryMarker.appendingPathComponent(".airsign-owner"), withIntermediateDirectories: true)

    #expect(Scratch.sweepTemporaryFolders(in: base) == 0)
    #expect(try fm.destinationOfSymbolicLink(atPath: linkedFolder.path) == outside.path)
    #expect(fm.fileExists(atPath: linkedMarker.path))
    #expect(fm.fileExists(atPath: directoryMarker.path))
    #expect(try String(contentsOf: outside.appendingPathComponent("payload"), encoding: .utf8) == "mine")
}
