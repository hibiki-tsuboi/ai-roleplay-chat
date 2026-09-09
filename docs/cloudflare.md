# Cloudflare 開発環境

自分の iPhone と curl から使う開発用バックエンドです。ユーザー登録・ログインや本番環境はまだありません。

接続先: `https://ai-roleplay-chat-api-dev.hibiki-apps.workers.dev`

2026-09-09 に初回デプロイしました。ヘルスチェック200、認証なしのチャット401、認証あり・不正な入力400を確認済みです。このデプロイ確認では OpenAI を呼び出していません。バックエンドのモックテスト46件、iOS の単体テスト10件、Debug・Release ビルドも成功しています。

## 構成

- Worker: `ai-roleplay-chat-api-dev`（Wrangler の `dev` 環境）。`workers.dev` の HTTPS URL を使います。
- `GET /health` は認証不要です。OpenAI への通信は発生しません。
- `POST /v1/chat` は専用の `DEV_ACCESS_TOKEN` が必要です。未設定なら503、認証失敗なら401で拒否し、OpenAI を呼びません。
- 正常な認証・入力の後に、チャット全体で10回/60秒の制限を適用します。超過すると429です。[Workers Rate Limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/) は Cloudflare 拠点ごとの近似的な制限で、全世界共通の厳密な課金上限ではありません。
- OpenAI API キーと開発用トークンは [Workers Secret](https://developers.cloudflare.com/workers/configuration/secrets/) に保存します。プレビュー URL は無効です。

## 初回デプロイ

`backend/` で実行します。`npx wrangler whoami` でアカウントを確認し、未ログインなら `npx wrangler login` を実行してください。

ローカルの `.dev.vars` にある OpenAI API キーを使い、開発用トークンを生成します。既存の `.dev.vars.dev` は上書きしません。

```bash
node --input-type=module <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { randomBytes } from 'node:crypto';
const key = parseEnv(readFileSync('.dev.vars', 'utf8')).OPENAI_API_KEY;
if (!key?.trim()) throw new Error('OPENAI_API_KEY を .dev.vars に設定してください');
writeFileSync('.dev.vars.dev',
  `OPENAI_API_KEY=${JSON.stringify(key)}\nDEV_ACCESS_TOKEN=${randomBytes(32).toString('hex')}\n`,
  { flag: 'wx', mode: 0o600 });
NODE

npm run check
npm run deploy:dev -- --secrets-file .dev.vars.dev
```

コードと2つの Secret を同時に登録します。`.dev.vars.dev` は Git 管理対象外です。内容をログや共有スキームへ貼り付けないでください。

通常のコード更新は `npm run deploy:dev` だけで反映できます。Secret は保持されます。キーやトークンの変更時だけ `--secrets-file .dev.vars.dev` を付けます。

## curl から確認

現在の接続先でヘルスチェックを実行します。

```bash
API_BASE_URL='https://ai-roleplay-chat-api-dev.hibiki-apps.workers.dev'
curl "$API_BASE_URL/health"
```

実際に会話する場合は、`.dev.vars.dev` の `DEV_ACCESS_TOKEN` を以下の入力待ちで貼り付けます（bash、入力は非表示）。この POST は OpenAI の利用料金が発生します。

```bash
read -r -s -p 'DEV_ACCESS_TOKEN: ' ROLEPLAY_DEV_ACCESS_TOKEN
curl "$API_BASE_URL/v1/chat" \
  -H "Authorization: Bearer $ROLEPLAY_DEV_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"scenarioId":"late-report","messages":[{"role":"user","content":"資料の進み具合を教えてください。"}]}'
unset ROLEPLAY_DEV_ACCESS_TOKEN
```

## iOS から接続

アプリの AI 選択に対応したコードは、現在の Cloudflare にはまだデプロイしていません。最新アプリで使うにはバックエンドの更新が必要です。旧バックエンドは応答に `provider` を返さないため、選択した AI を確認できずアプリ側でエラーになります。Gemini を公開環境で使うには、別途 `GEMINI_MODEL` の設定と `GEMINI_API_KEY` の Secret 登録も必要です。

Xcode の Manage Schemes で `AIRoleplayChat` を複製し、`CloudflareDev` などの名前にして Shared をオフにします。その個人用スキームの Edit Scheme → Run → Arguments → Environment Variables に以下を追加します。トークンを含むスキームは共有・コミットしないでください。

| 名前 | 値 |
| --- | --- |
| `ROLEPLAY_API_BASE_URL` | デプロイ結果の HTTPS URL |
| `ROLEPLAY_DEV_ACCESS_TOKEN` | `.dev.vars.dev` の `DEV_ACCESS_TOKEN` |

これらは Debug の実行時設定です。OpenAI API キーは渡しません。開発用トークンは HTTPS 接続にだけ送信し、Release ビルドにはこの仕組みを含めません。ローカル開発に戻すときは両方の環境変数を無効にします。

## 更新と停止

モデルは `wrangler.jsonc` の `env.dev.vars.OPENAI_MODEL` で指定します。元に戻す場合は `gpt-4.1-mini` に変更して再デプロイします。

公開を止める場合は `env.dev.workers_dev` を `false` に変更し、`npm run deploy:dev` を実行します。`preview_urls` は `false` のままにしてください。一般ユーザーへの配布前には、開発用共有トークンを置き換えるユーザー認証・利用量管理が必要です。
