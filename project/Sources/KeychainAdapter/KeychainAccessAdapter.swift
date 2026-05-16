// KeychainAccessAdapter.swift — infrastructure adapter for macOS Keychain
// Implements: KeychainAccessPort from LocalPersistence
// ADR refs: ADR-0010 (Keychain placement), ADR-0018 (namespace partitioning)
// Security class: kSecAttrAccessibleWhenUnlockedThisDeviceOnly (enforced on every write)

import Foundation
import Security
import LocalPersistence

// MARK: - KeychainAccessAdapter

/// Adapter that implements `KeychainAccessPort` using the macOS Security
/// framework.
///
/// Every write enforces `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and
/// `kSecUseDataProtectionKeychain = true`. Items are stored under
/// `kSecClassGenericPassword` keyed by `(kSecAttrService, kSecAttrAccount)`.
///
/// OSStatus → `KeychainAccessError` mapping:
/// - `errSecItemNotFound` → `.itemNotFound`
/// - `errSecDuplicateItem` → `.duplicate` (resolved by `writeSecret` via upsert)
/// - `errSecInteractionNotAllowed` → `.keychainLocked`
/// - anything else → `.securityError(status:detail:)`
public struct KeychainAccessAdapter: KeychainAccessPort {
    public init() {}

    // MARK: - KeychainAccessPort

    public func readSecret(for entry: KeychainEntry) async throws -> Data {
        var query = baseQuery(for: entry)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainAccessError.securityError(status: status, detail: "Unexpected result type")
            }
            return data
        case errSecItemNotFound:
            throw KeychainAccessError.itemNotFound(entry: entry)
        case errSecInteractionNotAllowed:
            throw KeychainAccessError.keychainLocked
        default:
            throw KeychainAccessError.securityError(status: status, detail: SecCopyErrorMessageString(status, nil) as? String ?? "Unknown")
        }
    }

    public func writeSecret(_ secret: Data, for entry: KeychainEntry) async throws {
        guard entry.isValid else {
            throw KeychainAccessError.invalidEntry(violations: collectViolations(entry))
        }
        // Try to add; if duplicate exists, update.
        let addStatus = SecItemAdd(addAttributes(secret: secret, entry: entry) as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            try await updateExisting(secret: secret, entry: entry)
        case errSecInteractionNotAllowed:
            throw KeychainAccessError.keychainLocked
        default:
            throw KeychainAccessError.securityError(status: addStatus, detail: SecCopyErrorMessageString(addStatus, nil) as? String ?? "Unknown")
        }
    }

    public func deleteSecret(for entry: KeychainEntry) async throws {
        let status = SecItemDelete(baseQuery(for: entry) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        case errSecInteractionNotAllowed:
            throw KeychainAccessError.keychainLocked
        default:
            throw KeychainAccessError.securityError(status: status, detail: SecCopyErrorMessageString(status, nil) as? String ?? "Unknown")
        }
    }

    public func listEntries(namespace: KeychainServiceNamespace) async throws -> [KeychainEntry] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.rawValue,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            kSecUseDataProtectionKeychain: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            let items = (result as? [[CFString: Any]]) ?? []
            return items.compactMap { entry(from: $0, namespace: namespace) }
        case errSecItemNotFound:
            return []
        case errSecInteractionNotAllowed:
            throw KeychainAccessError.keychainLocked
        default:
            throw KeychainAccessError.securityError(status: status, detail: SecCopyErrorMessageString(status, nil) as? String ?? "Unknown")
        }
    }

    // MARK: - Private helpers

    private func baseQuery(for entry: KeychainEntry) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: entry.serviceKey,
            kSecAttrAccount: entry.account,
            kSecUseDataProtectionKeychain: true,
        ]
    }

    private func addAttributes(secret: Data, entry: KeychainEntry) -> [CFString: Any] {
        var attrs = baseQuery(for: entry)
        attrs[kSecValueData] = secret
        attrs[kSecAttrLabel] = entry.label
        attrs[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return attrs
    }

    private func updateExisting(secret: Data, entry: KeychainEntry) async throws {
        let update: [CFString: Any] = [
            kSecValueData: secret,
            kSecAttrLabel: entry.label,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(for: entry) as CFDictionary, update as CFDictionary)
        guard status == errSecSuccess else {
            throw KeychainAccessError.securityError(status: status, detail: SecCopyErrorMessageString(status, nil) as? String ?? "Unknown")
        }
    }

    private func entry(from attributes: [CFString: Any], namespace: KeychainServiceNamespace) -> KeychainEntry? {
        guard let account = attributes[kSecAttrAccount] as? String else { return nil }
        let label = attributes[kSecAttrLabel] as? String ?? account
        return KeychainEntry(
            namespace: namespace,
            account: account,
            label: label
        )
    }

    private func collectViolations(_ entry: KeychainEntry) -> [String] {
        var violations: [String] = []
        if entry.account.isEmpty { violations.append("account must not be empty") }
        if entry.label.isEmpty { violations.append("label must not be empty") }
        if !(1...16_384).contains(entry.maxPayloadBytes) {
            violations.append("maxPayloadBytes must be in 1...16384")
        }
        return violations
    }
}
