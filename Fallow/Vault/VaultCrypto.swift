import CryptoKit
import Foundation

enum VaultError: Error, Equatable {
    case corrupted
    case wrongKey
    case noKey
    case cancelled
    case keychain(OSStatus)
}

/// Seals the vault file with AES-256-GCM. The file starts with a short
/// magic header so a future format can be told apart.
enum VaultCrypto {
    static let header = Data("FALLOW1".utf8)

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw VaultError.corrupted }
        return header + combined
    }

    static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        guard sealed.starts(with: header), sealed.count > header.count + 28 else {
            throw VaultError.corrupted
        }
        let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(header.count))
        do {
            return try AES.GCM.open(box, using: key)
        } catch {
            throw VaultError.wrongKey
        }
    }
}
