import SwiftData
import SwiftUI

struct ChatView: View {
    @State private var session: ChatSession
    @State private var sendTask: Task<Void, Never>?
    let onRestart: () -> Void

    init(conversation: Conversation, context: ModelContext, onRestart: @escaping () -> Void) {
        _session = State(initialValue: ChatSession(conversation: conversation, context: context))
        self.onRestart = onRestart
    }

    var body: some View {
        @Bindable var session = session
        Group {
            if session.conversation.isComplete {
                PracticeResultView(conversation: session.conversation, isEvaluating: session.isEvaluating,
                                   errorMessage: session.evaluationError, onRetry: {
                    guard sendTask == nil else { return }
                    sendTask = Task {
                        await session.evaluateIfNeeded()
                        sendTask = nil
                    }
                }, onRestart: onRestart)
            } else {
                chatMessages
            }
        }
        .navigationTitle(session.conversation.isComplete ? "練習の結果" : "\(session.conversation.characterName)さんとの会話")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(session.conversation.isComplete ? "練習の結果" : "\(session.conversation.characterName)さんとの会話")
                        .font(.headline)
                    if let provider = session.conversation.provider {
                        Text(provider.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("conversationProvider")
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if session.conversation.isPractice && !session.conversation.isComplete {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(session.conversation.completedTurns) / 5 往復")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("practiceProgress")
                        Spacer()
                        Text(session.conversation.completedTurns == 4 ? "次が最後のひと言です" : "5往復で結果発表")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(session.conversation.completedTurns), total: 5)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !session.conversation.isComplete {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = session.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("sendError")
                    }
                    if session.draftLength > ChatRequest.maxMessageLength {
                        Text("メッセージを短くしてください（上限4,000文字。絵文字などは複数文字として数えます）。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    HStack(alignment: .bottom, spacing: 12) {
                        TextField("\(session.conversation.characterName)さんに話しかける", text: $session.draft, axis: .vertical)
                            .lineLimit(1...5)
                            .textFieldStyle(.roundedBorder)
                            .disabled(session.isSending)
                            .accessibilityIdentifier("messageInput")
                        Button {
                            guard sendTask == nil else { return }
                            sendTask = Task {
                                await session.send()
                                sendTask = nil
                            }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("送信")
                        .accessibilityIdentifier("sendMessage")
                        .disabled(!session.canSend)
                    }
                }
                .padding()
                .background(.bar)
            }
        }
        .task { await session.evaluateIfNeeded() }
        .onDisappear { sendTask?.cancel() }
    }

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if session.conversation.messages.isEmpty && !session.isSending {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("まずは声をかけてみましょう")
                                .font(.headline)
                            if let opener = Scenario.named(session.conversation.scenarioID)?.opener {
                                Text("たとえば「\(opener)」")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical)
                    }
                    ForEach(session.conversation.sortedMessages) { message in
                        messageBubble(role: message.role, content: message.content)
                    }
                    if let pendingText = session.pendingText {
                        messageBubble(role: .user, content: pendingText)
                        ProgressView("\(session.conversation.characterName)さんが返答中…")
                            .accessibilityIdentifier("waitingForReply")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.conversation.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: session.isSending) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private func messageBubble(role: MessageRole, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(role == .user ? "あなた" : "\(session.conversation.characterName)さん · AI")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(content)
                .textSelection(.enabled)
                .padding(14)
                .background(role == .user ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier(role == .user ? "userMessage" : "assistantMessage")
        }
        .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
    }
}
