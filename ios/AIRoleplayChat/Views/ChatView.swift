import SwiftData
import SwiftUI

struct ChatView: View {
    @State private var session: ChatSession
    @State private var sendTask: Task<Void, Never>?

    init(conversation: Conversation, context: ModelContext) {
        _session = State(initialValue: ChatSession(conversation: conversation, context: context))
    }

    var body: some View {
        @Bindable var session = session
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if session.conversation.messages.isEmpty && !session.isSending {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("まずは声をかけてみましょう")
                                .font(.headline)
                            Text("たとえば「資料の進み具合を教えてもらえる？」")
                                .foregroundStyle(.secondary)
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
        .navigationTitle("\(session.conversation.characterName)さんとの会話")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
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
                    TextField("田中さんに話しかける", text: $session.draft, axis: .vertical)
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
        .onDisappear { sendTask?.cancel() }
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
