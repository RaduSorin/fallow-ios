import CryptoKit
import Foundation

/// Something written outside the app (a widget button, Siri), waiting for the vault.
struct InboxEntry: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case rhythm, note
    }

    var kind: Kind
    /// The day it is about ("2026-11-13").
    var day: String
    var createdAt: Date
    var rhythmID: String?
    var done: Bool?
    var text: String?

    static func rhythm(_ id: String, done: Bool, day: String, at date: Date = .now) -> InboxEntry {
        InboxEntry(kind: .rhythm, day: day, createdAt: date, rhythmID: id, done: done)
    }

    static func note(_ text: String, day: String, at date: Date = .now) -> InboxEntry {
        InboxEntry(kind: .note, day: day, createdAt: date, text: text)
    }
}

/// A write-only letterbox. Anyone holding the public key can drop a sealed entry in;
/// only the private key, kept inside the encrypted vault, opens them.
///
/// Each entry: a fresh X25519 key, agreed with the vault's public key, HKDF-SHA256,
/// then AES-256-GCM. File layout: "FINBOX1" | ephemeral public key (32) | nonce, ciphertext, tag.
enum Inbox {
    static let header = Data("FINBOX1".utf8)
    private static let info = Data("fallow-inbox-v1".utf8)

    enum InboxError: Error {
        case noKey, unreadable
    }

    static func seal(_ entry: InboxEntry, to publicKey: Data) throws -> Data {
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let key = try symmetricKey(
            secret: ephemeral.sharedSecretFromKeyAgreement(with: recipient),
            ephemeral: ephemeral.publicKey.rawRepresentation,
            recipient: publicKey
        )
        let plain = try JSONEncoder.shared.encode(entry)
        guard let combined = try AES.GCM.seal(plain, using: key).combined else { throw InboxError.unreadable }
        return header + ephemeral.publicKey.rawRepresentation + combined
    }

    static func open(_ box: Data, with privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> InboxEntry {
        let start = header.count
        guard box.starts(with: header), box.count > start + 32 + 28 else { throw InboxError.unreadable }
        let ephemeralRaw = Data(box[start..<(start + 32)])
        let ephemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralRaw)
        let key = try symmetricKey(
            secret: privateKey.sharedSecretFromKeyAgreement(with: ephemeral),
            ephemeral: ephemeralRaw,
            recipient: privateKey.publicKey.rawRepresentation
        )
        let sealed = try AES.GCM.SealedBox(combined: Data(box[(start + 32)...]))
        let plain = try AES.GCM.open(sealed, using: key)
        return try JSONDecoder.shared.decode(InboxEntry.self, from: plain)
    }

    private static func symmetricKey(secret: SharedSecret, ephemeral: Data, recipient: Data) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephemeral + recipient,
            sharedInfo: info,
            outputByteCount: 32
        )
    }

    /// Drops an entry in the shared inbox folder. Throws when the vault has not
    /// published its key yet (Fallow was never opened since this feature came).
    static func post(_ entry: InboxEntry, folder: URL = SharedStore.inboxFolder, publicKey: Data? = SharedStore.readPublicKey()) throws {
        guard let publicKey else { throw InboxError.noKey }
        let box = try seal(entry, to: publicKey)
        let name = "\(Int(entry.createdAt.timeIntervalSince1970 * 1000))-\(UUID().uuidString).box"
        try box.write(to: folder.appending(path: name), options: SharedStore.writeOptions)
    }

    /// The sealed files waiting, oldest first.
    static func waiting(in folder: URL = SharedStore.inboxFolder) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "box" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
