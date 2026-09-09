import SwiftUI

struct PracticeResultView: View {
    let conversation: Conversation
    let isEvaluating: Bool
    let errorMessage: String?
    let onRetry: () -> Void
    let onRestart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let result = conversation.evaluation {
                    VStack(spacing: 12) {
                        Label("5往復の練習、おつかれさまでした", systemImage: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("今回の上司度")
                            .font(.title3.bold())
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(result.totalScore)")
                                .font(.system(size: 72, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                            Text("/ 100点")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("今回の上司度 \(result.totalScore) / 100点")
                        .accessibilityIdentifier("evaluationScore")
                        Text("今回の会話に対するAIの評価です。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 12)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 20) {
                        Text("4つの視点で振り返る")
                            .font(.headline)
                        ForEach(result.criteria.rows, id: \.title) { row in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(row.title).font(.subheadline.bold())
                                    Spacer()
                                    Text("\(row.assessment.score) / 25")
                                        .font(.subheadline.monospacedDigit())
                                }
                                ProgressView(value: Double(row.assessment.score), total: 25)
                                Text(row.assessment.reason)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    feedback("良かった点", icon: "hand.thumbsup", text: result.goodPoint)
                    feedback("次に試してみよう", icon: "lightbulb", text: result.improvement)
                    feedback("こんな言い方もできます", icon: "quote.bubble", text: result.rephrase)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.bubble")
                            .font(.largeTitle)
                            .foregroundStyle(Color.accentColor)
                        Text("5往復の練習が終了しました")
                            .font(.title3.bold())
                        if isEvaluating {
                            ProgressView("会話を振り返っています…")
                                .accessibilityIdentifier("evaluatingPractice")
                        } else {
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("evaluationError")
                            }
                            Text("会話は保存されています。結果だけを再取得できます。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("結果を再取得", action: onRetry)
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("retryEvaluation")
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }

                if let reply = conversation.sortedMessages.last {
                    feedback("\(conversation.characterName)さんの最後のひと言", icon: "bubble.left", text: reply.content)
                }
                DisclosureGroup("今回の会話を見る") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(conversation.sortedMessages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.role == .user ? "あなた" : "\(conversation.characterName)さん · AI")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(message.content)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 12)
                }
                .accessibilityIdentifier("reviewTranscript")
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            Button("もう一度挑戦", action: onRestart)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("restartPractice")
                .padding()
                .background(.bar)
        }
    }

    private func feedback(_ title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
