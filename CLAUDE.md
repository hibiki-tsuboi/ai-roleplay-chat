# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

「AIロープレ」 — an iPhone app where an AI plays a subordinate (`田中`) and the user practices managing them, plus a thin Cloudflare Workers proxy in front of OpenAI/Gemini. Monorepo: `ios/`, `backend/`, `docs/`.

```text
iPhone (SwiftUI + SwiftData)  ──HTTPS──▶  Worker: GET /health, POST /v1/chat  ──▶  OpenAI Responses API
history + provider per conversation       auth → validate → rate limit → prompt     Gemini Interactions API
```

Deliberately absent from the MVP: backend database, accounts, sync, streaming, purchases. Don't add them — or new dependencies and abstraction layers — unless the change at hand actually requires it (`AGENTS.md`).

Read `AGENTS.md` and `docs/project-brief.md` before architectural or product-level changes. `docs/api.md` is the authoritative wire contract, `docs/development.md` holds commands plus past decisions and manual-verification logs, `docs/cloudflare.md` covers the deployed dev Worker. These docs are expected to be updated when behavior changes; README and `docs/` are written in Japanese.

## Commands

### Backend (`cd backend`, Node ≥ 24)

- `npm ci` — install from the lockfile
- `npm run dev` — Worker on `127.0.0.1:8787`. For a physical iPhone on the same Wi-Fi: `npx wrangler dev --ip 0.0.0.0 --port 8787`
- `npm test`, `npm run test:watch` — Vitest. Single test: `npx vitest run test/gemini.test.ts -t "works with only Gemini credentials"`
- `npm run typecheck` — runs `wrangler types` first. `worker-configuration.d.ts` is generated and gitignored, so run this (or `npm run types`) after a fresh clone or any `wrangler.jsonc` binding change, or `tsc` fails on missing types
- `npm run check` — typecheck + tests + dry-run builds of both environments. The gate before deploying or calling a change done
- `npm run deploy:dev` — deploy `ai-roleplay-chat-api-dev`. Append `-- --secrets-file .dev.vars.dev` only when rotating secrets; plain deploys keep them

Keys: `cp .dev.vars.example .dev.vars`, fill `OPENAI_API_KEY` / `GEMINI_API_KEY`, then restart `npm run dev`. `.dev.vars*` (except `.example`) is gitignored — never commit, print, or paste its contents.

### iOS (`ios/AIRoleplayChat.xcodeproj`, iOS 26.5+)

Build check — signing not required:

```bash
xcodebuild -project ios/AIRoleplayChat.xcodeproj -scheme AIRoleplayChat \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ai-roleplay-chat-derived CODE_SIGNING_ALLOWED=NO build
```

Unit tests (Swift Testing) — must run **signed**, and name an installed simulator:

```bash
xcodebuild -project ios/AIRoleplayChat.xcodeproj -scheme AIRoleplayChat \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ai-roleplay-chat-derived test
```

- Adding `CODE_SIGNING_ALLOWED=NO` to a test run breaks `DevelopmentConnectionTests` with `-34018` (`errSecMissingEntitlement`): an unsigned app has no keychain access group. Every unit test passes when signed
- Single test: add `-only-testing:'AIRoleplayChatTests/ChatTests/deletingConversationAlsoDeletesMessages()'`. The trailing `()` is required for Swift Testing — without it xcodebuild silently runs 0 tests and still prints `TEST SUCCEEDED`. XCTest cases in `AIRoleplayChatUITests` take no parentheses. Read the `Test run with N tests` summary line rather than trusting the exit status
- UI tests (XCTest): start the fixture first — `node ios/scripts/mock-chat-server.mjs` (port 8788) — then run with `-scheme AIRoleplayChatUITests`
- The project uses file-system-synchronized groups: a new Swift file under `ios/AIRoleplayChat/` needs no `project.pbxproj` edit

No automated test touches a real AI: backend tests stub global `fetch`, iOS unit tests swap in a `URLProtocol`, UI tests hit the local mock. Keep it that way and verify real replies by hand (curl or the app, per `docs/development.md`).

## Architecture

### The API contract is kept in sync by hand

There is no codegen between Swift and TypeScript. The same limits exist twice — `backend/src/chat.ts` (`scenarioID`, `maxMessages`, `maxMessageLength`, `maxTotalLength`) and `ios/AIRoleplayChat/Networking/ChatAPI.swift` (`ChatRequest.max*`) — counted in UTF-16 code units on both sides (`content.length` in TS, `text.utf16.count` in Swift) so they agree exactly. A wire-format change means editing the Worker, `ChatAPI.swift`, `docs/api.md`, and tests on both sides. iOS trims the oldest messages to fit the limits before sending, and never trims the stored history.

### The Worker's order of checks is a tested invariant

`backend/src/index.ts` runs one fixed sequence: route → method → dev auth (skipped only when `APP_ENV=local`) → `Content-Type` → 256 KiB body cap (streamed, actual bytes, not just `Content-Length`) → JSON parse → `parseChatRequest` → `resolveAIConfig` → rate limiter → upstream call. Auth and validation deliberately precede the rate limiter and any AI call, and `/health` requires no token and never reaches an AI. Tests assert that invalid input consumes no quota and that failures make no upstream request, so keep new checks in the same position.

### Provider choice belongs to the conversation and is verified

iOS picks OpenAI or Gemini before starting a conversation (`@AppStorage("preferredAIProvider")`, remembering the last choice), stores it on `Conversation.providerID`, and sends it on every turn. A reply whose `provider` doesn't match the request is rejected (`ChatAPIError.providerMismatch`) and nothing is saved. Conversations created before this feature have `providerID == nil`: they send no provider and adopt whatever the first successful reply reports, rather than guessing. Server-side, `resolveAIConfig` returns `null` → `503 not_configured` instead of silently falling back to the other vendor. Clients choose only a provider; model names, API keys, and the persona prompt (`scenarioInstructions`) stay on the server.

### One adapter holds both vendors' differences

`backend/src/ai.ts` is the only file that knows vendor shapes: OpenAI Responses API (`instructions`/`input`, reads `output_text`) versus Gemini Interactions API (`system_instruction`, `user_input`/`model_output` steps, `x-goog-api-key`). Both send `store: false`, cap output at 800 tokens, and use a 30 s `AbortSignal.timeout` (iOS waits 45 s, never auto-retries). Reasoning settings are keyed on the *model name* — `gpt-5.6-luna` → `reasoning.effort: "none"`, `gemini-3.5-flash-lite` → `thinking_level: "minimal"` — so switching models is a `wrangler.jsonc`/`.dev.vars` change with no code edit. `extractReply` accepts only `status: "completed"` and takes text from assistant/model output items, so reasoning summaries never enter the chat.

### Only completed round-trips are persisted

`ChatSession.send()` is the single writer: it parks the in-flight text in `pendingText`, appends the user message and reply together through `Conversation.appendTurn` after the response is validated, `rollback()`s the context if the save fails, and clears the draft only on success. Failed or cancelled sends keep the draft so a resend cannot duplicate a turn; leaving the chat screen cancels the task. Drafts and unfinished turns are never stored. Message order comes from an explicit `position` (`sortedMessages`), not from SwiftData relationship order; deleting a conversation cascades to its messages.

### SwiftData store setup

`AIRoleplayChatApp` opens a named `RoleplayChat.store` in Application Support with CloudKit disabled, keeping it separate from the Xcode template's sample store, and surfaces a retry UI if the container fails to open. New model properties must be optional or defaulted so existing stores still open — `providerID` is a `String?` rather than the enum for that reason, and `AIRoleplayChatTests/StoreMigrationTests.swift` guards it. UI tests get a throwaway store and `UserDefaults` suite via the `ROLEPLAY_TEST_STORE` launch environment variable.

### Secrets, and Debug-only connection config

The app never holds an AI key. A Release build reads only `APIBaseURL` from `Configuration/Release-Info.plist` and refuses anything but HTTPS. Everything else lives inside `#if DEBUG`: the `ROLEPLAY_API_BASE_URL` / `ROLEPLAY_DEV_ACCESS_TOKEN` overrides, the Keychain-backed `DevelopmentConnection` store, and the `Authorization: Bearer` header itself, which is only ever sent over HTTPS. Debug defaults to `http://localhost:8787` (`Configuration/Debug-Info.plist`, which also carries the local-networking ATS entry).

The Keychain store exists so an on-device Debug build keeps reaching the Cloudflare dev Worker after it is unplugged from Xcode: a launch carrying both env vars saves the pair (`AIRoleplayChatApp.init` → `captureLaunchConfiguration`) and later launches restore it. The rules around it are deliberate and covered by `DevelopmentConnectionTests` — an explicit `ROLEPLAY_API_BASE_URL` never borrows the saved token for a different server, only an HTTPS address with no user, password, query, or fragment can be persisted, `ROLEPLAY_CLEAR_DEV_CONNECTION=1` wipes it, and a UI-test launch (`ROLEPLAY_TEST_STORE` set) neither reads nor writes it. Setup procedure: `docs/cloudflare.md`.

### Two Wrangler environments that do not inherit

`backend/wrangler.jsonc` has a top-level config for local `wrangler dev` (`APP_ENV=local`, no auth, no rate limiter, `workers_dev: false`) and `env.dev` for the deployed Worker (`APP_ENV=development`, required secrets `OPENAI_API_KEY`/`GEMINI_API_KEY`/`DEV_ACCESS_TOKEN`, `CHAT_RATE_LIMITER` at 10 requests/60 s, `workers_dev: true`, `preview_urls: false`). Wrangler does not inherit `vars` into named environments, so a model or flag change has to be made in both blocks.

## Conventions

- `.editorconfig` governs formatting: 4-space Swift, 2-space TypeScript/JSON, LF, final newline. No linter or formatter is configured — match the surrounding code.
- Commits: a gitmoji prefix plus a short Japanese summary (`✨ 会話ごとにOpenAIとGeminiを選択できるようにする`). PRs state purpose, changes, and verification; screenshots for UI changes.
- User-facing strings, docs, and commit messages are Japanese; identifiers and comments are English, and comments are sparse — they explain a constraint instead of restating the code.
- Backend tests live in `backend/test/*.test.ts` and drive the Worker through `worker.fetch(request, env)` with an inline `Env` object — no Workers test pool or Miniflare setup.
