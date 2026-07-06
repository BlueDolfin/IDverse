# IDVerse iOS SDK

Native **iOS SDK that integrates [IDVerse](https://idverse.com) identity
verification** into your app, plus a sample app.

[![iOS](https://img.shields.io/badge/iOS-15.0+-blue.svg)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org/)
[![SPM](https://img.shields.io/badge/SwiftPM-supported-success.svg)](https://swift.org/package-manager/)
![Version](https://img.shields.io/badge/version-0.1.0-informational.svg)

## What this is (read first)

**IDVerse has no native mobile SDK.** Its identity-verification journey
(consent → document capture → OCR → confirm details → liveness → complete) is a
**hosted web flow** served by IDVerse. This SDK therefore presents that flow in
an embedded `WKWebView` and wraps it with a clean native API.

Document capture, OCR, liveness/anti-spoof, and fraud checks **all run inside
IDVerse's web flow on IDVerse's servers** — there is no native capture or
liveness here, by design. So the value is **not** that the SDK makes IDVerse
native; it makes the web integration **safe, predictable, monitored, and hard to
misuse**: the webview correctness, permission bridge, security defaults,
lifecycle handling, transaction-lifecycle orchestration, and PII-safe
observability that production mobile integration needs around that webview. (For
the full "why use this instead of a hand-rolled WebView", see the
[iOS Integration Guide](ios-sdk/Documentation/INTEGRATION_GUIDE.md).)

## How it works

```
Your app            Your backend                 IDVerse
────────            ────────────                 ───────
start  ───────────► Store Transaction  ─────────► creates transaction
       ◄─────────── transaction URL
present URL in a webview (this SDK)  ────────────► user completes the web journey
       ◄─────────── exit redirect (flow done)
done   ───────────► Get Results / webhook ◄─────── final outcome (authoritative)
```

The integrator's **backend** holds the IDVerse API secret and calls Store
Transaction / Get Results. **The app never holds IDVerse credentials.** The SDK
presents the transaction URL, detects completion via a redirect, and returns a
typed result; the authoritative outcome arrives via the backend webhook (an
in-app `.pending` result is valid and means "reconcile via the webhook").

## Repository structure

```
ios-sdk/        Swift Package (IDVerseSDK, iOS 15+, no deps) + Documentation/ + Examples/IDVerseApp
```

The SDK is self-contained: its code, its `Documentation/` (Integration +
Developer guides), and its example app all live under `ios-sdk/`.

## Quick start (iOS)

**SwiftUI — full lifecycle (returns the real result):**
```swift
import SwiftUI
import IDVerseSDK

IDVerseVerificationFlow(
    config: TransactionConfig(redirectURL: URL(string: "idverse-sdk://complete")!),
    service: service,                 // your IDVerseTransactionService (backend-proxy)
    onFinish: { result in /* Result<IDVerseVerificationResult, IDVerseError> */ }
)
```

**UIKit — async facade:**
```swift
let result = try await IDVerse.runVerification(
    TransactionConfig(redirectURL: URL(string: "idverse-sdk://complete")!),
    using: service,
    from: self)                        // a UIViewController
// result.outcome: .passed / .failed / .refer / .pending
```

Every entry point also takes an optional, defaulted `configuration:`
(`IDVerseConfiguration`) for observability, retry policy, and timeouts. See the
[iOS Integration Guide](ios-sdk/Documentation/INTEGRATION_GUIDE.md) for the full
API and backend wiring.

## Features

**Presentation & lifecycle**
- Full-screen webview host with native chrome (loader, close, error/timeout)
- Camera/mic **permission bridge** + IDVerse-correct WebView config (inline media, JS, Chrome UA)
- Main-frame-only **completion detection** via a custom-scheme redirect
- Transaction-lifecycle **orchestration** (create → present → fetch) behind one API
- One stable API across **SwiftUI + UIKit**

**Resilience** *(observability + resilience slice)*
- Transient-error **retry** with exponential backoff + jitter (`IDVerseRetryPolicy`)
- **Result polling** on `.pending` up to a configurable timeout
- **Idempotency keys** on transaction creation
- **WebView content-process recovery** + backgrounding-safe load watchdog
- `Task` and SwiftUI-teardown **cancellation**, configurable timeouts

**Security & privacy**
- **No IDVerse secrets in the app** — transactions come from your backend
- **Fail-closed** camera/mic origin allow-list; **non-persistent** web storage
- **PII-safe observability** — events/logs carry only ids/outcomes/categories/counters, by construction

**Developer experience**
- `MockTransactionService` + an example app to validate before production credentials
- Foundation logic fully unit-tested (`swift test`, 43 tests); iOS UI build-verified

## Documentation

| Document | For whom |
|----------|----------|
| **iOS** — [Integration Guide](ios-sdk/Documentation/INTEGRATION_GUIDE.md) | App developers: get the iOS SDK into your app, why use it (vs DIY), full API reference, backend wiring, security |
| **iOS** — [Developer Guide](ios-sdk/Documentation/DEVELOPER_GUIDE.md) | SDK maintainers: architecture, file-by-file code walkthrough, conventions, testing, roadmap |
| **iOS** — [Example app](ios-sdk/Examples/IDVerseApp/README.md) | Running the iOS example app |

## Requirements

- **iOS** 15.0+, Xcode 14+, Swift 5.7+, **Swift Package Manager only** (no CocoaPods), no third-party dependencies.
- A backend that can call IDVerse Store Transaction / Get Results — the IDVerse API secret lives on your server, never in the app.

## Testing

```bash
cd ios-sdk && swift test                 # Foundation logic (macOS host, no simulator)
```

### Full end-to-end testing needs an IDVerse staging environment

`MockTransactionService` and the example app exercise the SDK's native side
without any credentials — but the verification journey itself (document
capture, OCR, liveness, results) runs on IDVerse's hosted flow. To test the
app end-to-end you need access to an **IDVerse staging environment**: a
staging tenant whose credentials let your backend create transactions and
whose transaction URLs serve the web journey.

**Contact [IDVerse](https://idverse.com) to arrange staging access** for your
organisation. Once you have it, create a transaction via your backend (or
paste a staging transaction URL into the example app) and run the flow on a
**real device** — camera and liveness do not work in the iOS simulator.

## Status

Implemented (`v0.1.0`). The presentation, orchestration, observability, and
resilience are complete and tested. The **transaction API is stubbed**:
`RemoteTransactionService` throws `notImplemented` until you wire it to your
backend (no live IDVerse credentials/contract yet). Run the full flow locally
against `MockTransactionService`, or paste a real transaction URL into the
example app.

This is a **pre-1.0** project — see the iOS Developer Guide's
[Further development](ios-sdk/Documentation/DEVELOPER_GUIDE.md) section for the
path to production (real backend integration, privacy manifest, CI, distribution).

## License

Licensed under the [Apache License 2.0](LICENSE).

The IDVerse product documentation in `Manuals/`, the hosted-flow screenshots in
`Screenshots/`, and the IDVerse name/branding are the property of IDVerse and
are **not** covered by this license — see [NOTICE](NOTICE).
