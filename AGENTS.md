# Agentback Swift SDK

This repository owns the public, submission-only Swift Package. Agentback's
service and website live in a separate repository; Pulse is a consumer.

- Swift 6, macOS 12+, iOS 15+. Keep the core independent of UI frameworks.
- Native applications ship only public project keys, never server or identity secrets.
- No automatic log collection, screenshots, uploads, background queues or retries.
- Keep the JSON wire contract aligned with Agentback; native app forms default to `native`; explicit channel overrides remain supported.
- Run `swift test` and compile the iOS simulator target before publishing.
- Never send production test feedback or email without explicit authorization.
- Publish semantic version tags from tested commits. Do not move published tags.
