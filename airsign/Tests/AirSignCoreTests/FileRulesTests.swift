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

    var locker: FileLocker {
        let trash = trashDir
        return FileLocker(trash: {
            try FileManager.default.moveItem(at: $0, to: trash.appendingPathComponent($0.lastPathComponent))
        })
    }

    func file(_ name: String, _ text: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try! Data(text.utf8).write(to: url)
        return url
    }
}

struct FileRulesTests {
    @Test func openedItemsAreRoutedByTheirExtension() {
        let urls = ["a.txt", "b.airsign", "Docs", "C.AIRSIGN", "d.airsign.txt"].map { URL(fileURLWithPath: "/tmp/x/\($0)") }
        let routed = OpenRouting.route(urls)
        #expect(routed.toLock.map(\.lastPathComponent) == ["a.txt", "Docs", "d.airsign.txt"])
        #expect(routed.toUnlock.map(\.lastPathComponent) == ["b.airsign", "C.AIRSIGN"])
        #expect(OpenRouting.route([]).toLock.isEmpty && OpenRouting.route([]).toUnlock.isEmpty)
    }

    @Test func thisMacsKeyIsTriedFirstThenEachPairedKey() throws {
        let master = SymmetricKey(size: .bits256), otherMaster = SymmetricKey(size: .bits256)
        let mine = try RecoveryCode.privateKey(for: RecoveryCode.generate())
        let theirs = try RecoveryCode.privateKey(for: RecoveryCode.generate())
        let stranger = try RecoveryCode.privateKey(for: RecoveryCode.generate())
        let local = try LockedFile.seal(Data("local".utf8), originalName: "l.txt", masterKey: master, recoveryPublicKey: mine.publicKey)
        let foreign = try LockedFile.seal(Data("foreign".utf8), originalName: "f.txt", masterKey: otherMaster, recoveryPublicKey: theirs.publicKey)
        let keys = UnlockKeys(master: master, paired: [stranger, theirs])
        #expect(try keys.open(local).plaintext == Data("local".utf8))
        #expect(try keys.open(foreign).plaintext == Data("foreign".utf8))
        #expect(throws: LockedFileError.authenticationFailed) { try UnlockKeys(master: master, paired: [stranger]).open(foreign) }
        #expect(throws: LockedFileError.authenticationFailed) { try UnlockKeys(master: master, paired: []).open(foreign) }
        #expect(throws: LockedFileError.notAirSignFile) { try keys.open(Data("junk".utf8)) }
    }

    @Test func anUnlockRunRestoresReportsAndKeepsWaitingInOrder() throws {
        let f = Fixture(), fm = FileManager.default
        defer { try? fm.removeItem(at: f.dir) }
        let first = try f.locker.lock(f.file("a.txt", "alpha"), masterKey: f.master, recoveryPublicKey: f.pub)
        let second = try f.locker.lock(f.file("b.txt", "beta"), masterKey: SymmetricKey(size: .bits256), recoveryPublicKey: f.pub)
        let junk = f.file("junk.airsign", "junk")
        let outcome = UnlockRun.run([first, second, junk], locker: f.locker) { try LockedFile.open($0, masterKey: f.master) }

        #expect(outcome.restored == [f.dir.appendingPathComponent("a.txt")])
        let restored = try #require(outcome.restored.first)
        #expect(restored.lastPathComponent == "a.txt")
        #expect(try Data(contentsOf: restored) == Data("alpha".utf8))
        #expect(outcome.wrongKey == [second])
        #expect(outcome.failures.map(\.url) == [junk])
        #expect(outcome.failures.first?.error as? LockedFileError == .notAirSignFile)
        #expect(!outcome.allDone)
        #expect(fm.fileExists(atPath: second.path))
        #expect(fm.fileExists(atPath: junk.path))
        #expect(!fm.fileExists(atPath: first.path))
        #expect(fm.fileExists(atPath: f.trashDir.appendingPathComponent(first.lastPathComponent).path))
    }

    @Test func aFailureEarlyInAnUnlockRunDoesNotStopTheItemsAfterIt() throws {
        let f = Fixture(), fm = FileManager.default
        defer { try? fm.removeItem(at: f.dir) }
        let junk = f.file("junk.airsign", "junk")
        let otherKey = try f.locker.lock(f.file("other.txt", "other"), masterKey: SymmetricKey(size: .bits256), recoveryPublicKey: f.pub)
        let third = try f.locker.lock(f.file("a.txt", "alpha"), masterKey: f.master, recoveryPublicKey: f.pub)
        let fourth = try f.locker.lock(f.file("b.txt", "beta"), masterKey: f.master, recoveryPublicKey: f.pub)
        let locked = [junk, otherKey, third, fourth]
        let expectedAttempts = try locked.map { try Data(contentsOf: $0) }
        var attempts: [Data] = []
        let outcome = UnlockRun.run(locked, locker: f.locker) {
            attempts.append($0)
            return try LockedFile.open($0, masterKey: f.master)
        }

        #expect(attempts == expectedAttempts)
        #expect(outcome.failures.map(\.url) == [junk])
        #expect(outcome.failures.first?.error as? LockedFileError == .notAirSignFile)
        #expect(outcome.wrongKey == [otherKey])
        #expect(outcome.restored == [f.dir.appendingPathComponent("a.txt"), f.dir.appendingPathComponent("b.txt")])
        #expect(try outcome.restored.map { try Data(contentsOf: $0) } == [Data("alpha".utf8), Data("beta".utf8)])
        #expect(!outcome.allDone)
    }

    @Test func anUnlockRunWithNothingWrongIsAllDone() throws {
        let f = Fixture(), fm = FileManager.default
        defer { try? fm.removeItem(at: f.dir) }
        let sources = [f.file("a.txt", "alpha"), f.file("b.txt", "beta")]
        let locked = try sources.map { try f.locker.lock($0, masterKey: f.master, recoveryPublicKey: f.pub) }
        let outcome = UnlockRun.run(locked, locker: f.locker) { try LockedFile.open($0, masterKey: f.master) }

        #expect(outcome.restored == sources)
        #expect(try outcome.restored.map { try Data(contentsOf: $0) } == [Data("alpha".utf8), Data("beta".utf8)])
        #expect(outcome.allDone)
        #expect(outcome.wrongKey.isEmpty)
        #expect(outcome.failures.isEmpty)
    }

    @Test func aFailureEarlyInALockRunDoesNotStopTheItemsAfterIt() throws {
        let f = Fixture(), fm = FileManager.default
        defer { try? fm.removeItem(at: f.dir) }
        let alreadyLocked = f.file("existing.airsign", "keep")
        let file = f.file("a.txt", "alpha")
        let folder = f.dir.appendingPathComponent("Docs")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("beta".utf8).write(to: folder.appendingPathComponent("b.txt"))
        let outcome = LockRun.run([alreadyLocked, file, folder], locker: f.locker, masterKey: f.master, recoveryPublicKey: f.pub)

        try #require(outcome.items.count == 3)
        guard case .failed(let failure) = outcome.items[0],
              case .locked(let second) = outcome.items[1],
              case .locked(let third) = outcome.items[2] else {
            Issue.record("Expected a failure followed by two locked items.")
            return
        }
        #expect(failure.url == alreadyLocked)
        #expect(failure.error as? FileLockerError == .alreadyLocked)
        #expect(second.source == file)
        #expect(third.source == folder)
        #expect(outcome.anyFailed)
        let openedFile = try LockedFile.open(Data(contentsOf: second.locked), masterKey: f.master)
        let openedFolder = try LockedFile.open(Data(contentsOf: third.locked), masterKey: f.master)
        #expect(openedFile.name == "a.txt")
        #expect(openedFile.plaintext == Data("alpha".utf8))
        #expect(openedFolder.name == "Docs")
        #expect(!openedFolder.plaintext.isEmpty)
    }

    @Test func aLockRunReportsEachItemInOrder() throws {
        let f = Fixture(), fm = FileManager.default
        defer { try? fm.removeItem(at: f.dir) }
        let file = f.file("a.txt", "alpha")
        let folder = f.dir.appendingPathComponent("Docs")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("beta".utf8).write(to: folder.appendingPathComponent("b.txt"))
        let alreadyLocked = f.file("existing.airsign", "keep")
        let outcome = LockRun.run([file, folder, alreadyLocked], locker: f.locker, masterKey: f.master, recoveryPublicKey: f.pub)

        try #require(outcome.items.count == 3)
        guard case .locked(let first) = outcome.items[0],
              case .locked(let second) = outcome.items[1],
              case .failed(let failure) = outcome.items[2] else {
            Issue.record("Expected two locked items followed by a failure.")
            return
        }
        #expect(first.source == file)
        #expect(second.source == folder)
        #expect(failure.url == alreadyLocked)
        #expect(failure.error as? FileLockerError == .alreadyLocked)
        #expect(outcome.anyFailed)
        let openedFile = try LockedFile.open(Data(contentsOf: first.locked), masterKey: f.master)
        let openedFolder = try LockedFile.open(Data(contentsOf: second.locked), masterKey: f.master)
        #expect(openedFile.name == "a.txt")
        #expect(openedFile.plaintext == Data("alpha".utf8))
        #expect(openedFolder.name == "Docs")
        #expect(!openedFolder.plaintext.isEmpty)
    }
}
