import CommonCrypto
import CryptoKit
import Foundation

/// A .fallow file: everything in the vault, locked with a passphrase, to move to another
/// iPhone or to bring Răgaz over from Kitchen Tales. Built only from what Web Crypto also has,
/// so the web app can write the same file:
///
///     "FALLOWX1" | salt (16) | PBKDF2 rounds (UInt32, big-endian) | nonce (12) | ciphertext | tag (16)
///
/// The key is PBKDF2-HMAC-SHA256 of the passphrase (trimmed, Unicode NFC, UTF-8), 32 bytes.
/// The ciphertext is AES-256-GCM of the JSON `TransferPayload`.
enum TransferFile {
    static let header = Data("FALLOWX1".utf8)
    static let fileExtension = "fallow"
    static let defaultRounds: UInt32 = 600_000
    static let minimumPassphrase = 8
    /// Refuses files that would make the phone work for minutes.
    static let maximumRounds: UInt32 = 5_000_000

    enum Failure: Error, Equatable {
        case notAFallowFile
        case wrongPassphrase
        case unreadable
        case shortPassphrase
    }

    /// What is inside, so a file can say what made it.
    struct Payload: Codable, Sendable {
        var format = "fallow-vault"
        var version = 1
        var exportedAt: Date
        var contents: VaultContents
    }

    static func seal(_ contents: VaultContents, passphrase: String, rounds: UInt32 = defaultRounds, now: Date = .now) throws -> Data {
        let phrase = normalized(passphrase)
        guard phrase.count >= minimumPassphrase else { throw Failure.shortPassphrase }
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw Failure.unreadable }
        let key = try deriveKey(phrase, salt: salt, rounds: rounds)
        let json = try VaultCoding.encoder.encode(Payload(exportedAt: now, contents: contents))
        guard let combined = try AES.GCM.seal(json, using: key).combined else { throw Failure.unreadable }
        var r = rounds.bigEndian
        return header + salt + Data(bytes: &r, count: 4) + combined
    }

    static func open(_ data: Data, passphrase: String) throws -> VaultContents {
        let bytes = Data(data)
        let start = header.count
        guard bytes.starts(with: header), bytes.count > start + 16 + 4 + 12 + 16 else { throw Failure.notAFallowFile }
        let salt = bytes.subdata(in: start..<start + 16)
        let rounds = bytes.subdata(in: start + 16..<start + 20).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard rounds > 0, rounds <= maximumRounds else { throw Failure.notAFallowFile }
        let key = try deriveKey(normalized(passphrase), salt: salt, rounds: rounds)
        let plain: Data
        do {
            let box = try AES.GCM.SealedBox(combined: bytes.subdata(in: start + 20..<bytes.count))
            plain = try AES.GCM.open(box, using: key)
        } catch {
            throw Failure.wrongPassphrase
        }
        do {
            return try VaultCoding.decoder.decode(Payload.self, from: plain).contents
        } catch {
            throw Failure.unreadable
        }
    }

    static func normalized(_ passphrase: String) -> String {
        passphrase.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    static func deriveKey(_ passphrase: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        let password = Array(passphrase.utf8)
        guard !password.isEmpty else { throw Failure.wrongPassphrase }
        var derived = [UInt8](repeating: 0, count: 32)
        let status = password.withUnsafeBufferPointer { pw in
            salt.withUnsafeBytes { saltBytes in
                pw.baseAddress!.withMemoryRebound(to: Int8.self, capacity: password.count) { pwPointer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPointer, password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        &derived, derived.count
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.unreadable }
        return SymmetricKey(data: derived)
    }

    /// What the vault holds after "Replace" with a file's contents. The inbox key stays this
    /// iPhone's own: widgets and Siri seal with its public half, so entries waiting in the inbox
    /// (and ones written before the next Face ID) can still be opened.
    static func replacing(_ current: VaultContents, with file: VaultContents) -> VaultContents {
        var next = file
        next.inboxKey = current.inboxKey ?? file.inboxKey
        return next
    }

    /// "Fallow 2026-11-11.fallow"
    static func suggestedName(now: Date = .now) -> String {
        "Fallow \(DayKey.string(now))"
    }
}
