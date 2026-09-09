# AI Roleplay Chat

AI が部下などの役割を演じる、会話練習用の iPhone アプリです。最初の MVP は「提出が遅れている部下との会話」を扱います。正式名称は未定です。

## 構成

```text
ios/
  AIRoleplayChat.xcodeproj/  Xcode プロジェクト
  AIRoleplayChat/            SwiftUI・SwiftData アプリ、Assets.xcassets
backend/
  src/                      Cloudflare Workers API（TypeScript）
  test/                     API のテスト（Vitest）
docs/
  project-brief.md           企画・MVP の範囲
  api.md                    iOS とバックエンドの API 契約
  development.md            開発手順・初期構成の判断
```

## 現在の状態

- iOS は Xcode で作成した SwiftUI・SwiftData の初期テンプレートです。チャット画面と API 接続はこれから実装します。
- バックエンドには `GET /health` と `POST /v1/chat`、シナリオのプロンプト、入力検証、エラー処理を用意しています。
- 会話履歴は今後 iPhone 内に保存します。バックエンド DB・認証・同期・課金は未実装です。

## バックエンドの起動

Node.js 24 以降と npm を使用します。

```bash
cd backend
npm ci
cp .dev.vars.example .dev.vars
# .dev.vars の OPENAI_API_KEY に自分のキーを設定
npm run dev
```

別ターミナルで確認します。ヘルスチェックは API キーなしでも動作します。

```bash
curl http://localhost:8787/health
```

検証は `backend/` で `npm run check` を実行します。型チェック、テスト、デプロイを伴わないビルドを順番に行います。実際の AI 応答確認には API キーが必要です。

## iOS の起動

Xcode で `ios/AIRoleplayChat.xcodeproj` を開き、`AIRoleplayChat` スキームと iPhone Simulator を選んで実行します。現在のプロジェクトの対象 OS は iOS 26.5 以降です。実機では Signing & Capabilities の Team を各自の環境に合わせてください。

## 開発方針

変更前に [AGENTS.md](AGENTS.md) と [企画書](docs/project-brief.md) を確認してください。API の変更時は [API 契約](docs/api.md) と iOS 側を揃えます。OpenAI API キーはバックエンドのローカル `.dev.vars`、公開環境では Workers Secret で管理します。

初期構成はローカル開発用です。公開時のアクセス制御と利用量制限は別途設計します。詳しい手順は [開発ガイド](docs/development.md) を参照してください。
