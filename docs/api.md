# API 契約

iOS と Workers の間は JSON を使用します。ローカル開発時のベース URL は `http://localhost:8787`、公開環境では HTTPS を使用します。バージョン付き API は `/v1` 配下です。

## GET /health

Worker の起動確認です。OpenAI への接続や API キーの有効性は検証しません。

```json
{ "status": "ok" }
```

## POST /v1/chat

`Content-Type: application/json` を指定します。iOS が会話履歴と今回のユーザー発言を古い順に送信し、Worker が AI 部下の返答を1件返します。初期実装は非ストリーミングです。

### リクエスト

```json
{
  "scenarioId": "late-report",
  "messages": [
    { "role": "user", "content": "資料の進み具合を教えてください。" }
  ]
}
```

- `scenarioId`: 現在は `late-report`（提出が遅れている部下）のみ。
- `messages`: 1〜40件。`role` は `user` または `assistant`。最後のメッセージは `user`。
- `content`: 空白のみは不可。1件につき最大4,000 UTF-16コード単位、全件合計24,000単位以内。Swift では `String.utf16.count` で数えます。
- リクエスト本文は最大256 KiB。本文の実バイト数も検証します。
- iOS は今回の発言を追加してから、件数・合計長の上限に収まるまで最古のメッセージを除いて送信してください。端末上の履歴は削除しません。
- モデル名や役割のプロンプトはサーバー側で固定します。クライアントから指定するフィールドはありません。

### 成功レスポンス（200）

```json
{
  "message": {
    "role": "assistant",
    "content": "すみません、集計に時間がかかっています。"
  }
}
```

返答も最大4,000 UTF-16コード単位です。iOS は受信成功後、今回のユーザー発言と AI の返答を1往復として SwiftData に保存します。失敗時は入力を残し、再送でユーザー発言が二重保存されないようにします。画面を閉じると送信中の通信をキャンセルします。未送信の下書きや未完了の往復は永続化しません。

### エラーレスポンス

```json
{
  "error": {
    "code": "not_configured",
    "message": "サーバーの OpenAI 設定が完了していません。"
  }
}
```

| HTTP | code | 意味 |
| --- | --- | --- |
| 400 | `invalid_json` | JSON の解析に失敗 |
| 400 | `invalid_request` | 未知のシナリオ、不正な形式、メッセージ上限超過 |
| 404 | `not_found` | 未知のパス |
| 405 | `method_not_allowed` | HTTP メソッド違い。`Allow` ヘッダーで案内 |
| 413 | `payload_too_large` | 本文が256 KiBを超過 |
| 415 | `unsupported_media_type` | JSON 以外の Content-Type |
| 429 | `rate_limited` | OpenAI 側の利用制限 |
| 502 | `upstream_error` | OpenAI への接続失敗・エラー応答 |
| 502 | `invalid_response` | 空・未完了・長すぎるなど、使用できない AI 応答 |
| 503 | `not_configured` | サーバーの API キーまたはモデル名が未設定 |
| 504 | `upstream_timeout` | OpenAI へのリクエストが30秒でタイムアウト |

レスポンスは `Cache-Control: no-store` を付けます。OpenAI の生のエラー本文や認証情報は返しません。iOS の通信タイムアウトはサーバー側より長い45秒程度を想定します。自動再試行は行わず、失敗時にユーザーが再送します。

## サーバー側の接続

Workers から [OpenAI Responses API](https://developers.openai.com/api/docs/guides/text) を呼び出します。`instructions` にシナリオ、`input` に検証済みメッセージを渡し、`output` 内の `output_text` を取り出します。モデルは `OPENAI_MODEL` で設定し、初期値は `gpt-4.1-mini` です。

`store: false` を指定し、会話 ID や OpenAI 側の会話状態を使わず毎回履歴を渡します。これは API で後から取得するためのレスポンス保存を無効化する設定で、通信先でのあらゆるデータ保持がなくなることを意味しません。[会話状態の公式仕様](https://developers.openai.com/api/docs/guides/conversation-state)
