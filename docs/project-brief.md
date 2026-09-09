# AI Roleplay Chat - Project Brief

## Overview

ChatGPTを利用した、対話型のiPhoneアプリを開発する。

通常のAIアシスタントではなく、AIが特定の人物・役割を演じ、ユーザーがその相手と会話する「ロールプレイ型チャットアプリ」を想定している。

GitHub repository:

`git@github.com:hibiki-tsuboi/ai-roleplay-chat.git`

正式なアプリ名は未定。  
`ai-roleplay-chat` は開発用の仮名称。

---

## Product Concept

AIが以下のような役割を演じる。

- 部下
- 上司
- メンター
- 後輩
- 顧客・取引先

最初のMVPでは「AI部下との会話」を中心に検討する。

例:

- 仕事が遅れている部下
- ミスを報告してきた部下
- モチベーションが下がっている部下
- 優秀だが態度に問題がある部下

ユーザーは上司としてAI部下と会話する。

将来的には、会話終了後に以下のようなフィードバックを返すことも検討する。

- 指示の明確さ
- コミュニケーション
- 心理的安全性
- 問題解決
- 良かった点
- 改善点

---

## Architecture

Monorepoで管理する。

```text
ai-roleplay-chat/
├── ios/
├── backend/
├── docs/
├── AGENTS.md
└── README.md
```

### iOS

- Swift
- SwiftUI
- SwiftData

チャット履歴は、MVPでは基本的にiPhone端末内へ保存する。

### Backend

Cloudflare Workersを利用する予定。

役割は主にOpenAI APIへの安全なプロキシ。ローカルでは比較用にGemini APIも選択できる。

```text
iPhone App
    ↓ HTTPS
Cloudflare Workers
    ↓
OpenAI API / Gemini API
```

OpenAI・GeminiのAPI KeyをiOSアプリ内には保存しない。

Cloudflare Workers側のSecretとして管理する。ローカルではGit管理外の`backend/.dev.vars`を使う。現在のCloudflare開発環境はOpenAIを使用する。

MVPではバックエンド側に大規模なDBやユーザー管理を持たせない方針。

---

## OpenAI

OpenAI APIを利用してAIとの対話を実現する。

AIには単なるアシスタントとして回答させるのではなく、

「特定の性格・背景・役割を持つ人物」

として会話させる。

例:

```text
あなたはユーザーの部下です。

性格:
- 真面目
- やや自信がない
- 報告が遅れがち

状況:
昨日までに提出する予定だった資料がまだ完成していません。

ユーザーはあなたの上司です。
部下として自然に会話してください。
```

プロンプト設計や会話履歴の管理方式は今後検討する。

---

## MVP

まずは非常に小さく作る。

想定する最低限の機能:

1. シナリオを1つ選択
2. AI部下とのチャット画面を表示
3. ユーザーがメッセージを送信
4. Cloudflare Workers経由でOpenAI APIへ送信
5. AI部下の返答を表示
6. 会話履歴をSwiftDataへ保存

認証・クラウド同期・サブスクリプションなどは後回しにする。

---

## Development Policy

まず動くMVPを作る。

過度な抽象化や将来を見越した複雑な設計は避ける。

以下を優先する。

1. シンプル
2. 読みやすい
3. 小さく実装
4. 動作確認しながら段階的に拡張

正式名称・デザイン・課金モデルなどは、MVP完成後に検討する。
