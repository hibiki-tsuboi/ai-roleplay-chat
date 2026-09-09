import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct APIMessage: Codable, Equatable {
    let role: MessageRole
    let content: String
}

struct ChatRequest: Encodable {
    let scenarioId: String
    let provider: AIProvider?
    let messages: [APIMessage]
    let practice: String?

    // Match backend/src/chat.ts and docs/api.md. Swift's Character count differs from UTF-16.
    static let maxMessages = 40
    static let maxMessageLength = 4_000
    static let maxTotalLength = 24_000
    static let practiceMode = "five-turns"

    init(scenarioID: String, provider: AIProvider? = nil, history: [APIMessage], text: String, isPractice: Bool = false) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= Self.maxMessageLength else {
            throw ChatAPIError.invalidMessage
        }
        scenarioId = scenarioID
        self.provider = provider
        practice = isPractice ? Self.practiceMode : nil
        if isPractice {
            guard history.count < Conversation.turnLimit * 2, history.count % 2 == 0,
                  history.enumerated().allSatisfy({ index, message in
                      message.role == (index % 2 == 0 ? .user : .assistant)
                          && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && message.content.utf16.count <= Self.maxMessageLength
                  }) else { throw ChatAPIError.invalidMessage }
            messages = history + [APIMessage(role: .user, content: text)]
            return
        }
        var recent = Array((history + [APIMessage(role: .user, content: text)]).suffix(Self.maxMessages))
        while recent.count > 1 && recent.reduce(0, { $0 + $1.content.utf16.count }) > Self.maxTotalLength {
            recent.removeFirst()
        }
        messages = recent
    }
}

struct ChatResponse: Decodable {
    let provider: AIProvider?
    let practice: String?
    let message: APIMessage
}

private struct APIErrorResponse: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String
    }
    let error: Detail
}

enum ChatAPIError: LocalizedError {
    case notConfigured
    case invalidMessage
    case invalidResponse
    case providerMismatch
    case server(String)
    case connectionFailed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "チャットサーバーの接続先が設定されていません。"
        case .invalidMessage:
            "空白以外のメッセージを4,000文字以内で入力してください。"
        case .invalidResponse:
            "返答を読み取れませんでした。もう一度送信してください。"
        case .providerMismatch:
            "選択した AI の返答を確認できませんでした。接続先を確認して、もう一度お試しください。"
        case .server(let message):
            message
        case .connectionFailed:
            "サーバーに接続できません。接続を確認して、もう一度送信してください。"
        case .timedOut:
            "返答に時間がかかっています。少し待ってから、もう一度送信してください。"
        }
    }
}

struct ChatAPI {
    var baseURL: URL?
    var session: URLSession = .shared
    #if DEBUG
    var developmentAccessToken: String?
    #endif

    static var configured: ChatAPI {
        let address = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let saved = environment["ROLEPLAY_TEST_STORE"] == nil ? DevelopmentConnectionStore.shared.load() : nil
        let connection = DevelopmentConnection.resolve(defaultAddress: address, environment: environment, saved: saved)
        return ChatAPI(baseURL: URL(string: connection.address), developmentAccessToken: connection.accessToken)
        #else
        return ChatAPI(baseURL: URL(string: address))
        #endif
    }

    func send(_ payload: ChatRequest) async throws -> ChatResponse {
        let data = try await post(payload, path: "v1/chat")
        guard let reply = try? JSONDecoder().decode(ChatResponse.self, from: data),
              reply.message.role == .assistant,
              !reply.message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reply.message.content.utf16.count <= ChatRequest.maxMessageLength else {
            throw ChatAPIError.invalidResponse
        }
        if let selected = payload.provider, reply.provider != selected {
            throw ChatAPIError.providerMismatch
        }
        if let practice = payload.practice, reply.practice != practice {
            throw ChatAPIError.server("接続先が5往復の練習に未対応です。バックエンドを更新してください。")
        }
        return reply
    }

    func evaluate(_ payload: EvaluationRequest) async throws -> PracticeEvaluation {
        let data = try await post(payload, path: "v1/evaluation")
        guard let reply = try? JSONDecoder().decode(EvaluationResponse.self, from: data), reply.evaluation.isValid else {
            throw ChatAPIError.invalidResponse
        }
        guard reply.provider == payload.provider else { throw ChatAPIError.providerMismatch }
        return reply.evaluation
    }

    private func post(_ payload: some Encodable, path: String) async throws -> Data {
        guard let baseURL, let host = baseURL.host, !host.isEmpty,
              baseURL.user == nil, baseURL.password == nil else {
            throw ChatAPIError.notConfigured
        }
        #if DEBUG
        guard baseURL.scheme == "https" || baseURL.scheme == "http" else {
            throw ChatAPIError.notConfigured
        }
        #else
        guard baseURL.scheme == "https" else { throw ChatAPIError.notConfigured }
        #endif

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        #if DEBUG
        if let token = developmentAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            guard baseURL.scheme == "https" else { throw ChatAPIError.notConfigured }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #endif
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? ChatAPIError.timedOut : ChatAPIError.connectionFailed
        }
        guard let response = response as? HTTPURLResponse else { throw ChatAPIError.invalidResponse }
        let decoder = JSONDecoder()
        guard (200..<300).contains(response.statusCode) else {
            let detail = try? decoder.decode(APIErrorResponse.self, from: data)
            throw ChatAPIError.server(detail?.error.message ?? "返答を取得できませんでした。もう一度送信してください。")
        }
        return data
    }
}
