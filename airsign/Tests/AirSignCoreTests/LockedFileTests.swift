import CryptoKit
import Foundation
import Testing
@testable import AirSignCore

@Test func recoveryCodeShapeAndNormalization() throws {
    let code = RecoveryCode.generate()
    #expect(code.range(of: #"^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){7}$"#, options: .regularExpression) != nil)
    let messy = code.lowercased()
        .replacingOccurrences(of: "-", with: " ")
        .replacingOccurrences(of: "0", with: "o")
        .replacingOccurrences(of: "1", with: "l")
    #expect(try RecoveryCode.normalize(messy) == code.replacingOccurrences(of: "-", with: ""))
    #expect(throws: LockedFileError.badRecoveryCode) { try RecoveryCode.normalize("too-short") }
}

@Test func sealOpensWithMasterAndWithRecovery() throws {
    let master = SymmetricKey(size: .bits256), code = RecoveryCode.generate()
    let pub = try RecoveryCode.privateKey(for: code).publicKey
    let sealed = try LockedFile.seal(Data("tax return".utf8), originalName: "tax-return.pdf", masterKey: master, recoveryPublicKey: pub)
    let viaMaster = try LockedFile.open(sealed, masterKey: master)
    #expect(viaMaster.name == "tax-return.pdf" && viaMaster.plaintext == Data("tax return".utf8))
    #expect(try LockedFile.open(sealed, recoveryCode: code.lowercased()).plaintext == Data("tax return".utf8))
    #expect(try LockedFile.header(of: sealed).originalName == "tax-return.pdf")
}

@Test func wrongKeysAndTamperingFail() throws {
    let master = SymmetricKey(size: .bits256), code = RecoveryCode.generate()
    let sealed = try LockedFile.seal(Data("x".utf8), originalName: "a.txt", masterKey: master,
                                     recoveryPublicKey: try RecoveryCode.privateKey(for: code).publicKey)
    #expect(throws: LockedFileError.authenticationFailed) { try LockedFile.open(sealed, masterKey: SymmetricKey(size: .bits256)) }
    #expect(throws: LockedFileError.authenticationFailed) { try LockedFile.open(sealed, recoveryCode: RecoveryCode.generate()) }
    var tampered = sealed
    tampered[tampered.count - 1] ^= 0xFF
    #expect(throws: LockedFileError.authenticationFailed) { try LockedFile.open(tampered, masterKey: master) }
    let renamed = sealed.replacing(Data("a.txt".utf8), with: Data("b.txt".utf8))
    #expect(throws: LockedFileError.authenticationFailed) { try LockedFile.open(renamed, masterKey: master) }
    #expect(throws: LockedFileError.notAirSignFile) { try LockedFile.open(Data("hello".utf8), masterKey: master) }
}
