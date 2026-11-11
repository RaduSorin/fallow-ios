import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Where the vault key lives. The app uses the Keychain; tests use memory.
@MainActor
protocol VaultKeyStore {
    func hasKey() -> Bool
    func createKey() throws -> SymmetricKey
    func loadKey(reason: String) async throws -> SymmetricKey
    func deleteKey() throws
}

/// Keeps the 256-bit vault key in the Keychain, on this device only.
/// Reading it needs Face ID (or the phone passcode as a fallback).
struct KeychainKeyStore: VaultKeyStore {
    var service = "app.fallow.ios.vault"
    var account = "vault-key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func hasKey() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnAttributes as String] = true
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    func createKey() throws -> SymmetricKey {
        try deleteKey()
        let key = SymmetricKey(size: .bits256)
        var query = baseQuery
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        #if targetEnvironment(simulator)
        // Simulators usually have no passcode, so no biometric protection there.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #else
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .userPresence,
            &error
        ) else {
            throw VaultError.keychain(errSecParam)
        }
        query[kSecAttrAccessControl as String] = access
        #endif
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        return key
    }

    func loadKey(reason: String) async throws -> SymmetricKey {
        let service = service
        let account = account
        // The Keychain shows the Face ID prompt itself. That call blocks,
        // so it runs off the main thread.
        let result: Result<Data, VaultError> = await Task.detached {
            let context = LAContext()
            context.localizedReason = reason
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecUseAuthenticationContext as String: context,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            switch status {
            case errSecSuccess:
                guard let data = item as? Data else { return .failure(.corrupted) }
                return .success(data)
            case errSecItemNotFound:
                return .failure(.noKey)
            case errSecUserCanceled:
                return .failure(.cancelled)
            default:
                return .failure(.keychain(status))
            }
        }.value
        return SymmetricKey(data: try result.get())
    }

    func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychain(status)
        }
    }
}

/// For tests and previews.
@MainActor
final class InMemoryKeyStore: VaultKeyStore {
    private var key: SymmetricKey?
    var failNextLoad: VaultError?

    init() {}

    func hasKey() -> Bool { key != nil }

    func createKey() throws -> SymmetricKey {
        let new = SymmetricKey(size: .bits256)
        key = new
        return new
    }

    func loadKey(reason: String) async throws -> SymmetricKey {
        if let failure = failNextLoad {
            failNextLoad = nil
            throw failure
        }
        guard let key else { throw VaultError.noKey }
        return key
    }

    func deleteKey() throws { key = nil }
}
