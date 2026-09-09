# 開発ガイド

## 初期構成の判断

- iOS はユーザーが Xcode で作成したプロジェクトを `ios/` に配置し、SwiftUI でシナリオ・チャット・履歴画面を実装しています。
- Workers は標準の `fetch` と小さなハンドラーで実装します。ルーター、OpenAI SDK、DB、ユーザー管理は追加していません。
- 最初のシナリオ ID は `late-report`。人物・背景・話し方は `backend/src/chat.ts` に置きます。
- API は非ストリーミングです。iOS の SwiftData に `Conversation` と `ChatMessage` を保存し、Workers に保存しません。会話削除時はメッセージも削除します。
- 送信状態・再送処理は `ChatSession`、HTTP 通信と履歴の送信上限は `ChatAPI.swift` にまとめています。API の応答が成功した往復だけを保存します。
- iOS と TypeScript の型生成をつなぐ仕組みは導入せず、[API 契約](api.md) とテストで整合性を確認します。

## バックエンドのコマンド

`backend/` で実行します。Node.js 24 以降を使用し、依存バージョンは `package-lock.json` で固定します。

| コマンド | 内容 |
| --- | --- |
| `npm ci` | lockfile に従って依存をインストール |
| `npm run dev` | `127.0.0.1:8787` で Workers をローカル起動 |
| `npm run types` | Wrangler の設定から実行環境の型を生成 |
| `npm run typecheck` | 型生成と TypeScript の strict チェック |
| `npm test` | Vitest による API テスト。OpenAI への通信はモック |
| `npm run test:watch` | テストを監視モードで実行 |
| `npm run build` | Workers の dry-run ビルド。公開しない |
| `npm run check` | 型チェック・テスト・ビルドを実行 |

Wrangler の生成型・ビルド出力・ローカル状態は Git 管理対象外です。Wrangler はユーザーの設定領域にログを書き、型生成時にもローカルポートを使用します。

Wrangler の間接依存 `miniflare > sharp` は、[修正済みバージョン 0.35.4](https://github.com/advisories/GHSA-rgj7-g3m4-5g8c) に `overrides` で固定しています。Wrangler が修正版を取り込んだ際に解除して、`npm audit` と `npm run check` を確認してください。

### チャット API の手動確認

`.dev.vars.example` を `.dev.vars` にコピーしてキーを設定し、`npm run dev` で起動した後に実行します。実際の OpenAI API 利用が発生します。

```bash
curl http://localhost:8787/v1/chat \
  -H 'Content-Type: application/json' \
  -d '{"scenarioId":"late-report","messages":[{"role":"user","content":"資料の進み具合を教えてください。"}]}'
```

キー未設定なら `503 not_configured` になります。ローカルの `.dev.vars` を Git に追加しないでください。公開環境のキーは [Workers Secret](https://developers.cloudflare.com/workers/configuration/secrets/) で管理します。

### モデルの切り替え

`backend/wrangler.jsonc` の `vars.OPENAI_MODEL` は現在 `gpt-5.6-luna` です。応答品質を比較するための試用で、Luna のみ推論量を `none` に設定しています。

元のモデルに戻す場合は `OPENAI_MODEL` を `gpt-4.1-mini` に変更し、`backend/` の `npm run dev` を再起動してください。Luna 固有の推論設定は自動的に省略されるため、コードの変更は不要です。`.dev.vars` に `OPENAI_MODEL` を追加している場合は、その上書きも変更または削除してください。

自動テストは両モデルのリクエスト形式をモックで検証します。Luna の実際の返答品質は、上記の curl または iOS アプリから手動で確認してください。

## iOS

`ios/AIRoleplayChat.xcodeproj` を Xcode で開き、`AIRoleplayChat` スキームを選びます。プロジェクトの現在の設定は iOS 26.5 以降です。既存の Xcode サンプルデータとは別の `RoleplayChat` ストアに会話を保存します。

リポジトリルートで Simulator 向けにビルドできます。

```bash
xcodebuild -project ios/AIRoleplayChat.xcodeproj \
  -scheme AIRoleplayChat \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ai-roleplay-chat-derived \
  CODE_SIGNING_ALLOWED=NO build
```

### 自動テスト

`AIRoleplayChat` スキームの `⌘U` で Swift Testing の単体テストを実行できます。会話の保存と再読み込み、関連メッセージの削除、送信する履歴の上限、API 応答の検証、失敗後の再送・キャンセルを確認します。通信は `URLProtocol` で置き換え、実際の AI を呼びません。

CLI では、インストール済み Simulator 名を指定して実行します。

```bash
xcodebuild -project ios/AIRoleplayChat.xcodeproj \
  -scheme AIRoleplayChat \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ai-roleplay-chat-derived \
  CODE_SIGNING_ALLOWED=NO test
```

画面操作の XCTest は `AIRoleplayChatUITests` スキームです。まず別ターミナルで以下の HTTP モックを起動します（リポジトリルートで実行）。

```bash
node ios/scripts/mock-chat-server.mjs
```

そのまま `AIRoleplayChatUITests` スキームでテストを実行します。CLI では上の `-scheme` を `AIRoleplayChatUITests` に変更してください。モックは `localhost:8788` で動き、会話の送信・アプリ再起動後の続行・エラーからの再送・履歴削除を検証します。通常利用の履歴とは別のテスト用ストアを使い、スクリーンショットをテスト結果に添付します。

### ローカル接続

Debug の接続先は `Configuration/Debug-Info.plist` の `http://localhost:8787` です。Simulator から Mac 上のバックエンドに接続できます。Xcode の Edit Scheme → Run → Arguments → Environment Variables に `ROLEPLAY_API_BASE_URL` を追加すると、Debug の接続先を上書きできます。API キーはこの設定に入れません。

実機では同じ Wi-Fi 上の Mac の `.local` ホスト名を接続先に指定し、`backend/` で `npx wrangler dev --ip 0.0.0.0 --port 8787` を実行します。Debug 用 Info.plist にはローカル HTTP 接続の ATS 設定とネットワークの利用目的を追加しています。

Release の URL は空欄です。将来公開する際に `Configuration/Release-Info.plist` に HTTPS の接続先を設定してください。Release は開発用の環境変数による上書きや HTTP 接続を使いません。

## コードと変更の確認

インデントは `.editorconfig` に従い、Swift は4スペース、TypeScript・JSON は2スペースです。Swift の型名は `UpperCamelCase`、関数・変数は `lowerCamelCase`、TypeScript のソースファイルは短い英小文字名を使います。専用のリンターやフォーマッターはまだ導入していません。

バックエンドのテストは `backend/test/*.test.ts` に置き、API の成功・入力不正・外部サービス障害を確認します。カバレッジの数値目標は未設定です。

コミットには変更内容を短く記載し、PR には目的・変更点・検証結果を記載してください。画面変更ではスクリーンショット、対応する issue があればそのリンクを添えます。

## MVP の手動確認

1. バックエンドに API キーを設定し、`npm run dev` で起動する。
2. Simulator でアプリを起動し、「会話を始める」から田中さんに話しかける。
3. AI の返答を受信し、2往復以上会話する。
4. アプリを終了して再起動し、履歴から会話を開いて続きを送信する。
5. バックエンド停止中に送信し、入力が残ることを確認する。再起動して再送する。
6. ホームで履歴をスワイプ削除する。

2026-09-09 に iPhone 17 Pro Simulator（iOS 26.5）で、単体テスト8件、モックを使った画面テスト3件、実際の OpenAI と2往復する画面テストを確認しました。実通信ではアプリを再起動して履歴を開き、続きを送信しています。Debug・Release のビルドも確認済みです。

認証は企画書どおり後回しです。現在はローカル開発用として `workers_dev` と `preview_urls` を無効にし、公開ルートを設定していません。外部公開時にはアクセス制御と利用量制限を決めてから公開設定を追加してください。
