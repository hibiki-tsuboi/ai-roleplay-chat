import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var path: [Conversation] = []
    @State private var errorMessage: String?
    @AppStorage("preferredAIProvider") private var selectedProvider: AIProvider = .gemini

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("あなたは上司役です", systemImage: "person.2.bubble")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(Scenario.lateReport.title)
                            .font(.title2.bold())
                        Text(Scenario.lateReport.summary)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("会話する AI")
                                .font(.subheadline.weight(.medium))
                            Picker("会話する AI", selection: $selectedProvider) {
                                ForEach(AIProvider.allCases) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("aiProviderPicker")
                        }
                        Button("会話を始める", action: startConversation)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityIdentifier("startConversation")
                    }
                    .padding(.vertical, 12)
                } header: {
                    Text("シナリオ")
                } footer: {
                    Text("AI が演じる架空の部下との会話練習です。選んだ AI は、この会話の続きでも使います。")
                }

                Section("会話履歴") {
                    if conversations.isEmpty {
                        Text("会話を始めると、ここから続きを話せます。")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .accessibilityIdentifier("emptyHistory")
                    }
                    ForEach(conversations) { conversation in
                        NavigationLink(value: conversation) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(conversation.title)
                                    .font(.headline)
                                Text(conversation.sortedMessages.last?.content ?? "まだメッセージはありません")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    if let provider = conversation.provider {
                                        Text(provider.displayName)
                                            .fontWeight(.medium)
                                    }
                                    Text(conversation.updatedAt, format: .dateTime.month().day().hour().minute())
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("conversationRow")
                    }
                    .onDelete(perform: deleteConversations)
                }
            }
            .navigationTitle("ロールプレイ")
            .toolbar {
                if !conversations.isEmpty { EditButton() }
            }
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(conversation: conversation, context: modelContext)
            }
            .alert("履歴を更新できませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func startConversation() {
        let conversation = Conversation(provider: selectedProvider)
        modelContext.insert(conversation)
        do {
            try modelContext.save()
            path.append(conversation)
        } catch {
            modelContext.rollback()
            errorMessage = "端末の空き容量などを確認して、もう一度お試しください。"
        }
    }

    private func deleteConversations(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(conversations[index]) }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "会話を削除できませんでした。もう一度お試しください。"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Conversation.self, ChatMessage.self], inMemory: true)
}
