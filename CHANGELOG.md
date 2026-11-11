# Changelog

## 0.2.0

- Native app forms now default to `source: native`, separate from web, MCP and CLI feedback.
- Explicit `direct`, `mcp`, `cli` and `web` sources remain supported.
- No operating-system detection or platform field is added.
- Requires a service that accepts `native`; self-hosted installations must upgrade first or pass `.direct`.

## 0.1.0

Initial public release of the submission-only Agentback Swift SDK.

- Async text feedback submission for macOS 12+ and iOS 15+, using Swift 6.
- Public project keys, categories, product versions and optional signed accounts.
- Optional structured agent feedback and MCP/CLI source fields.
- Field and request-size validation, typed HTTP/network errors and cancellation.
- No automatic retries, diagnostic collection, UI or attachment uploads.
