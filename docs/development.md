# 開発ガイド

## 初期構成の判断

- iOS はユーザーが Xcode で作成したプロジェクトを `ios/` に配置し、SwiftUI でシナリオ・チャット・履歴画面を実装しています。
- Workers は標準の `fetch` と小さなハンドラーで実装します。OpenAI・Gemini への接続と応答の変換は `backend/src/ai.ts` に置きます。ルーター、AI の SDK、DB、ユーザー管理は追加していません。
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
| `npm test` | Vitest による API テスト。OpenAI・Gemini への通信はモック |
| `npm run test:watch` | テストを監視モードで実行 |
| `npm run build` | Workers の dry-run ビルド。公開しない |
| `npm run build:dev` | Cloudflare 開発環境の dry-run ビルド。公開しない |
| `npm run deploy:dev` | Cloudflare の `ai-roleplay-chat-api-dev` にデプロイ |
| `npm run check` | 型チェック・テスト・両環境の dry-run ビルドを実行 |

Wrangler の生成型・ビルド出力・ローカル状態は Git 管理対象外です。Wrangler はユーザーの設定領域にログを書き、型生成時にもローカルポートを使用します。

Wrangler の間接依存 `miniflare > sharp` は、[修正済みバージョン 0.35.4](https://github.com/advisories/GHSA-rgj7-g3m4-5g8c) に `overrides` で固定しています。Wrangler が修正版を取り込んだ際に解除して、`npm audit` と `npm run check` を確認してください。

### チャット API の手動確認

初回は `.dev.vars.example` を `.dev.vars` にコピーし、使用する AI のキーを設定します。既存の `.dev.vars` があれば直接編集してください。`npm run dev` で起動した後に次を実行すると、選択した AI の API 利用が発生します。

```bash
curl http://localhost:8787/v1/chat \
  -H 'Content-Type: application/json' \
  -d '{"scenarioId":"late-report","messages":[{"role":"user","content":"資料の進み具合を教えてください。"}]}'
```

キー未設定なら `503 not_configured` になります。ローカルの `.dev.vars` を Git に追加しないでください。公開環境のキーは [Workers Secret](https://developers.cloudflare.com/workers/configuration/secrets/) で管理します。

### モデルの切り替え

アプリの「会話する AI」で OpenAI / Gemini を選択します。両方を使うには、既存の `OPENAI_API_KEY` を残したまま `.dev.vars` に次を設定してください。モデル名とキーはバックエンドだけで管理します。

```dotenv
GEMINI_API_KEY=取得したキー
GEMINI_MODEL=gemini-3.5-flash-lite
```

設定後は `npm run dev` を再起動します。アプリから選ぶたびに再起動する必要はありません。選んだ AI の設定が不足している場合は503を返し、他社の AI へ自動で切り替えません。

curl でも JSON に `"provider":"gemini"` または `"provider":"openai"` を追加して選べます。省略時だけ `.dev.vars` の `AI_PROVIDER`（既定は `openai`）を使用します。

[Gemini 3.5 Flash-Lite](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite) は短い会話の試用向けに選択しています。このモデルのみ推論量を `minimal` に設定します。アプリで OpenAI を試すときは、ホームで OpenAI を選んで新しい会話を始めてください。

`backend/wrangler.jsonc` の `vars.OPENAI_MODEL` は現在 `gpt-5.6-luna` です。応答品質を比較するための試用で、Luna のみ推論量を `none` に設定しています。

元のモデルに戻す場合は `OPENAI_MODEL` を `gpt-4.1-mini` に変更し、`backend/` の `npm run dev` を再起動してください。Luna 固有の推論設定は自動的に省略されるため、コードの変更は不要です。`.dev.vars` に `OPENAI_MODEL` を追加している場合は、その上書きも変更または削除してください。

Cloudflare 上のモデルは `env.dev.vars.OPENAI_MODEL` で指定します。変更後に `npm run deploy:dev` で反映します。Wrangler の環境ごとの変数は継承されないため、ローカルと別に変更してください。

Cloudflare の開発環境は引き続き `AI_PROVIDER=openai` です。ローカルの `.dev.vars` はデプロイ先に反映されません。Gemini のキー登録・デプロイは今回のローカル設定には含みません。

自動テストは OpenAI・Gemini のリクエスト形式、会話履歴、エラー処理をモックで検証します。API キーを読み込まず、実際の AI を呼びません。返答品質とキーの有効性は、上記の curl または iOS アプリから手動で確認してください。

## iOS

新規会話の AI は最初は Gemini で、以降は前回の選択を `AppStorage` に保存します。各会話には `providerID` を SwiftData で保存し、ホームの選択が変わっても履歴の接続先は変えません。

既存ストアへは任意の `providerID` を追加します。過去の AI は記録されていないため推測せず、次の成功応答で確認した接続先を保存します。アプリは指定した AI と応答の `provider` が一致することを確認し、不一致・未対応の旧バックエンドの応答では履歴を保存せず下書きを残します。

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
2. Simulator でアプリを起動し、OpenAI / Gemini を選んで「会話を始める」から田中さんに話しかける。
3. AI の返答を受信し、2往復以上会話する。
4. アプリを終了して再起動し、履歴から会話を開いて続きを送信する。
5. バックエンド停止中に送信し、入力が残ることを確認する。再起動して再送する。
6. ホームで履歴をスワイプ削除する。
7. もう一方の AI で会話を始め、元の履歴からは以前の AI で続けられることを確認する。

2026-09-09 に iPhone 17 Pro Simulator（iOS 26.5）で、単体テスト8件、モックを使った画面テスト3件、実際の OpenAI と2往復する画面テストを確認しました。実通信ではアプリを再起動して履歴を開き、続きを送信しています。Debug・Release のビルドも確認済みです。

同日の AI 選択追加では、バックエンド86件、iOS 単体14件、画面操作4件と Release ビルドを確認しました。既存ストアの移行、両 AI の選択、再起動後の履歴継続を検証しています。この変更のテストはすべてモック通信です。画面テストでは履歴と AI の選択設定を専用の保存領域へ分けます。

ユーザー登録・ログインは企画書どおり後回しです。Cloudflare では自分用の開発環境として、開発用トークンによるアクセス制御と Rate Limiting を使用します。デプロイと iOS の接続手順は [Cloudflare 開発環境](cloudflare.md) を参照してください。ローカルの既定環境とプレビュー URL は公開しません。
