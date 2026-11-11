# Agentback for Swift

A dependency-free, submission-only Swift Package for macOS 12+ and iOS 15+,
using Swift 6 and Foundation. Pulse Mac is its first integration. Native reports
use the existing `direct` source and require no server migration.

## Install

In Xcode, choose **File → Add Package Dependencies**, enter:

```text
https://github.com/superagents-lab/agentback-swift.git
```

Choose **Up to Next Major Version** starting at **0.1.0**, then add the `Agentback`
product to your app target. With a `Package.swift` manifest:

```swift
// Package dependencies:
.package(url: "https://github.com/superagents-lab/agentback-swift.git", from: "0.1.0")
// Target dependencies:
.product(name: "Agentback", package: "agentback-swift")
```

For local development, clone this repository and add its directory as a local
Swift package. There is no UI dependency: use your application's existing form.

## Submit from an existing form

```swift
import Foundation
import Agentback

let client = try Agentback(projectKey: "af_..." /* your real public project key */)
let receipt = try await client.send(.init(
    message: "The watchlist did not refresh.",
    category: .bug,
    version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
))
// Show success only after send returns. receipt.id identifies the report.
```

The package provides transport, not a SwiftUI view: keep your app's existing
feedback entry point, language and styling. Disable duplicate submission while
sending, preserve the draft on failure, and expose an alternative contact method.
The client has a 20-second request timeout and does not queue or retry on its own.
A network error can mean the report was stored but its response was lost.

Only the report fields you explicitly pass are sent. The SDK collects no device
identifiers, logs, email addresses or diagnostics, and uses an ephemeral URLSession
by default. Native apps ship only the public `af_` key (64 hexadecimal characters
after the prefix); secret keys and identity secrets are rejected.

Optional fields include `outcome`, `intent`, `expected`, `actual`, `suggestion`,
`tool`, `requestID`, `agent`, and `identity`. For local MCP servers or CLIs, set
`source: .mcp` or `.cli`; native user feedback defaults to `.direct`. The SDK
validates trimmed text against the service's UTF-16 limits and 64 KiB body limit.
There is no support for server-only context or status changes.

## Verified accounts

Only attach an opaque account ID with its backend-issued signature:

```swift
let identity = Agentback.Identity(account: accountID, signature: backendSignature)
let report = Agentback.Report(message: message, identity: identity)
```

Compute the HMAC-SHA256 signature on your backend using the project's identity
secret. Never ship that secret or calculate signatures inside the app. Without a
backend, leave reports anonymous.

## Failures and testing

`AgentbackError` distinguishes invalid configuration, invalid fields, network
errors, invalid success responses and HTTP errors. `.http(status:retryAfter:)`
includes a numeric Retry-After header in seconds when present. `retryable` is true
for network errors, HTTP 429 and 5xx; cancellation remains `CancellationError`.
Do not print report bodies or credentials in error logs.

A custom `origin` supports HTTPS and loopback HTTP development servers, and a
custom `URLSession` supports app-specific networking and tests. Origins must have
no path, credentials, query or fragment. For local end-to-end checks, use a local
Agentback project and the preview mail sink, never a production test recipient.

```sh
swift test
```

The tests use an injected transport and never send feedback or email.

## Scope of 0.1.0

This release submits text feedback. It does not upload log files, screenshots or
other attachments, and it does not include a default feedback UI. Native apps
should not embed server-only keys or silently collect diagnostics.

## License

MIT. See [LICENSE](LICENSE).
