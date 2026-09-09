import SwiftData
import SwiftUI

@main
struct AIRoleplayChatApp: App {
    @State private var store = Result { try makeContainer() }

    init() {
        #if DEBUG
        do {
            try DevelopmentConnectionStore.captureLaunchConfiguration(environment: ProcessInfo.processInfo.environment)
        } catch {
            NSLog("Could not save the development connection to Keychain.")
        }
        let api = ChatAPI.configured
        NSLog("Development backend host: %@; access token configured: %@",
              api.baseURL?.host ?? "unset", api.developmentAccessToken?.isEmpty == false ? "yes" : "no")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            switch store {
            case .success(let container):
                ContentView()
                    .modelContainer(container)
                    .defaultAppStorage(Self.preferences)
            case .failure:
                ContentUnavailableView {
                    Label("会話履歴を開けませんでした", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("端末の空き容量などを確認して、もう一度お試しください。")
                } actions: {
                    Button("再試行") { store = Result { try Self.makeContainer() } }
                }
            }
        }
    }

    private static var preferences: UserDefaults {
        #if DEBUG
        if let testID = ProcessInfo.processInfo.environment["ROLEPLAY_TEST_STORE"],
           let uuid = UUID(uuidString: testID),
           let preferences = UserDefaults(suiteName: "UITests-\(uuid.uuidString)") {
            return preferences
        }
        #endif
        return .standard
    }

    private static func makeContainer() throws -> ModelContainer {
        // Keep the original Xcode sample's Item store intact.
        var storeName = "RoleplayChat"
        #if DEBUG
        if let testID = ProcessInfo.processInfo.environment["ROLEPLAY_TEST_STORE"],
           let uuid = UUID(uuidString: testID) {
            storeName = "UITests-\(uuid.uuidString)"
        }
        #endif
        let schema = Schema([Conversation.self, ChatMessage.self])
        let directory = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(storeName).store")
        let configuration = ModelConfiguration(storeName, schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
