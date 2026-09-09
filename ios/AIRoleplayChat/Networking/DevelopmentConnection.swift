#if DEBUG
import Foundation
import Security

struct DevelopmentConnection: Codable, Equatable {
    let address: String
    let accessToken: String?

    var canPersist: Bool {
        guard let url = URL(string: address), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return false }
        return !(accessToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func resolve(defaultAddress: String, environment: [String: String], saved: Self?) -> Self {
        // An explicit override must never borrow a saved token for a different server.
        if environment["ROLEPLAY_API_BASE_URL"] != nil || environment["ROLEPLAY_DEV_ACCESS_TOKEN"] != nil {
            return Self(address: environment["ROLEPLAY_API_BASE_URL"] ?? defaultAddress,
                        accessToken: environment["ROLEPLAY_DEV_ACCESS_TOKEN"])
        }
        return saved ?? Self(address: defaultAddress, accessToken: nil)
    }
}

struct DevelopmentConnectionStore {
    static let shared = Self(service: "jp.hibiki.AIRoleplayChat.development-connection")
    let service: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "backend"]
    }

    func load() -> DevelopmentConnection? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let connection = try? JSONDecoder().decode(DevelopmentConnection.self, from: data),
              connection.canPersist else { return nil }
        return connection
    }

    func save(_ connection: DevelopmentConnection) throws {
        guard connection.canPersist else { throw StoreError.invalidConfiguration }
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(connection),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.keychain(status) }
    }

    enum StoreError: Error {
        case invalidConfiguration
        case keychain(OSStatus)
    }

    static func captureLaunchConfiguration(environment: [String: String]) throws {
        // UI test launches use their own explicit connection and must not change device credentials.
        guard environment["ROLEPLAY_TEST_STORE"] == nil else { return }
        if environment["ROLEPLAY_CLEAR_DEV_CONNECTION"] == "1" { try shared.clear() }
        guard let address = environment["ROLEPLAY_API_BASE_URL"],
              let token = environment["ROLEPLAY_DEV_ACCESS_TOKEN"] else { return }
        let connection = DevelopmentConnection(address: address, accessToken: token)
        if connection.canPersist { try shared.save(connection) }
    }
}
#endif
