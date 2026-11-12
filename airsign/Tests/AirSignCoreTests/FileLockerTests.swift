import CryptoKit
import Foundation
import Testing
@testable import AirSignCore

private struct Fixture {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let trashDir: URL
    let master = SymmetricKey(size: .bits256)
    let code = RecoveryCode.generate()

    init() {
        trashDir = dir.appendingPathComponent(".trash")
        try! FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    }

    var pub: Curve25519.KeyAgreement.PublicKey { try! RecoveryCode.privateKey(for: code).publicKey }

    var trash: (URL) throws -> Void {
        let trash = trashDir
        return { try FileManager.default.moveItem(at: $0, to: trash.appendingPathComponent($0.lastPathComponent)) }
    }

    var locker: FileLocker { FileLocker(trash: trash) }

    func file(_ name: String, _ text: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try! Data(text.utf8).write(to: url)
        return url
    }
}

private func partials(in dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(".airsign-partial-") }
}
private struct Stop: Error {}

@Test func restoredFileAppearsUnderItsNameOnlyWhenComplete() throws {
    let f = Fixture(), fm = FileManager.default
    let locked = try f.locker.lock(f.file("a.txt", "alpha"), masterKey: f.master, recoveryPublicKey: f.pub)
    var seen = 0
    let locker = FileLocker(trash: f.trash, willPublish: { source, target in
        seen += 1
        #expect(source.path.contains("/.airsign-partial-"))
        #expect(source.deletingLastPathComponent().path == target.deletingLastPathComponent().path)
        #expect((try? String(contentsOf: source, encoding: .utf8)) == "alpha")
        #expect(!fm.fileExists(atPath: target.path))
    })
    let restored = try locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) }
    #expect(seen == 1 && restored.lastPathComponent == "a.txt")
    #expect(try String(contentsOf: restored, encoding: .utf8) == "alpha")
    #expect(partials(in: f.dir).isEmpty)
}

@Test func aRestoreThatFailsBeforePublishingLeavesNothingBehind() throws {
    let f = Fixture(), fm = FileManager.default
    let lockedFile = try f.locker.lock(f.file("a.txt", "alpha"), masterKey: f.master, recoveryPublicKey: f.pub)
    let folder = f.dir.appendingPathComponent("Docs")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("beta".utf8).write(to: folder.appendingPathComponent("b.txt"))
    let lockedFolder = try f.locker.lock(folder, masterKey: f.master, recoveryPublicKey: f.pub)
    let locker = FileLocker(trash: f.trash, willPublish: { _, _ in throw Stop() })
    for locked in [lockedFile, lockedFolder] {
        #expect(throws: (any Error).self) { try locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) } }
        #expect(fm.fileExists(atPath: locked.path))
    }
    #expect(partials(in: f.dir).isEmpty)
    #expect(!fm.fileExists(atPath: f.dir.appendingPathComponent("a.txt").path))
    #expect(!fm.fileExists(atPath: folder.path))
}

@Test func unlockRemovesLeftoverPartialsFromAnEarlierCrash() throws {
    let f = Fixture(), fm = FileManager.default
    let staleFile = f.dir.appendingPathComponent(".airsign-partial-\(UUID().uuidString)")
    let staleDir = f.dir.appendingPathComponent(".airsign-partial-\(UUID().uuidString)")
    try Data("half".utf8).write(to: staleFile)
    try fm.createDirectory(at: staleDir.appendingPathComponent("out"), withIntermediateDirectories: true)
    let keep = [".airsign-partial-notes", ".hidden"]
    for name in keep { try Data().write(to: f.dir.appendingPathComponent(name)) }
    let locked = try f.locker.lock(f.file("a.txt", "alpha"), masterKey: f.master, recoveryPublicKey: f.pub)
    _ = try f.locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) }
    #expect(!fm.fileExists(atPath: staleFile.path) && !fm.fileExists(atPath: staleDir.path))
    for name in keep { #expect(fm.fileExists(atPath: f.dir.appendingPathComponent(name).path)) }
}

@Test func unlockIntoAReadOnlyFolderFailsCleanly() throws {
    let f = Fixture(), fm = FileManager.default
    let locked = try f.locker.lock(f.file("a.txt", "alpha"), masterKey: f.master, recoveryPublicKey: f.pub)
    let before = try fm.contentsOfDirectory(atPath: f.dir.path).sorted()
    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: f.dir.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.dir.path) }
    #expect(throws: FileLockerError.self) { try f.locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) } }
    #expect(try fm.contentsOfDirectory(atPath: f.dir.path).sorted() == before)
}

@Test func lockThenUnlockRestoresBytesAndTrashesOriginal() throws {
    let f = Fixture(), src = f.file("report.pdf", "secret")
    let locked = try f.locker.lock(src, masterKey: f.master, recoveryPublicKey: f.pub)
    #expect(locked.lastPathComponent == "report.pdf.airsign")
    #expect(!FileManager.default.fileExists(atPath: src.path))
    #expect(FileManager.default.fileExists(atPath: f.trashDir.appendingPathComponent("report.pdf").path))
    let restored = try f.locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) }
    #expect(try Data(contentsOf: restored) == Data("secret".utf8))
    #expect(!FileManager.default.fileExists(atPath: locked.path))
}

@Test func unlockNeverOverwritesAnExistingFile() throws {
    let f = Fixture(), src = f.file("report.pdf", "v1")
    let locked = try f.locker.lock(src, masterKey: f.master, recoveryPublicKey: f.pub)
    _ = f.file("report.pdf", "someone else's")
    let restored = try f.locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) }
    #expect(restored.lastPathComponent == "report (unlocked).pdf")
    #expect(try String(contentsOf: f.dir.appendingPathComponent("report.pdf"), encoding: .utf8) == "someone else's")
}

@Test func refusesUnsupportedInputsAndChangesNothing() throws {
    let f = Fixture()
    let already = f.file("x.airsign", "y")
    #expect(throws: FileLockerError.alreadyLocked) { try f.locker.lock(already, masterKey: f.master, recoveryPublicKey: f.pub) }
    let big = f.dir.appendingPathComponent("big.bin")
    FileManager.default.createFile(atPath: big.path, contents: nil)
    try FileHandle(forWritingTo: big).truncate(atOffset: UInt64(FileLocker.maxBytes + 1))
    #expect(throws: FileLockerError.tooLarge) { try f.locker.lock(big, masterKey: f.master, recoveryPublicKey: f.pub) }
    #expect(FileManager.default.fileExists(atPath: big.path))
}

@Test func writeFailureLeavesOriginalAndNoPartialFile() throws {
    let f = Fixture(), src = f.file("notes.txt", "keep me")
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: f.dir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.dir.path) }
    #expect(throws: (any Error).self) { try f.locker.lock(src, masterKey: f.master, recoveryPublicKey: f.pub) }
    #expect(try String(contentsOf: src, encoding: .utf8) == "keep me")
    #expect(!FileManager.default.fileExists(atPath: f.dir.appendingPathComponent("notes.txt.airsign").path))
}

@Test func unlockKeepsTheRestoredFileInsideTheSameFolder() throws {
    let f = Fixture()
    let sealed = try LockedFile.seal(Data("x".utf8), originalName: "../escape.txt", masterKey: f.master, recoveryPublicKey: f.pub)
    let locked = f.dir.appendingPathComponent("odd.airsign")
    try sealed.write(to: locked)
    let restored = try f.locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) }
    #expect(restored.deletingLastPathComponent().standardizedFileURL.path == f.dir.standardizedFileURL.path)
    #expect(restored.lastPathComponent == "escape.txt")
}

// MARK: - Folders

private extension Fixture {
    /// Docs/ with a nested file and a non-ASCII name.
    func folder() -> URL {
        let docs = dir.appendingPathComponent("Docs")
        try! FileManager.default.createDirectory(at: docs.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try! Data("alpha".utf8).write(to: docs.appendingPathComponent("a.txt"))
        try! Data("beta".utf8).write(to: docs.appendingPathComponent("sub/b.txt"))
        try! Data("筆記".utf8).write(to: docs.appendingPathComponent("筆記.txt"))
        return docs
    }
}

@Test func lockingAFolderMakesOneLockedFileAndTrashesTheFolder() throws {
    let f = Fixture(), docs = f.folder()
    let locked = try f.locker.lock(docs, masterKey: f.master, recoveryPublicKey: f.pub)
    #expect(locked.lastPathComponent == "Docs.airsign")
    #expect(!FileManager.default.fileExists(atPath: docs.path))
    #expect(FileManager.default.fileExists(atPath: f.trashDir.appendingPathComponent("Docs/sub/b.txt").path))
    #expect(try LockedFile.header(of: Data(contentsOf: locked)).kind == LockedFileHeader.folderKind)
}

@Test func unlockingALockedFolderRestoresEveryFile() throws {
    let f = Fixture(), docs = f.folder()
    let locked = try f.locker.lock(docs, masterKey: f.master, recoveryPublicKey: f.pub)
    let restored = try f.locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) }
    #expect(restored.lastPathComponent == "Docs")
    #expect(try String(contentsOf: restored.appendingPathComponent("a.txt"), encoding: .utf8) == "alpha")
    #expect(try String(contentsOf: restored.appendingPathComponent("sub/b.txt"), encoding: .utf8) == "beta")
    #expect(try String(contentsOf: restored.appendingPathComponent("筆記.txt"), encoding: .utf8) == "筆記")
    #expect(!FileManager.default.fileExists(atPath: locked.path))
}

@Test func unlockedFolderNeverMergesIntoAnExistingOne() throws {
    let f = Fixture(), docs = f.folder()
    let locked = try f.locker.lock(docs, masterKey: f.master, recoveryPublicKey: f.pub)
    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    try Data("someone else's".utf8).write(to: docs.appendingPathComponent("a.txt"))
    let restored = try f.locker.unlock(locked) { try LockedFile.open($0, masterKey: f.master) }
    #expect(restored.lastPathComponent == "Docs (unlocked)")
    #expect(try String(contentsOf: docs.appendingPathComponent("a.txt"), encoding: .utf8) == "someone else's")
    #expect(try String(contentsOf: restored.appendingPathComponent("a.txt"), encoding: .utf8) == "alpha")
}

@Test func lockedFilesKeepTheOldHeaderWithoutAKind() throws {
    let f = Fixture(), src = f.file("report.pdf", "secret")
    let locked = try f.locker.lock(src, masterKey: f.master, recoveryPublicKey: f.pub)
    let headerJSON = try String(decoding: LockedFile.headerData(of: Data(contentsOf: locked)), as: UTF8.self)
    #expect(!headerJSON.contains("kind"))
}
