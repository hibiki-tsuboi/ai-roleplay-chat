# Project Instructions

Read `docs/project-brief.md` before making architectural or product-level changes.

This repository is a monorepo for an iOS application and its backend.

## Repository

```text
ios/       iOS application
backend/   Backend API
docs/      Product and technical documentation
```

## Development principles

- Keep the MVP simple.
- Avoid unnecessary abstraction.
- Prefer small, incremental changes.
- Do not add infrastructure unless it is currently required.
- Keep iOS and backend API contracts consistent.
- Never put the OpenAI API key or other secrets in the iOS application or repository.
- Update relevant documentation when architectural decisions change.

## iOS

- Swift
- SwiftUI
- SwiftData
- Prefer native Apple frameworks where practical.

## Backend

- Cloudflare Workers
- TypeScript
- Acts initially as a thin API layer between the iOS app and OpenAI API.

## Product context

See `docs/project-brief.md`.