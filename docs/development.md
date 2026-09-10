# 開発ガイド

## 初期構成の判断

- iOS はユーザーが Xcode で作成したプロジェクトを `ios/` に配置し、SwiftUI でシナリオ・チャット・履歴画面を実装しています。
- Workers は標準の `fetch` と小さなハンドラーで実装します。OpenAI・Gemini への接続と応答の変換は `backend/src/ai.ts` に置きます。ルーター、AI の SDK、DB、ユーザー管理は追加していません。
- 最初のシナリオ ID は `late-report`。人物・背景・話し方は `backend/src/chat.ts` に置きます。
- 新しい練習は5往復で終了します。`backend/src/evaluation.ts` に固定の採点基準・構造化出力スキーマ・検証処理を置き、同じ AI で結果を取得します。
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

`scenarioId` は `backend/src/scenarios.ts` に登録した4種類（`late-report` / `mistake-report` / `low-motivation` / `attitude-issue`）のいずれかで、未知の値は AI を呼ばずに `400 invalid_request` になります。人物設定はサーバーだけが持ち、クライアントは ID しか送りません。

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

Cloudflare の開発環境も OpenAI / Gemini の選択に対応しています。`AI_PROVIDER=openai` は接続先を省略したリクエストの既定値です。ローカルの `.dev.vars` はデプロイ先に自動反映されないため、公開先のモデル・Secret は [Cloudflare 開発環境](cloudflare.md) の手順で管理します。

自動テストは OpenAI・Gemini のリクエスト形式、会話履歴、エラー処理をモックで検証します。API キーを読み込まず、実際の AI を呼びません。返答品質とキーの有効性は、上記の curl または iOS アプリから手動で確認してください。

## iOS

新規会話の AI は最初は Gemini で、以降は前回の選択を `AppStorage` に保存します。各会話には `providerID` を SwiftData で保存し、ホームの選択が変わっても履歴の接続先は変えません。

既存ストアへは任意の `providerID` を追加します。過去の AI は記録されていないため推測せず、次の成功応答で確認した接続先を保存します。アプリは指定した AI と応答の `provider` が一致することを確認し、不一致・未対応の旧バックエンドの応答では履歴を保存せず下書きを残します。

5往復の練習では `Conversation.practiceVersion = 1`、保存した採点 JSON は任意の `evaluationData` に保持します。既存ストアへの追加属性は `nil` を既定値とし、旧履歴は自由形式のまま読み込み・続行できます。新規作成時だけ5往復のルールを使います。「もう一度挑戦」は同じ AI で別の会話を作り、以前の結果を保持します。

5回目の返信を保存してから採点を別途実行します。採点失敗時は結果だけ再取得でき、結果が保存済みなら再起動しても再採点しません。画面を閉じたときは進行中の通信をキャンセルし、再表示時に結果が未取得なら採点から再開します。

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

Keychain の実動作もテストするため、単体テストでは通常のコード署名を有効にします。`CODE_SIGNING_ALLOWED=NO` は付けないでください。

```bash
xcodebuild -project ios/AIRoleplayChat.xcodeproj \
  -scheme AIRoleplayChat \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ai-roleplay-chat-derived \
  test
```

画面操作の XCTest は `AIRoleplayChatUITests` スキームです。まず別ターミナルで以下の HTTP モックを起動します（リポジトリルートで実行）。

```bash
node ios/scripts/mock-chat-server.mjs
```

そのまま `AIRoleplayChatUITests` スキームでテストを実行します。CLI では上の `-scheme` を `AIRoleplayChatUITests` に変更してください。モックは `localhost:8788` で動き、会話の送信・アプリ再起動後の続行・エラーからの再送・履歴削除に加え、5往復終了・結果表示・結果の再取得・再起動後の結果保存・再挑戦を検証します。通常利用の履歴とは別のテスト用ストアを使い、スクリーンショットをテスト結果に添付します。

### ローカル接続

Debug の接続先は `Configuration/Debug-Info.plist` の `http://localhost:8787` です。Simulator から Mac 上のバックエンドに接続できます。Xcode の Edit Scheme → Run → Arguments → Environment Variables に `ROLEPLAY_API_BASE_URL` を追加すると、Debug の接続先を上書きできます。API キーはこの設定に入れません。

Cloudflare 用の HTTPS URL と `ROLEPLAY_DEV_ACCESS_TOKEN` を設定して一度起動すると、両方を端末の Keychain に保存します。ホーム画面から起動した場合も復元します。保存属性は [`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly) で、ロック解除中だけ読み出せ、別端末へ移行しません。起動時に URL を明示した場合は保存済み設定より優先し、別の接続先へ保存済みトークンを送らないようにしています。削除手順は [Cloudflare 開発環境](cloudflare.md#ios-から接続) を参照してください。

実機の `localhost` は iPhone 自身です。Mac のサーバーを使う場合は次の実機向け設定に変更し、Cloudflare を使う場合は初回の接続設定を行ってください。

実機では同じ Wi-Fi 上の Mac の `.local` ホスト名を接続先に指定し、`backend/` で `npx wrangler dev --ip 0.0.0.0 --port 8787` を実行します。Debug 用 Info.plist にはローカル HTTP 接続の ATS 設定とネットワークの利用目的を追加しています。

Release の URL は空欄です。将来公開する際に `Configuration/Release-Info.plist` に HTTPS の接続先を設定してください。Release は開発用の環境変数・Keychain 設定・HTTP 接続を使いません。

## コードと変更の確認

インデントは `.editorconfig` に従い、Swift は4スペース、TypeScript・JSON は2スペースです。Swift の型名は `UpperCamelCase`、関数・変数は `lowerCamelCase`、TypeScript のソースファイルは短い英小文字名を使います。専用のリンターやフォーマッターはまだ導入していません。

バックエンドのテストは `backend/test/*.test.ts` に置き、API の成功・入力不正・外部サービス障害を確認します。カバレッジの数値目標は未設定です。

コミットには変更内容を短く記載し、PR には目的・変更点・検証結果を記載してください。画面変更ではスクリーンショット、対応する issue があればそのリンクを添えます。

## MVP の手動確認

1. バックエンドに API キーを設定し、`npm run dev` で起動する。
2. Simulator でアプリを起動し、シナリオと OpenAI / Gemini を選んで「会話を始める」から相手役に話しかける。
3. 途中でアプリを終了して再起動し、履歴から会話を開いて同じ AI で続きを送信する。
4. 5往復すると入力欄が閉じ、上司度・4項目の点数・良かった点・改善点・言い換え例が出ることを確認する。
5. アプリを再起動して履歴から保存済みの結果を表示する。「もう一度挑戦」で0 / 5往復に戻り、前の結果が残ることを確認する。
6. バックエンド停止中の送信は入力が残ること、採点失敗時は5往復をやり直さず結果だけ再取得できることを確認する。
7. もう一方の AI でも練習し、最後にホームから不要な履歴をスワイプ削除する。
8. シナリオを切り替えて練習し、相手の名前・状況・採点の観点が入れ替わることと、履歴が元のシナリオのまま残ることを確認する。

2026-09-09 に iPhone 17 Pro Simulator（iOS 26.5）で、単体テスト8件、モックを使った画面テスト3件、実際の OpenAI と2往復する画面テストを確認しました。実通信ではアプリを再起動して履歴を開き、続きを送信しています。Debug・Release のビルドも確認済みです。

同日の AI 選択追加では、バックエンド86件、iOS 単体14件、画面操作4件と Release ビルドを確認しました。既存ストアの移行、両 AI の選択、再起動後の履歴継続を検証しています。この変更のテストはすべてモック通信です。画面テストでは履歴と AI の選択設定を専用の保存領域へ分けます。

5往復・採点の追加では、バックエンド137件、iOS 単体28件、画面操作6件、型チェック・両環境の Workers ビルド・iOS Release ビルドを確認しました。6回目の送信防止、採点だけの再取得、結果の永続化、旧形式ストアの移行、再挑戦時の画面初期化を含みます。すべてモック通信で、実際の AI による採点品質は手動確認の対象です。同日22:41 JST に Cloudflare へ反映し、疎通・認証・入力検証も AI を呼ばずに確認しました。

シナリオを4種類に増やした変更では、バックエンド154件、iOS 単体30件、画面操作7件、型チェック・両環境の Workers ビルドを確認しました。ID からシナリオを引く形にし、会話用の人物設定とコーチ用の状況説明を1か所（`backend/src/scenarios.ts`）にまとめています。採点の4項目は据え置き、期限や報告時刻に寄っていた `clarity` と `action` の説明だけを他のシナリオでも成立する表現に直しました。ID と登場人物名は Swift 側（`ios/AIRoleplayChat/Models/Scenario.swift`）と手作業で一致させています。ホーム画面は見出し自体をシナリオ選択メニューにしました。カード内に選択欄を積むと履歴が画面外へ押し出され、既存の画面テスト2件が落ちたためです。自動テストはすべてモック通信です。

同日、ローカル Worker で実際の AI による確認を行いました（Gemini `gemini-3.5-flash-lite`、演じ分けのみ OpenAI `gpt-5.6-luna` でも実施）。同じ問いかけに対し4シナリオが別人として応答し、鈴木は「大丈夫です」とはぐらかしてから少しずつ本音を話し、山本は指摘にまず反論してから代案に同意しました。田中と佐藤は自分から用件を切り出しますが、鈴木と山本は上司が話題を出すまで待つため初手は似た応答になります。アプリはシナリオごとの例文を提示するため導線上は問題ありません。

`low-motivation` と `attitude-issue` で5往復＋採点まで通し、どちらも80/100。`clarity` は期限ではなく「期待する基準」、`action` は「次に状況を確認する機会」を根拠に採点されており、文言の修正が意図どおり効いています。同じシナリオで詰問だけの会話を流すと0/100になり、点数が実際に差を付けることを確認しました。未知の `scenarioId` は AI を呼ばずに400、会話内で満点を要求した記録を採点させても0/100で、注入は通りません。低評価が0点に張り付く件は、固定した5往復のトランスクリプトを保存し、採点だけを繰り返す方法で調べ直しました（会話を都度生成すると変更の効果と会話のばらつきが混ざるため）。同一入力での合計点は、詰問だけの会話が0点（4項目とも0）、聞くだけで次の行動を決めない会話が28点、事情を聞いて具体的な打診と次回の約束まで進めた会話が78〜80点で、いずれも繰り返しても±2程度に収まります。そっけないが敵対的ではない会話は21〜28点と幅が出ます。

0点は敵対的な会話に限って安定して出ており、判定理由も「傾聴せず一方的に詰問している」「支援も次の確認機会も設定していない」と会話の事実に対応しています。「良かった点」も捏造せず、声をかけた事実自体を拾えています。**採点として正しい挙動と判断し、点数の底上げは見送りました。** 0点を「行動がまったくない場合に限る」と補足して1〜5で差をつけさせる案を試しましたが、詰問の会話は0点のままで、他の会話の点数が不安定になったため取り消しています。採点だけ `temperature: 0` にする案も、点数のばらつきが縮まらなかったため取り消しました。

この確認中に、練習の進行指示が返答本文へ漏れる不具合を見つけました（3往復目の返答末尾に「（※残り2往復です。自然なやり取りを続けましょう）」が付いた）。`chatInstructions` に往復数を返答へ書かない旨を追記し、`test/practice.test.ts` で全往復について指示の存在を確認しています。修正後に4シナリオ×2回の中盤返答を採取して漏れ0件でしたが、元の発生頻度が30回に1回程度のため、この件数では解消の証明になりません。

ユーザー登録・ログインは企画書どおり後回しです。Cloudflare では自分用の開発環境として、開発用トークンによるアクセス制御と Rate Limiting を使用します。デプロイと iOS の接続手順は [Cloudflare 開発環境](cloudflare.md) を参照してください。ローカルの既定環境とプレビュー URL は公開しません。
