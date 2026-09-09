#if DEBUG
import Foundation
import Testing
@testable import AIRoleplayChat

@MainActor
struct DevelopmentConnectionTests {
    private let cloud = DevelopmentConnection(address: "https://example.test", accessToken: "test-only-token")

    @Test func homeScreenLaunchRestoresTheSavedServerAndToken() {
        let connection = DevelopmentConnection.resolve(defaultAddress: "http://localhost:8787", environment: [:], saved: cloud)
        #expect(connection == cloud)
    }

    @Test func unconfiguredSimulatorKeepsTheLocalDefault() {
        let connection = DevelopmentConnection.resolve(defaultAddress: "http://localhost:8787", environment: [:], saved: nil)
        #expect(connection.address == "http://localhost:8787")
        #expect(connection.accessToken == nil)
    }

    @Test(arguments: ["http://localhost:8787", "https://another.example.test"])
    func explicitServerNeverReceivesTheSavedCredential(address: String) {
        let connection = DevelopmentConnection.resolve(defaultAddress: "http://localhost:8787",
            environment: ["ROLEPLAY_API_BASE_URL": address], saved: cloud)
        #expect(connection.address == address)
        #expect(connection.accessToken == nil)
    }

    @Test func tokenWithoutServerDoesNotUseASavedServer() {
        let connection = DevelopmentConnection.resolve(defaultAddress: "http://localhost:8787",
            environment: ["ROLEPLAY_DEV_ACCESS_TOKEN": "different-test-token"], saved: cloud)
        #expect(connection.address == "http://localhost:8787")
        #expect(connection.accessToken == "different-test-token")
        #expect(!connection.canPersist)
    }

    @Test(arguments: [
        "http://localhost:8787", "https://user:pass@example.test", "not a URL",
        "https://example.test?token=ignored", "https://example.test#ignored",
    ])
    func unsafeOrAmbiguousAddressesCannotBeSaved(address: String) {
        #expect(!DevelopmentConnection(address: address, accessToken: "test-only-token").canPersist)
    }

    @Test func emptyCredentialsCannotBeSaved() {
        #expect(!DevelopmentConnection(address: "https://example.test", accessToken: nil).canPersist)
        #expect(!DevelopmentConnection(address: "https://example.test", accessToken: " \n ").canPersist)
    }

    @Test func keychainPersistsUpdatesAndClearsTheConnection() throws {
        let service = "jp.hibiki.AIRoleplayChat.tests.\(UUID().uuidString)"
        let store = DevelopmentConnectionStore(service: service)
        defer { try? store.clear() }
        #expect(store.load() == nil)
        try store.save(cloud)
        #expect(DevelopmentConnectionStore(service: service).load() == cloud)
        let updated = DevelopmentConnection(address: "https://updated.example.test", accessToken: "updated-test-token")
        try store.save(updated)
        #expect(store.load() == updated)
        try store.clear()
        #expect(store.load() == nil)
    }
}
#endif
