import CryptoKit
import Darwin
import Foundation
import Testing
@testable import AirSignCore

private func publishDirectory(in base: URL = FileManager.default.temporaryDirectory) throws -> URL {
    let dir = base.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
    return dir
}

@Test func withoutExclusiveRenameAFileIsPublishedByExclusiveCreate() throws {
    let fm = FileManager.default, dir = try publishDirectory()
    defer { try? fm.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source"), target = dir.appendingPathComponent("target")
    try Data("plain".utf8).write(to: source)
    try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)
    try FileLocker.publish(source, to: target, exclusiveRename: { _, _ in ENOTSUP })
    #expect(try String(contentsOf: target, encoding: .utf8) == "plain")
    #expect((try fm.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue == 0o640)
    #expect(!fm.fileExists(atPath: source.path))
}

@Test func withoutExclusiveRenameAnExistingFileIsNeverOverwritten() throws {
    let fm = FileManager.default, dir = try publishDirectory()
    defer { try? fm.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source"), target = dir.appendingPathComponent("target")
    try Data("plain".utf8).write(to: source)
    try Data("theirs".utf8).write(to: target)
    #expect(throws: FileLockerError.self) {
        try FileLocker.publish(source, to: target, exclusiveRename: { _, _ in ENOTSUP })
    }
    #expect(try String(contentsOf: target, encoding: .utf8) == "theirs")
    #expect(try String(contentsOf: source, encoding: .utf8) == "plain")
}

@Test func withoutExclusiveRenameAFolderIsPublishedWhole() throws {
    let fm = FileManager.default, dir = try publishDirectory()
    defer { try? fm.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source"), target = dir.appendingPathComponent("target")
    try fm.createDirectory(at: source.appendingPathComponent("inner"), withIntermediateDirectories: true)
    try Data("plain".utf8).write(to: source.appendingPathComponent("inner/file"))
    try FileLocker.publish(source, to: target, exclusiveRename: { _, _ in ENOTSUP })
    #expect(try String(contentsOf: target.appendingPathComponent("inner/file"), encoding: .utf8) == "plain")
    #expect(!fm.fileExists(atPath: source.path))
}

@Test func withoutExclusiveRenameAnExistingFolderIsNeverReplaced() throws {
    let fm = FileManager.default, dir = try publishDirectory()
    defer { try? fm.removeItem(at: dir) }
    for populated in [false, true] {
        let caseDir = try publishDirectory(in: dir)
        let source = caseDir.appendingPathComponent("source"), target = caseDir.appendingPathComponent("target")
        try fm.createDirectory(at: source.appendingPathComponent("inner"), withIntermediateDirectories: true)
        try Data("plain".utf8).write(to: source.appendingPathComponent("inner/file"))
        try fm.createDirectory(at: target, withIntermediateDirectories: false)
        if populated { try Data("theirs".utf8).write(to: target.appendingPathComponent("keep")) }
        #expect(throws: FileLockerError.self) {
            try FileLocker.publish(source, to: target, exclusiveRename: { _, _ in ENOTSUP })
        }
        #expect(try fm.contentsOfDirectory(atPath: target.path) == (populated ? ["keep"] : []))
        if populated { #expect(try String(contentsOf: target.appendingPathComponent("keep"), encoding: .utf8) == "theirs") }
        #expect(try String(contentsOf: source.appendingPathComponent("inner/file"), encoding: .utf8) == "plain")
        #expect(try fm.contentsOfDirectory(atPath: source.path) == ["inner"])
    }
}

@Test func publishStillRefusesAnExistingTargetWithExclusiveRename() throws {
    let fm = FileManager.default, dir = try publishDirectory()
    defer { try? fm.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source"), target = dir.appendingPathComponent("target")
    try Data("plain".utf8).write(to: source)
    try Data("theirs".utf8).write(to: target)
    #expect(throws: FileLockerError.self) { try FileLocker.publish(source, to: target) }
    #expect(try String(contentsOf: target, encoding: .utf8) == "theirs")
    #expect(try String(contentsOf: source, encoding: .utf8) == "plain")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AIRSIGN_TEST_VOLUME"] != nil))
func lockAndUnlockWorkOnAVolumeWithoutExclusiveRename() throws {
    let fm = FileManager.default
    let volume = try #require(ProcessInfo.processInfo.environment["AIRSIGN_TEST_VOLUME"])
    let dir = try publishDirectory(in: URL(fileURLWithPath: volume, isDirectory: true))
    defer { try? fm.removeItem(at: dir) }
    let probe = dir.appendingPathComponent("probe"), probeTarget = dir.appendingPathComponent("probe-target")
    try Data("probe".utf8).write(to: probe)
    guard FileLocker.exclusiveRename(probe.path, probeTarget.path) == ENOTSUP else {
        Issue.record("AIRSIGN_TEST_VOLUME must reject exclusive rename with ENOTSUP to exercise the fallback")
        return
    }
    let trash = dir.appendingPathComponent(".trash")
    try fm.createDirectory(at: trash, withIntermediateDirectories: false)
    let locker = FileLocker(trash: { try fm.moveItem(at: $0, to: trash.appendingPathComponent($0.lastPathComponent)) })
    let master = SymmetricKey(size: .bits256)
    let publicKey = try RecoveryCode.privateKey(for: RecoveryCode.generate()).publicKey
    for (name, isFolder, secondName) in [("note.txt", false, "note (unlocked).txt"), ("Docs", true, "Docs (unlocked)")] {
        let source = dir.appendingPathComponent(name)
        if isFolder { try fm.createDirectory(at: source.appendingPathComponent("inner"), withIntermediateDirectories: true) }
        let payload = isFolder ? source.appendingPathComponent("inner/file") : source
        try Data("plain".utf8).write(to: payload)
        let locked = try locker.lock(source, masterKey: master, recoveryPublicKey: publicKey)
        let secondLocked = dir.appendingPathComponent("\(name)-copy.airsign")
        try fm.copyItem(at: locked, to: secondLocked)
        let restored = try locker.unlock(locked) { try LockedFile.open($0, masterKey: master) }
        #expect(restored.lastPathComponent == name)
        #expect(try String(contentsOf: payload, encoding: .utf8) == "plain")
        let second = try locker.unlock(secondLocked) { try LockedFile.open($0, masterKey: master) }
        #expect(second.lastPathComponent == secondName)
        let secondPayload = isFolder ? second.appendingPathComponent("inner/file") : second
        #expect(try String(contentsOf: secondPayload, encoding: .utf8) == "plain")
        #expect(try String(contentsOf: payload, encoding: .utf8) == "plain")
        #expect(try fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".airsign-partial-") }.isEmpty)
    }
}
