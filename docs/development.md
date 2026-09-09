# 開発ガイド

## 初期構成の判断

- iOS はユーザーが Xcode で作成したプロジェクトを `ios/` に配置しています。SwiftUI・SwiftData のテンプレートを出発点にします。
- Workers は標準の `fetch` と小さなハンドラーで実装します。ルーター、OpenAI SDK、DB、ユーザー管理は追加していません。
- 最初のシナリオ ID は `late-report`。人物・背景・話し方は `backend/src/chat.ts` に置きます。
- API は非ストリーミングです。履歴の永続化は iOS 側で実装し、Workers に保存しません。
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

## iOS

`ios/AIRoleplayChat.xcodeproj` を Xcode で開きます。プロジェクトの現在の設定は iOS 26.5 以降です。SwiftData のサンプル `Item` を置き換え、会話・メッセージの保存モデルを実装するところから始めます。

リポジトリルートで Simulator 向けにビルドできます。

```bash
xcodebuild -project ios/AIRoleplayChat.xcodeproj \
  -scheme AIRoleplayChat \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ai-roleplay-chat-derived \
  CODE_SIGNING_ALLOWED=NO build
```

iOS のテストターゲットはまだありません。チャットの保存・履歴の切り詰め・通信エラーからの再送を実装する際に、対応するテストを追加してください。

API 接続時は Simulator から `http://localhost:8787` を使用できます。実機からは同じ Wi-Fi 上の Mac のホスト名を指定し、Workers を `npx wrangler dev --ip 0.0.0.0 --port 8787` で起動します。HTTP 用の ATS 設定やローカルネットワークの利用目的は iOS の開発用設定として追加し、公開環境の接続先は HTTPS にしてください。

## コードと変更の確認

インデントは `.editorconfig` に従い、Swift は4スペース、TypeScript・JSON は2スペースです。Swift の型名は `UpperCamelCase`、関数・変数は `lowerCamelCase`、TypeScript のソースファイルは短い英小文字名を使います。専用のリンターやフォーマッターはまだ導入していません。

バックエンドのテストは `backend/test/*.test.ts` に置き、API の成功・入力不正・外部サービス障害を確認します。カバレッジの数値目標は未設定です。

初期リポジトリにはコミット履歴や PR テンプレートがありません。コミットには変更内容を短く記載し、PR には目的・変更点・検証結果を記載してください。画面変更ではスクリーンショット、対応する issue があればそのリンクを添えます。

## 次の実装

1. iOS にシナリオ選択とチャット画面を作成する。
2. [API 契約](api.md) に沿って送信・受信・エラー表示を実装する。
3. SwiftData に会話とメッセージを保存し、再起動後の履歴表示を確認する。
4. API キーをローカル設定し、iOS → Workers → OpenAI の実通信を確認する。

認証は企画書どおり後回しです。現在はローカル開発用として `workers_dev` と `preview_urls` を無効にし、公開ルートを設定していません。外部公開時にはアクセス制御と利用量制限を決めてから公開設定を追加してください。
