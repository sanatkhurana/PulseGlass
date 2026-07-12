import Foundation
import Security

// MARK: - Keychain custody (§6.5, §8)

/// Thin wrapper over Keychain generic-password items. Credentials (API key,
/// host, project ID) live here and only here — never UserDefaults, never the
/// App Group file container, never logs.
public struct KeychainStore: Sendable {
    public let service: String
    /// Shared keychain access group so the widget extension can read the same
    /// items. `nil` for unit tests / environments without entitlements.
    public let accessGroup: String?

    public init(service: String = "com.example.pulseglass", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public enum KeychainError: Error, Equatable {
        case unhandled(OSStatus)
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public func set(_ data: Data, account: String) throws {
        var attributes = baseQuery(account: account)
        // AfterFirstUnlock: the widget must be able to refresh after
        // reboot-then-unlock even while the device is later locked (§6.5).
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        SecItemDelete(baseQuery(account: account) as CFDictionary)
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func get(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

// MARK: - Profiles (§4.1, §6.3)

/// One connection profile: host + project + a reference to its Keychain-held key.
/// This metadata is itself stored in the Keychain (single item) so the widget
/// intent can enumerate profiles without the app running.
public struct Profile: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var host: URL
    public var projectID: Int

    public init(id: UUID = UUID(), name: String, host: URL, projectID: Int) {
        self.id = id
        self.name = name
        self.host = host
        self.projectID = projectID
    }

    /// Settings shows `phx_…last4` only (§8); the full key never renders.
    public static func keyPreview(_ key: String) -> String {
        guard key.count > 8 else { return "phx_…" }
        return "phx_…\(key.suffix(4))"
    }
}

public struct ProfileStore: Sendable {
    private let keychain: KeychainStore
    private static let profilesAccount = "profiles"

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    public func loadProfiles() -> [Profile] {
        guard let data = try? keychain.get(account: Self.profilesAccount) else { return [] }
        return (try? JSONDecoder().decode([Profile].self, from: data)) ?? []
    }

    public func saveProfiles(_ profiles: [Profile]) throws {
        try keychain.set(JSONEncoder().encode(profiles), account: Self.profilesAccount)
    }

    public func apiKey(for profileID: UUID) throws -> String {
        guard let data = try keychain.get(account: "key-\(profileID.uuidString)"),
              let key = String(data: data, encoding: .utf8) else {
            throw PostHogError.invalidKey
        }
        return key
    }

    public func setAPIKey(_ key: String, for profileID: UUID) throws {
        try keychain.set(Data(key.utf8), account: "key-\(profileID.uuidString)")
    }

    public func removeProfile(_ profileID: UUID) throws {
        var profiles = loadProfiles()
        profiles.removeAll { $0.id == profileID }
        try saveProfiles(profiles)
        try keychain.delete(account: "key-\(profileID.uuidString)")
    }

    /// Destructive sign-out: wipes every profile and key (§5.5).
    public func wipeAll() throws {
        for profile in loadProfiles() {
            try? keychain.delete(account: "key-\(profile.id.uuidString)")
        }
        try keychain.delete(account: Self.profilesAccount)
    }
}
