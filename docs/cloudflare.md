# Cloudflare 開発環境

自分の iPhone と curl から使う開発用バックエンドです。ユーザー登録・ログインや本番環境はまだありません。

接続先: `https://ai-roleplay-chat-api-dev.hibiki-apps.workers.dev`

2026-09-09 22:41 JST に5往復の練習・採点 API を反映しました。現在のバージョンは `b060487a-c33c-4b25-a3c9-69f3b4cde948` で、トラフィックは100%切り替え済みです。既存の Secret を保持しています。最新版のアプリを更新インストールし、新しい練習を始めてください。

デプロイ後はヘルスチェック200、採点 API の GET は405、チャット・採点の認証なしは401、認証ありの不正な入力・5往復未満の採点は400を確認しました。確認で実際の AI は呼び出していません。

2026-09-09 に初回デプロイしました。ヘルスチェック200、認証なしのチャット401、認証あり・不正な入力400を確認済みです。このデプロイ確認では OpenAI を呼び出していません。バックエンドのモックテスト46件、iOS の単体テスト10件、Debug・Release ビルドも成功しています。

同日20:11 JST に AI 選択対応をバージョン `0df32fa0-7f80-4136-a78e-e8ecbc439022` で反映しました。OpenAI / Gemini の選択に対応し、Gemini の Secret を追加しました。モックテスト86件、型チェック、両環境のビルド、上記のヘルスチェック・認証・入力検証を確認しています。この更新では実際の AI は呼び出していません。

## 構成

- Worker: `ai-roleplay-chat-api-dev`（Wrangler の `dev` 環境）。`workers.dev` の HTTPS URL を使います。
- `GET /health` は認証不要です。AI への通信は発生しません。
- `POST /v1/chat` と `POST /v1/evaluation` は専用の `DEV_ACCESS_TOKEN` が必要です。未設定なら503、認証失敗なら401で拒否し、AI を呼びません。
- `provider` は `openai` / `gemini` を選べます。モデルはそれぞれ `gpt-5.6-luna` / `gemini-3.5-flash-lite`。省略時は OpenAI を使います。
- 正常な認証・入力の後に、チャットと採点を合わせて10回/60秒の制限を適用します。5往復の練習はチャット5回＋採点1回です。超過すると429です。[Workers Rate Limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/) は Cloudflare 拠点ごとの近似的な制限で、全世界共通の厳密な課金上限ではありません。
- OpenAI・Gemini の API キーと開発用トークンは [Workers Secret](https://developers.cloudflare.com/workers/configuration/secrets/) に保存します。プレビュー URL は無効です。

## 初回デプロイ

`backend/` で実行します。`npx wrangler whoami` でアカウントを確認し、未ログインなら `npx wrangler login` を実行してください。

新規環境では、ローカルの `.dev.vars` にある両 AI の API キーを使い、開発用トークンを生成します。既存の `.dev.vars.dev` は上書きしません。

```bash
node --input-type=module <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { randomBytes } from 'node:crypto';
const local = parseEnv(readFileSync('.dev.vars', 'utf8'));
const keys = ['OPENAI_API_KEY', 'GEMINI_API_KEY'].map(name => {
  const value = local[name];
  if (!value?.trim()) throw new Error(name + ' を .dev.vars に設定してください');
  return name + '=' + JSON.stringify(value);
});
writeFileSync('.dev.vars.dev',
  keys.join('\n') + '\nDEV_ACCESS_TOKEN=' + randomBytes(32).toString('hex') + '\n',
  { flag: 'wx', mode: 0o600 });
NODE

npm run check
npm run deploy:dev -- --secrets-file .dev.vars.dev
```

コードと3つの Secret を同時に登録します。`.dev.vars.dev` は Git 管理対象外です。内容をログや共有スキームへ貼り付けないでください。

通常のコード更新は `npm run deploy:dev` だけで反映できます。Secret は保持されます。キーやトークンの変更時だけ `--secrets-file .dev.vars.dev` を付けます。

今回の更新では、既存の OpenAI キーとトークンを保持し、Gemini キーだけを含む一時ファイルから追加登録しました。一時ファイルは削除済みです。ローカルの `.dev.vars.dev` にも Gemini キーを追加しています。

## curl から確認

現在の接続先でヘルスチェックを実行します。

```bash
API_BASE_URL='https://ai-roleplay-chat-api-dev.hibiki-apps.workers.dev'
curl "$API_BASE_URL/health"
```

実際に会話する場合は、`.dev.vars.dev` の `DEV_ACCESS_TOKEN` を以下の入力待ちで貼り付けます（bash、入力は非表示）。この POST は選択した AI の API 利用が発生します。

```bash
read -r -s -p 'DEV_ACCESS_TOKEN: ' ROLEPLAY_DEV_ACCESS_TOKEN
curl "$API_BASE_URL/v1/chat" \
  -H "Authorization: Bearer $ROLEPLAY_DEV_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"scenarioId":"late-report","provider":"gemini","messages":[{"role":"user","content":"資料の進み具合を教えてください。"}]}'
unset ROLEPLAY_DEV_ACCESS_TOKEN
```

OpenAI を試すときは `provider` を `openai` にします。成功応答の `provider` で実際の接続先を確認できます。

## iOS から接続

AI 選択・5往復の練習・採点に対応したバックエンドをデプロイ済みです。以下の接続設定を使い、最新版アプリの会話開始画面で OpenAI / Gemini を選択してください。

Xcode の Manage Schemes で `AIRoleplayChat` を複製し、`CloudflareDev` などの名前にして Shared をオフにします。その個人用スキームの Edit Scheme → Run → Arguments → Environment Variables に以下を追加します。トークンを含むスキームは共有・コミットしないでください。

| 名前 | 値 |
| --- | --- |
| `ROLEPLAY_API_BASE_URL` | デプロイ結果の HTTPS URL |
| `ROLEPLAY_DEV_ACCESS_TOKEN` | `.dev.vars.dev` の `DEV_ACCESS_TOKEN` |

これらは Debug の初回接続設定です。このスキームで一度起動すると、HTTPS の接続先と開発用トークンを端末の Keychain に保存します。その後は Mac を切り離し、iPhone のホーム画面から起動しても同じ接続先を使います。AI の API キーは端末へ渡しません。保存処理・読み出し・開発用トークンの送信は Debug ビルドだけに含めます。

ローカル開発へ戻すときは、起動時に `ROLEPLAY_API_BASE_URL=http://localhost:8787`（Simulator）または Mac の `.local` URL（実機）を指定し、`ROLEPLAY_DEV_ACCESS_TOKEN` を無効にします。明示した URL に保存済みのトークンを流用しません。保存された Cloudflare 設定も消す場合は、上記2つの環境変数を無効にして `ROLEPLAY_CLEAR_DEV_CONNECTION=1` で一度起動し、その後この削除用変数を外してください。

## 更新と停止

モデルは `wrangler.jsonc` の `env.dev.vars.OPENAI_MODEL` と `GEMINI_MODEL` で指定し、変更後に再デプロイします。OpenAI を元のモデルに戻す場合は `gpt-4.1-mini` に変更します。AI の選択だけならアプリから切り替えられ、再デプロイは不要です。

公開を止める場合は `env.dev.workers_dev` を `false` に変更し、`npm run deploy:dev` を実行します。`preview_urls` は `false` のままにしてください。一般ユーザーへの配布前には、開発用共有トークンを置き換えるユーザー認証・利用量管理が必要です。
