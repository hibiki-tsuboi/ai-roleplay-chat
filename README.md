# AI Roleplay Chat

AI が部下などの役割を演じる、会話練習用の iPhone アプリです。最初の MVP は「提出が遅れている部下との会話」を扱います。正式名称は未定です。

## 構成

```text
ios/
  AIRoleplayChat.xcodeproj/  Xcode プロジェクト
  AIRoleplayChat/            SwiftUI・SwiftData アプリ、Assets.xcassets
  AIRoleplayChatTests/       保存・API 契約・再送のテスト
  AIRoleplayChatUITests/     Simulator での画面操作テスト
  Configuration/            開発用・Release 用の接続設定
backend/
  src/                      Cloudflare Workers API（TypeScript）
  test/                     API のテスト（Vitest）
docs/
  project-brief.md           企画・MVP の範囲
  api.md                    iOS とバックエンドの API 契約
  development.md            開発手順・初期構成の判断
```

## 現在の状態

- iOS にはシナリオからの会話開始、メッセージ送受信、送信中表示、失敗時の再送、会話履歴の再表示・削除を実装しています。
- 新しい練習は5往復で終了し、「今回の上司度」を100点満点で表示します。4項目の内訳、良かった点、改善点、言い換え例を保存し、履歴から再表示・再挑戦できます。採点失敗時は結果だけを再取得できます。
- バックエンドには `GET /health`、`POST /v1/chat`、`POST /v1/evaluation`、シナリオ・採点のプロンプト、入力検証、エラー処理を用意しています。
- 会話を始める画面で OpenAI / Gemini を選び、履歴から再開するときも同じ AI を使えます。ローカル・Cloudflare 開発環境の両方に対応し、Gemini は `gemini-3.5-flash-lite` を使用します。
- Cloudflare の開発用バックエンドはデプロイ済みです。開発用トークンと連続送信の制限を設けています。接続・デプロイ手順は [Cloudflare 開発環境](docs/cloudflare.md) を参照してください。
- 会話履歴は SwiftData で iPhone 内に保存します。バックエンド DB・認証・同期・課金は未実装です。

## バックエンドの起動

Node.js 24 以降と npm を使用します。

```bash
cd backend
npm ci
cp .dev.vars.example .dev.vars
# .dev.vars の OPENAI_API_KEY に自分のキーを設定
npm run dev
```

アプリで両方の AI を使う場合は `.dev.vars` に `OPENAI_API_KEY`、`GEMINI_API_KEY`、`GEMINI_MODEL=gemini-3.5-flash-lite` を設定して再起動します。アプリでの選択を優先し、`AI_PROVIDER` は接続先を省略したリクエストの既定値として使います。手順は [開発ガイド](docs/development.md#モデルの切り替え) を参照してください。

別ターミナルで確認します。ヘルスチェックは API キーなしでも動作します。

```bash
curl http://localhost:8787/health
```

検証は `backend/` で `npm run check` を実行します。型チェック、テスト、デプロイを伴わないビルドを順番に行います。実際の AI 応答確認には API キーが必要です。

## iOS の起動

Xcode で `ios/AIRoleplayChat.xcodeproj` を開き、`AIRoleplayChat` スキームと iPhone Simulator を選んで実行します。現在のプロジェクトの対象 OS は iOS 26.5 以降です。実機では Signing & Capabilities の Team を各自の環境に合わせてください。

Debug ビルドの接続先は `http://localhost:8787` です。Mac 上でバックエンドを起動したまま、アプリで「会話する AI」を選び、「会話を始める」を押します。5往復すると同じ AI による結果が表示されます。新しい練習・採点 API に対応したバックエンドが必要です。Cloudflare の更新状況は [開発環境](docs/cloudflare.md) を参照してください。

実機で Cloudflare を使う場合は、[開発用の接続設定](docs/cloudflare.md#ios-から接続) を一度設定して起動してください。接続先と開発用トークンを端末の Keychain に保存し、ホーム画面からの起動時にも復元します。

`AIRoleplayChat` スキームで `⌘U` を押すと、保存・通信・再送の単体テストを実行します。テストは実際の AI に接続しません。画面操作テストや実機接続の手順は [開発ガイド](docs/development.md) に記載しています。

## 開発方針

変更前に [AGENTS.md](AGENTS.md) と [企画書](docs/project-brief.md) を確認してください。API の変更時は [API 契約](docs/api.md) と iOS 側を揃えます。OpenAI・Gemini の API キーはバックエンドのローカル `.dev.vars`、公開環境では Workers Secret で管理します。

現在はローカルと Cloudflare の個人開発用です。一般公開に向けたユーザー認証と利用量管理は別途設計します。詳しい手順は [開発ガイド](docs/development.md) を参照してください。
