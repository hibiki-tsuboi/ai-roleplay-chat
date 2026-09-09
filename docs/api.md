# API 契約

iOS と Workers の間は JSON を使用します。ローカル開発時のベース URL は `http://localhost:8787`、公開環境では HTTPS を使用します。バージョン付き API は `/v1` 配下です。

## GET /health

Worker の起動確認です。AI への接続や API キーの有効性は検証しません。

```json
{ "status": "ok" }
```

## POST /v1/chat

`Content-Type: application/json` を指定します。iOS が会話履歴と今回のユーザー発言を古い順に送信し、Worker が AI 部下の返答を1件返します。初期実装は非ストリーミングです。

Cloudflare の開発環境では `Authorization: Bearer <DEV_ACCESS_TOKEN>` も必要です。これは開発用バックエンドにアクセスするためのトークンで、OpenAI・Gemini の API キーとは別です。ローカル環境（`APP_ENV=local`）では不要です。設定手順は [Cloudflare 開発環境](cloudflare.md) を参照してください。

### リクエスト

```json
{
  "scenarioId": "late-report",
  "provider": "gemini",
  "practice": "five-turns",
  "messages": [
    { "role": "user", "content": "資料の進み具合を教えてください。" }
  ]
}
```

- `scenarioId`: 現在は `late-report`（提出が遅れている部下）のみ。
- `provider`: 任意。`openai` または `gemini`。省略時はサーバーの `AI_PROVIDER` を使用。`null`・空文字・未知の値は400。
- `practice`: 新規練習では `five-turns` を指定。未知の値・`null` は400。省略時は旧アプリ・既存履歴向けの自由形式の会話。
- `messages`: 練習では1・3・5・7・9件。最初は `user`、以降 `assistant` と交互で、最後は `user`。10件以上・6往復目は400。
- `content`: 空白のみは不可。1件につき最大4,000 UTF-16コード単位。練習では最大40,000単位まで受け付け、履歴を省略しません。Swift では `String.utf16.count` で数えます。
- リクエスト本文は最大256 KiB。本文の実バイト数も検証します。
- 自由形式のみ従来の1〜40件・合計24,000単位を適用し、今回の発言を追加してから上限に収まるまで最古のメッセージを除いて送信します。端末上の履歴は削除しません。
- モデル名・接続先 URL・役割のプロンプトはサーバー側で固定します。クライアントは `provider` で許可された AI だけを選べます。

### 成功レスポンス（200）

```json
{
  "provider": "gemini",
  "practice": "five-turns",
  "message": {
    "role": "assistant",
    "content": "すみません、集計に時間がかかっています。"
  }
}
```

返答も最大4,000 UTF-16コード単位です。iOS は受信成功後、今回のユーザー発言と AI の返答を1往復として SwiftData に保存します。失敗時は入力を残し、再送でユーザー発言が二重保存されないようにします。画面を閉じると送信中の通信をキャンセルします。未送信の下書きや未完了の往復は永続化しません。

応答の `provider` は実際に呼び出した AI です。iOS は会話に保存した接続先を毎回送信し、応答が一致することを確認します。指定済みなのに応答の `provider` が異なる・欠けている場合は保存しません。AI が未記録の既存履歴は接続先を省略して送信し、成功応答の `provider` を次回以降のために保存します。

練習の応答には `practice: "five-turns"` を返し、iOS は対応を確認します。サーバーが受信履歴から往復数を計算し、5回目には質問で引き延ばさず会話を締めるよう指示します。iOS は5回目の返信を保存したら入力欄を閉じ、採点 API を呼びます。

## POST /v1/evaluation

会話と同じ認証・Content-Type を使います。`scenarioId: "late-report"`、`practice: "five-turns"`、会話で使用した `provider`（必須）、`messages` を送ります。メッセージは古い順に **ちょうど10件**（5往復）、`user` / `assistant` が交互で、最後は `assistant`。1件4,000・合計40,000 UTF-16コード単位以内です。途中の会話や切り詰めた履歴は採点しません。

### 成功レスポンス（200）

```json
{
  "provider": "gemini",
  "evaluation": {
    "totalScore": 78,
    "criteria": {
      "listening": { "score": 20, "reason": "遅れの原因を確認できました。" },
      "consideration": { "score": 21, "reason": "責めずに話を聞けました。" },
      "clarity": { "score": 19, "reason": "次に進める作業を伝えました。" },
      "action": { "score": 18, "reason": "次の報告時刻も確認しましょう。" }
    },
    "goodPoint": "解決策を伝える前に事情を聞けました。",
    "improvement": "次の報告時刻を一緒に決めましょう。",
    "rephrase": "では、今日15時に進み具合を教えてもらえる？"
  }
}
```

4項目の `score` は0〜25の整数。`totalScore` はサーバーが合計します。`reason` は空白のみ不可・最大300、残り3つの文章は各500 UTF-16コード単位以内です。型・範囲・必須項目を検証し、不正なら502を返します。iOS も項目、合計、応答の AI を検証し、結果を1度保存したら再表示に API を呼びません。

採点に失敗しても5往復は保存済みです。結果だけを手動で再取得でき、再起動時も未取得の結果から再開します。5回目の会話を再送したり、6回目へ進んだりしません。新しい練習はチャット5回＋採点1回の AI 呼び出しです。採点も同じ開発環境の10回/60秒枠を消費します。

Workers は状態を持たず、送られた履歴の形式・件数を検証します。履歴の真正性や採点の重複をサーバーで管理しません。失敗・中断後の再取得では AI の再呼び出しが発生し、点数が変わる場合があります。

## 共通エラーレスポンス

```json
{
  "error": {
    "code": "not_configured",
    "message": "指定された AI を利用できません。サーバーの AI 設定を確認してください。"
  }
}
```

| HTTP | code | 意味 |
| --- | --- | --- |
| 400 | `invalid_json` | JSON の解析に失敗 |
| 400 | `invalid_request` | 未知のシナリオ、不正な形式、メッセージ上限超過 |
| 401 | `unauthorized` | 開発用アクセストークンが未指定または不正 |
| 404 | `not_found` | 未知のパス |
| 405 | `method_not_allowed` | HTTP メソッド違い。`Allow` ヘッダーで案内 |
| 413 | `payload_too_large` | 本文が256 KiBを超過 |
| 415 | `unsupported_media_type` | JSON 以外の Content-Type |
| 429 | `rate_limited` | 開発環境または AI 側の利用制限。開発環境側では `Retry-After: 60` |
| 502 | `upstream_error` | AI への接続失敗・エラー応答 |
| 502 | `invalid_response` | 空・未完了・長すぎるなど、使用できない AI 応答 |
| 503 | `not_configured` | AI の接続先・API キー・モデル名・開発環境のアクセス設定が不足 |
| 503 | `rate_limit_unavailable` | 開発環境の利用制限を確認できず、AI 呼び出しを中止 |
| 504 | `upstream_timeout` | AI へのリクエストが30秒でタイムアウト |

レスポンスは `Cache-Control: no-store` を付けます。AI の生のエラー本文や認証情報は返しません。iOS の通信タイムアウトはサーバー側より長い45秒程度を想定します。自動再試行は行わず、失敗時にユーザーが再送します。

## サーバー側の接続

リクエストの `provider` を優先し、省略時は `AI_PROVIDER`（`openai` または `gemini`、未設定時は `openai`）で接続先を選びます。選択した接続先の設定が不正なら `503 not_configured` を返し、他社への自動切り替えは行いません。認証・利用制限はどちらの AI にも共通です。

採点では `backend/src/evaluation.ts` のコーチ用指示と固定スキーマを使い、会話全体を評価対象の JSON データとして渡します。OpenAI は [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs) の `text.format`、Gemini は [Interactions の構造化出力](https://ai.google.dev/gemini-api/docs/interactions-breaking-changes-may-2026?hl=en#structured-output-json) の `response_format: { type: "text", mime_type: "application/json", schema: ... }` を指定します。採点の出力上限は2,000トークン、会話は800トークン。モデル・推論設定・30秒タイムアウト・`store: false` は共通です。

### OpenAI

Workers から [OpenAI Responses API](https://developers.openai.com/api/docs/guides/text) を呼び出します。`instructions` にシナリオ、`input` に検証済みメッセージを渡し、`output` 内の `output_text` を取り出します。モデルは `OPENAI_MODEL` で設定し、現在は `gpt-5.6-luna` を試用します。

短い会話の応答時間と出力上限800トークンに合わせ、Luna の場合だけ `reasoning: { effort: "none" }` を指定します（[Luna の公式仕様](https://developers.openai.com/api/docs/models/gpt-5.6-luna)）。`gpt-4.1-mini` に戻す場合はこのパラメーターを送信しません。切り替え手順は [開発ガイド](development.md#モデルの切り替え) を参照してください。

`store: false` を指定し、会話 ID や OpenAI 側の会話状態を使わず毎回履歴を渡します。これは API で後から取得するためのレスポンス保存を無効化する設定で、通信先でのあらゆるデータ保持がなくなることを意味しません。[会話状態の公式仕様](https://developers.openai.com/api/docs/guides/conversation-state)

### Gemini

[Gemini Interactions API](https://ai.google.dev/api/interactions-api) の `POST /v1beta/interactions` を使用し、`GEMINI_API_KEY` を `x-goog-api-key` ヘッダーに設定します。ローカル・Cloudflare 開発環境のモデルは `GEMINI_MODEL=gemini-3.5-flash-lite` です。

`system_instruction` にシナリオを設定し、履歴を `input` の `user_input` / `model_output` ステップへ変換します。`store: false` を指定し、毎回履歴を送信します。これは後から取得するための保存を無効にする設定です（[データ保持の仕様](https://ai.google.dev/gemini-api/docs/interactions-overview#data-retention)）。

出力上限は800トークン、3.5 Flash-Lite の [推論量](https://ai.google.dev/gemini-api/docs/thinking) は `minimal`、推論サマリーは `none` にします。`status: completed` の応答から、`steps` 内の `model_output.content` の `text` だけを返します。思考・未完了の応答は会話本文に使用しません。
