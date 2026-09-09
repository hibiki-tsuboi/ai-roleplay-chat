import Foundation
import SwiftData
import Testing
@testable import AIRoleplayChat

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct ChatTests {
    private func client() -> ChatAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return ChatAPI(baseURL: URL(string: "http://localhost:8787"), session: URLSession(configuration: configuration))
    }

    private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Conversation.self, ChatMessage.self])
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test func requestMatchesWorkerContractAndKeepsLatestMessages() throws {
        let history = (0..<60).map { APIMessage(role: $0 % 2 == 0 ? .user : .assistant, content: "message \($0)") }
        let request = try ChatRequest(scenarioID: "late-report", history: history, text: "  latest  ")
        #expect(request.messages.count == 40)
        #expect(request.messages.first?.content == "message 21")
        #expect(request.messages.last == APIMessage(role: .user, content: "latest"))
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["scenarioId"] as? String == "late-report")
        #expect(json["scenarioID"] == nil)
    }

    @Test func requestUsesUTF16BudgetAndDoesNotMutateHistory() throws {
        let history = (0..<20).map { _ in APIMessage(role: .assistant, content: String(repeating: "😀", count: 2_000)) }
        let request = try ChatRequest(scenarioID: "late-report", history: history, text: "次は？")
        #expect(request.messages.count == 6)
        #expect(request.messages.reduce(0) { $0 + $1.content.utf16.count } <= 24_000)
        #expect(history.count == 20)
        #expect(throws: ChatAPIError.self) {
            try ChatRequest(scenarioID: "late-report", history: [], text: String(repeating: "😀", count: 2_001))
        }
        #expect(throws: ChatAPIError.self) {
            try ChatRequest(scenarioID: "late-report", history: [], text: " \n ")
        }
    }

    @Test func conversationSurvivesStoreReopeningAndPreservesOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.store")
        do {
            let store = try container(url: url)
            let context = ModelContext(store)
            let conversation = Conversation()
            context.insert(conversation)
            conversation.appendTurn(userText: "進み具合は？", reply: "半分まで終わっています。")
            conversation.appendTurn(userText: "何か困っている？", reply: "集計を手伝っていただけると助かります。")
            try context.save()
        }
        let reopened = try container(url: url)
        let context = ModelContext(reopened)
        let saved = try #require(context.fetch(FetchDescriptor<Conversation>()).first)
        #expect(saved.scenarioID == "late-report")
        #expect(saved.sortedMessages.map(\.content) == ["進み具合は？", "半分まで終わっています。", "何か困っている？", "集計を手伝っていただけると助かります。"])
        #expect(saved.sortedMessages.map(\.role) == [.user, .assistant, .user, .assistant])
        #expect(saved.messages.allSatisfy { $0.conversation?.id == saved.id })
    }

    @Test func deletingConversationAlsoDeletesMessages() throws {
        let store = try container()
        let context = ModelContext(store)
        let conversation = Conversation()
        context.insert(conversation)
        conversation.appendTurn(userText: "こんにちは", reply: "お疲れさまです。")
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ChatMessage>()) == 2)
        context.delete(conversation)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ChatMessage>()) == 0)
    }

    @Test func apiPostsToWorkerAndDecodesReply() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "http://localhost:8787/v1/chat")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (200, Data(#"{"message":{"role":"assistant","content":"すみません。"}}"#.utf8))
        }
        let request = try ChatRequest(scenarioID: "late-report", history: [], text: "状況は？")
        let reply = try await client().send(request)
        #expect(reply == APIMessage(role: .assistant, content: "すみません。"))
    }

    @Test(arguments: [
        #"{"message":{"role":"user","content":"wrong role"}}"#,
        #"{"message":{"role":"assistant","content":" "}}"#,
        #"{"unexpected":true}"#,
        "not JSON",
    ])
    func apiRejectsInvalidSuccessResponses(body: String) async throws {
        StubURLProtocol.handler = { _ in (200, Data(body.utf8)) }
        let request = try ChatRequest(scenarioID: "late-report", history: [], text: "状況は？")
        await #expect(throws: ChatAPIError.self) { try await client().send(request) }
    }

    @Test func failedTurnKeepsDraftAndRetryDoesNotDuplicateMessages() async throws {
        let store = try container()
        let context = ModelContext(store)
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()
        let session = ChatSession(conversation: conversation, context: context, api: client())
        session.draft = "資料はできた？"
        StubURLProtocol.handler = { _ in
            (503, Data(#"{"error":{"code":"not_configured","message":"サーバーを設定してください。"}}"#.utf8))
        }
        await session.send()
        #expect(session.errorMessage == "サーバーを設定してください。")
        #expect(session.draft == "資料はできた？")
        #expect(conversation.messages.isEmpty)
        #expect(session.canSend)

        StubURLProtocol.handler = { _ in (200, Data(#"{"message":{"role":"assistant","content":"あと少しです。"}}"#.utf8)) }
        await session.send()
        #expect(session.errorMessage == nil)
        #expect(session.draft.isEmpty)
        #expect(conversation.sortedMessages.map(\.content) == ["資料はできた？", "あと少しです。"])
        #expect(try context.fetchCount(FetchDescriptor<ChatMessage>()) == 2)
    }

    @Test func cancelledRequestLeavesDraftWithoutSavingATurn() async throws {
        let store = try container()
        let context = ModelContext(store)
        let conversation = Conversation()
        context.insert(conversation)
        let session = ChatSession(conversation: conversation, context: context, api: client())
        session.draft = "資料はできた？"
        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        await session.send()
        #expect(session.draft == "資料はできた？")
        #expect(conversation.messages.isEmpty)
        #expect(!session.isSending)
    }
}
