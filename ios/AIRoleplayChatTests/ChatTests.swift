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

private func jsonBody(of request: URLRequest) throws -> [String: Any] {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite(.serialized)
@MainActor
struct ChatTests {
    private static let evaluationJSON = #"{"criteria":{"listening":{"score":20,"reason":"事情を確認できました。"},"consideration":{"score":21,"reason":"責めずに応じました。"},"clarity":{"score":19,"reason":"指示が伝わりました。"},"action":{"score":18,"reason":"期限も確認しましょう。"}},"totalScore":78,"goodPoint":"先に事情を聞けました。","improvement":"報告時刻を決めましょう。","rephrase":"15時に進捗を教えてもらえる？"}"#
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
        #expect(json["provider"] == nil)
    }

    @Test(arguments: [AIProvider.openai, .gemini])
    func selectedProviderIsSentAndPreservedForEveryTurn(provider: AIProvider) async throws {
        let store = try container()
        let context = ModelContext(store)
        let conversation = Conversation(provider: provider)
        context.insert(conversation)
        try context.save()
        StubURLProtocol.handler = { request in
            let json = try jsonBody(of: request)
            #expect(json["provider"] as? String == provider.rawValue)
            #expect(json["model"] == nil)
            return (200, try JSONSerialization.data(withJSONObject: [
                "provider": provider.rawValue, "practice": "five-turns",
                "message": ["role": "assistant", "content": "あと少しです。"],
            ]))
        }
        let session = ChatSession(conversation: conversation, context: context, api: client())
        session.draft = "資料はできた？"
        await session.send()
        let resumed = ChatSession(conversation: conversation, context: context, api: client())
        resumed.draft = "何か手伝える？"
        await resumed.send()
        #expect(session.errorMessage == nil)
        #expect(resumed.errorMessage == nil)
        #expect(conversation.messages.count == 4)
        #expect(conversation.provider == provider)
    }

    @Test(arguments: ["openai", "missing"])
    func mismatchedOrMissingProviderDoesNotSaveTurn(returnedProvider: String) async throws {
        let store = try container()
        let context = ModelContext(store)
        let conversation = Conversation(provider: .gemini)
        context.insert(conversation)
        try context.save()
        StubURLProtocol.handler = { _ in
            var json: [String: Any] = ["message": ["role": "assistant", "content": "あと少しです。"]]
            if returnedProvider != "missing" { json["provider"] = returnedProvider }
            return (200, try JSONSerialization.data(withJSONObject: json))
        }
        let session = ChatSession(conversation: conversation, context: context, api: client())
        session.draft = "資料はできた？"
        await session.send()
        #expect(session.errorMessage == ChatAPIError.providerMismatch.localizedDescription)
        #expect(session.draft == "資料はできた？")
        #expect(conversation.messages.isEmpty)
        #expect(conversation.provider == .gemini)
    }

    @Test func legacyConversationRecordsConfirmedProviderAfterSuccessfulReply() async throws {
        let store = try container()
        let context = ModelContext(store)
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()
        #expect(conversation.provider == nil)
        StubURLProtocol.handler = { request in
            let json = try jsonBody(of: request)
            #expect(json["provider"] == nil)
            return (200, Data(#"{"practice":"five-turns","provider":"gemini","message":{"role":"assistant","content":"あと少しです。"}}"#.utf8))
        }
        let session = ChatSession(conversation: conversation, context: context, api: client())
        session.draft = "資料はできた？"
        await session.send()
        #expect(session.errorMessage == nil)
        #expect(conversation.provider == .gemini)
        #expect(conversation.messages.count == 2)
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

    @Test(arguments: [AIProvider.openai, .gemini])
    func conversationSurvivesStoreReopeningAndPreservesOrder(provider: AIProvider) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // SwiftData can retain SQLite handles beyond this scope. Let the test app's
        // temporary directory own cleanup instead of unlinking a database still in use.
        let url = directory.appendingPathComponent("history.store")
        do {
            let store = try container(url: url)
            let context = ModelContext(store)
            let conversation = Conversation(provider: provider)
            context.insert(conversation)
            conversation.appendTurn(userText: "進み具合は？", reply: "半分まで終わっています。")
            conversation.appendTurn(userText: "何か困っている？", reply: "集計を手伝っていただけると助かります。")
            try context.save()
        }
        let reopened = try container(url: url)
        let context = ModelContext(reopened)
        let saved = try #require(context.fetch(FetchDescriptor<Conversation>()).first)
        #expect(saved.scenarioID == "late-report")
        #expect(saved.provider == provider)
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
            return (200, Data(#"{"practice":"five-turns","message":{"role":"assistant","content":"すみません。"}}"#.utf8))
        }
        let request = try ChatRequest(scenarioID: "late-report", history: [], text: "状況は？")
        let reply = try await client().send(request)
        #expect(reply.message == APIMessage(role: .assistant, content: "すみません。"))
    }

    #if DEBUG
    @Test func cloudDevelopmentRequestIncludesAccessTokenOverHTTPS() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://example.test/v1/chat")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer development-test-token")
            return (200, Data(#"{"practice":"five-turns","message":{"role":"assistant","content":"すみません。"}}"#.utf8))
        }
        var api = client()
        api.baseURL = URL(string: "https://example.test")
        api.developmentAccessToken = "development-test-token"
        let request = try ChatRequest(scenarioID: "late-report", history: [], text: "状況は？")
        #expect(try await api.send(request).message.content == "すみません。")
    }

    @Test func developmentTokenCannotBeSentOverHTTP() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("The token must not be sent over HTTP")
            return (200, Data())
        }
        var api = client()
        api.developmentAccessToken = "development-test-token"
        let request = try ChatRequest(scenarioID: "late-report", history: [], text: "状況は？")
        await #expect(throws: ChatAPIError.self) { try await api.send(request) }
    }
    #endif

    @Test(arguments: [
        #"{"practice":"five-turns","message":{"role":"user","content":"wrong role"}}"#,
        #"{"practice":"five-turns","message":{"role":"assistant","content":" "}}"#,
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

        StubURLProtocol.handler = { _ in (200, Data(#"{"practice":"five-turns","message":{"role":"assistant","content":"あと少しです。"}}"#.utf8)) }
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

    @Test(arguments: [AIProvider.openai, .gemini])
    func fiveTurnsEndAutomaticallyAndPersistOneEvaluation(provider: AIProvider) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // SwiftData can retain SQLite handles beyond this scope. Let the test app's
        // temporary directory own cleanup instead of unlinking a database still in use.
        let url = directory.appendingPathComponent("practice.store")
        var chatCalls = 0
        var evaluationCalls = 0
        StubURLProtocol.handler = { request in
            let json = try jsonBody(of: request)
            #expect(json["provider"] as? String == provider.rawValue)
            #expect(json["practice"] as? String == "five-turns")
            let messages = try #require(json["messages"] as? [[String: String]])
            if request.url?.path == "/v1/evaluation" {
                evaluationCalls += 1
                #expect(messages.count == 10)
                #expect(messages.first?["content"] == "質問1")
                #expect(messages.last?["role"] == "assistant")
                return (200, Data("{\"provider\":\"\(provider.rawValue)\",\"evaluation\":\(Self.evaluationJSON)}".utf8))
            }
            chatCalls += 1
            #expect(messages.count == chatCalls * 2 - 1)
            return (200, Data("{\"provider\":\"\(provider.rawValue)\",\"practice\":\"five-turns\",\"message\":{\"role\":\"assistant\",\"content\":\"承知しました。\"}}".utf8))
        }
        do {
            let store = try container(url: url)
            let context = ModelContext(store)
            let conversation = Conversation(provider: provider)
            context.insert(conversation)
            try context.save()
            let session = ChatSession(conversation: conversation, context: context, api: client())
            for turn in 1...5 {
                session.draft = "質問\(turn)"
                await session.send()
                #expect(session.errorMessage == nil)
                #expect(conversation.completedTurns == turn)
            }
            #expect(conversation.isComplete)
            #expect(conversation.evaluation?.totalScore == 78)
            session.draft = "6回目は送信しない"
            #expect(!session.canSend)
            await session.send()
            await session.evaluateIfNeeded()
            #expect(chatCalls == 5)
            #expect(evaluationCalls == 1)
        }
        let reopened = try container(url: url)
        let context = ModelContext(reopened)
        let saved = try #require(context.fetch(FetchDescriptor<Conversation>()).first)
        #expect(saved.isComplete)
        #expect(saved.messages.count == 10)
        #expect(saved.evaluation?.totalScore == 78)
        #expect(saved.provider == provider)
        await ChatSession(conversation: saved, context: context, api: client()).evaluateIfNeeded()
        #expect(evaluationCalls == 1)
    }

    @Test func failedFifthReplyDoesNotAdvanceAndEvaluationRetryNeverResendsChat() async throws {
        let store = try container()
        let context = ModelContext(store)
        let conversation = Conversation(provider: .gemini)
        context.insert(conversation)
        for _ in 0..<4 { conversation.appendTurn(userText: "状況は？", reply: "あと少しです。") }
        try context.save()
        let session = ChatSession(conversation: conversation, context: context, api: client())
        session.draft = "15時に報告してもらえる？"
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        await session.send()
        #expect(conversation.completedTurns == 4)
        #expect(session.canSend)
        #expect(!session.draft.isEmpty)

        StubURLProtocol.handler = { request in
            if request.url?.path == "/v1/evaluation" { throw URLError(.timedOut) }
            return (200, Data(#"{"provider":"gemini","practice":"five-turns","message":{"role":"assistant","content":"承知しました。"}}"#.utf8))
        }
        await session.send()
        #expect(conversation.messages.count == 10)
        #expect(conversation.isComplete)
        #expect(conversation.evaluation == nil)
        #expect(session.evaluationError != nil)
        #expect(session.errorMessage == nil)
        #expect(session.draft.isEmpty)
        #expect(!session.isEvaluating)

        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/evaluation")
            return (200, Data("{\"provider\":\"gemini\",\"evaluation\":\(Self.evaluationJSON)}".utf8))
        }
        let resumed = ChatSession(conversation: conversation, context: context, api: client())
        await resumed.evaluateIfNeeded()
        #expect(conversation.messages.count == 10)
        #expect(conversation.evaluation?.totalScore == 78)
        #expect(resumed.evaluationError == nil)
    }

    @Test(arguments: ["bad-total", "bad-provider", "empty-feedback", "out-of-range", "cancelled"])
    func unusableEvaluationLeavesFinishedConversationAvailableForRetry(failure: String) async throws {
        let store = try container()
        let context = ModelContext(store)
        let conversation = Conversation(provider: .gemini)
        context.insert(conversation)
        for _ in 0..<5 { conversation.appendTurn(userText: "状況は？", reply: "あと少しです。") }
        try context.save()
        StubURLProtocol.handler = { _ in
            if failure == "cancelled" { throw URLError(.cancelled) }
            var evaluation = Self.evaluationJSON
            if failure == "bad-total" { evaluation = evaluation.replacingOccurrences(of: "\"totalScore\":78", with: "\"totalScore\":100") }
            if failure == "empty-feedback" { evaluation = evaluation.replacingOccurrences(of: "先に事情を聞けました。", with: " ") }
            if failure == "out-of-range" { evaluation = evaluation.replacingOccurrences(of: "\"score\":20", with: "\"score\":26") }
            let provider = failure == "bad-provider" ? "openai" : "gemini"
            return (200, Data("{\"provider\":\"\(provider)\",\"evaluation\":\(evaluation)}".utf8))
        }
        let session = ChatSession(conversation: conversation, context: context, api: client())
        await session.evaluateIfNeeded()
        #expect(conversation.isComplete)
        #expect(conversation.messages.count == 10)
        #expect(conversation.evaluationData == nil)
        #expect(!session.isEvaluating)
        #expect(!session.canSend)
        if failure != "cancelled" { #expect(session.evaluationError != nil) }
    }

    @Test func practicePreservesLongHistoryAndRejectsSixthTurn() throws {
        let history = (0..<8).map { APIMessage(role: $0 % 2 == 0 ? .user : .assistant, content: String(repeating: "あ", count: 4_000)) }
        let request = try ChatRequest(scenarioID: "late-report", history: history, text: "最後の質問", isPractice: true)
        #expect(request.messages.count == 9)
        #expect(request.messages.first?.content == history.first?.content)
        #expect(request.practice == "five-turns")
        #expect(throws: ChatAPIError.self) {
            try ChatRequest(scenarioID: "late-report", history: history + Array(history.prefix(2)), text: "6回目", isPractice: true)
        }
    }

    @Test func evaluationDoesNotStartBeforeFiveTurns() async throws {
        let store = try container()
        let context = ModelContext(store)
        let conversation = Conversation(provider: .gemini)
        context.insert(conversation)
        for _ in 0..<4 { conversation.appendTurn(userText: "状況は？", reply: "あと少しです。") }
        StubURLProtocol.handler = { _ in
            Issue.record("Incomplete practice must not be evaluated")
            return (200, Data())
        }
        await ChatSession(conversation: conversation, context: context, api: client()).evaluateIfNeeded()
        #expect(conversation.evaluationData == nil)
    }

    @Test func oldBackendCannotSilentlyStartANewPractice() async throws {
        let store = try container()
        let context = ModelContext(store)
        let conversation = Conversation(provider: .gemini)
        context.insert(conversation)
        try context.save()
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"provider":"gemini","message":{"role":"assistant","content":"あと少しです。"}}"#.utf8))
        }
        let session = ChatSession(conversation: conversation, context: context, api: client())
        session.draft = "進み具合は？"
        await session.send()
        #expect(session.errorMessage?.contains("未対応") == true)
        #expect(session.draft == "進み具合は？")
        #expect(conversation.messages.isEmpty)
    }
}
