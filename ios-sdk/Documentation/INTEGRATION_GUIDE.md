# IDVerse iOS SDK — Integration Guide

How to integrate `IDVerseSDK` into your iOS app. The SDK presents IDVerse's
hosted identity-verification journey inside a `WKWebView` and hands you a typed
result. This guide covers everything from installation to production security.

For the internal design and code walkthrough, see `DEVELOPER_GUIDE.md` in this
folder.

---

## Why use this SDK instead of a hand-rolled WebView

**It is a native API for IDVerse — not a native verification engine.** Integrators
write Swift: `IDVerse.runVerification(...)`, typed models, typed errors,
SwiftUI/UIKit entry points (the Android SDK mirrors this in Kotlin). The
`WKWebView` is an implementation detail the API hides. What is _native_ is the
integration surface and everything around the webview — container, permissions,
lifecycle, security, results. The verification journey itself — capture, OCR,
liveness, anti-spoof, fraud — runs in IDVerse's **hosted web flow on IDVerse's
servers**; there is no native capture, because IDVerse ships no native engine. So
the real choice is never "native SDK vs WebView" — it is **a hardened, productized
native container vs a raw `WKWebView` you build and maintain yourself.**

An integrator _can_ build this themselves — call the backend for a transaction
URL, load it in a `WKWebView`, catch the redirect, fetch the result. The minimal
happy path is a few dozen lines. The SDK's value is that production mobile
integration is **not** "just a WebView": it packages the platform-specific
correctness, privacy defaults, lifecycle handling, and observability that
enterprises need around that WebView — the sharp edges where teams quietly lose
weeks or ship fragile flows.

| Sharp edge | What goes wrong if you DIY | Where the SDK handles it |
|---|---|---|
| **WKWebView setup for IDVerse** (inline media, JS, Chrome-iOS UA, getUserMedia) | Wrong config → camera silently never works | `WebViewConfigurationFactory`, `IDVerseWebViewController` |
| **Camera/mic permission bridge** (native `AVCaptureDevice` + `WKUIDelegate requestMediaCapturePermissionFor`) | Miss the bridge → in-webview camera is dead with no error | `IDVerseWebViewController` |
| **Main-frame-only redirect detection** | A sub-frame URL spoofs "done", or you miss real completion | `IDVerseRedirectMatcher` + `decidePolicyFor` |
| **Resume-exactly-once / double-completion guards** | Double-resume crashes the continuation; lost callbacks hang the flow | `OneShotCompletion` + controller `didFinish` |
| **Cancellation** (Task cancel + SwiftUI teardown) | Orphaned webviews, leaked continuations | `withTaskCancellationHandler`, `dismantleUIViewController`, `cancelFromOutside` |
| **Backgrounding + load watchdog** | Watchdog fires while suspended, or a spinner-forever on a dead URL | Backgrounding-aware watchdog in `IDVerseWebViewController` |
| **WebView content-process termination** | Blank screen with no recovery when WebKit's renderer is jettisoned | Reload-once recovery in `webViewWebContentProcessDidTerminate` |
| **Security defaults** (no secrets in-app, fail-closed origin allow-list, non-persistent web storage, PII-safe telemetry) | Secrets leak into the binary; the webview gets camera access for arbitrary origins; cookie/cache residue; document data in logs | The service seam, `MediaOriginAllowList`, non-persistent data store, `IDVerseEvent`/`IDVerseEventEmitter` |
| **Result semantics** (redirect is a completion *signal*, not the result; polling can return `.pending`; webhook is authoritative) | Teams treat the in-app result as final and make irreversible decisions on `.pending` | Orchestrator polling + the `.pending`/webhook contract |
| **Operational visibility** (events for start/load/retry/pending/complete/cancel/fail, without leaking document data) | Field issues are unsupportable guesswork | The observability layer (`IDVerseEvent`, `IDVerseObservability`, `IDVerseEventEmitter`) |
| **One stable API across SwiftUI + UIKit** | N divergent in-house implementations across an app fleet | The facade + SwiftUI wrappers |
| **Test app + mocks** | No way to validate integration before production credentials exist | `MockTransactionService`, injectable `sleep`/`now`, the example app |

Beyond the table:

- **Single maintenance surface for iOS/WebKit churn.** WebKit and iOS keep
  changing — permission APIs, process-termination behaviour, deprecations. The
  SDK centralises that so each integrator app doesn't carry the burden. One place
  to fix when the platform shifts.
- **Secret hygiene is a structural guardrail, not just a default.** The
  transaction-service seam + the `RemoteTransactionService` proxy pattern makes
  it _hard_ to put an IDVerse secret in the app. The architecture resists the
  mistake; it isn't merely discouraged in a comment.
- **A typed failure taxonomy for support/triage.** `IDVerseError` +
  `IDVerseFailureCategory` + the event stream give support teams a shared
  vocabulary ("we see `webContentProcessTerminated` then `failed:
  webContentLoadFailed`") instead of guessing from screenshots.
- **Compliance-assertable telemetry.** Because PII safety is enforced by the
  event type's shape (ids/enums/counters only), a privacy/compliance reviewer can
  assert "the SDK's telemetry cannot carry document data" — a property, not a
  promise.
- **Time-to-integrate / risk.** The real cost saved isn't the few dozen lines of
  the happy path — it's the weeks _not_ spent discovering these edges in
  production, on real devices, with real users mid-verification.

IDVerse's hosted flow is web-based, but production mobile integration is not
"just a WebView." The SDK's value is not that it makes IDVerse native — it makes
the web integration **safe, predictable, monitored, and hard to misuse**.

### "But isn't this just an enhanced WebView?"

Correct — and that is by design, not a shortcut. Because IDVerse's flow is
web-based and there is no native engine to call, **a webview is the only possible
shape** — yours, ours, or a hand-rolled one. The objection smuggles in a false
alternative (a "real" native SDK) that does not exist. This is the same pattern as
**Stripe, Auth0/Okta, and Plaid** mobile SDKs, which all wrap a hosted web flow
(payment sheets, OAuth/PKCE, bank auth) — nobody calls those low-value, because
the value was never the rendering surface; it is the correctness, security, and
lifecycle the SDK owns around it. "Just a WebView" undersells it the way "a
browser is just an HTML renderer" does: the _enhancements_ — the permission
bridge, completion interception, security defaults, lifecycle handling, and
PII-safe observability above — **are** the product. The honest boundary stays the
same: this is a **native API for IDVerse, not native verification**.

---

## How it works

IDVerse has no native mobile SDK. Their verification journey (consent → document
capture → OCR → confirm details → liveness → complete) is a **hosted web flow**
served by IDVerse's servers. The SDK runs that journey inside a full-screen
`WKWebView` with a clean native Swift API.

```
Your app            Your backend                 IDVerse
────────            ────────────                 ───────
start  ───────────► Store Transaction  ─────────► creates transaction
       ◄─────────── transaction URL
present URL in WKWebView (this SDK)  ───────────► user completes the web journey
       ◄─────────── exit redirect (flow done)
done   ───────────► Get Results / webhook ◄─────── final outcome (authoritative)
```

Your app's only job is: **ask your backend for a transaction, present it, report
completion.** The SDK does the presenting and completion-detection; your backend
owns the credentials and the authoritative result.

**Key points:**

- All capture, OCR, and liveness happen inside IDVerse's web flow — nothing is
  captured natively.
- Completion is detected when the web flow navigates to a custom-scheme redirect
  URL (e.g. `idverse-sdk://complete`). The SDK intercepts this inside the
  webview; you do **not** need to register the scheme in `Info.plist`.
- The authoritative outcome arrives via IDVerse's **webhook** to your backend. The
  in-app result should be treated as a signal, not a final decision (see
  [Handle the result](#step-5--handle-the-result-and-the-redirect-contract)).
- **API keys and client secrets must never be embedded in the app.** Always proxy
  IDVerse through your own backend.

---

## Prerequisites

- **iOS 15+**, Xcode 14+, Swift 5.7+.
- An **IDVerse account** and a **backend** that can call IDVerse's *Store
  Transaction* and *Get Results* APIs. The IDVerse API secret lives on your
  server, never in the app.
- No third-party dependencies.

---

## Step 1 — Add the package

Swift Package Manager only (no CocoaPods).

### Local package (current working method)

In Xcode: **File → Add Package Dependencies → Add Local** → select the
`ios-sdk/` directory → add the **`IDVerseSDK`** library to your app target.

### Remote package (once tagged releases are published)

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/idverse-ios-sdk.git", from: "1.0.0")
],
targets: [
    .target(name: "App", dependencies: ["IDVerseSDK"])
]
```

No tagged releases exist yet; `.package(path:)` is the primary form during
development.

---

## Step 2 — Permissions

The web journey uses the camera (document + selfie) and microphone (liveness
video). Add usage strings to your target (Xcode Info tab, or `Info.plist`
directly):

```xml
<key>NSCameraUsageDescription</key>
<string>Used to capture your ID and a liveness selfie to verify your identity.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Used to capture a short liveness video to verify your identity.</string>
```

The SDK pre-flights both permissions before loading the flow. A denial (or a
missing usage string, which makes the OS deny automatically) surfaces as an
immediate `cameraPermissionDenied` or `microphonePermissionDenied` error when
the flow starts.

---

## Step 3 — Provide a transaction service

The SDK gets transactions through the `IDVerseTransactionService` protocol.
**Implement one that calls your backend** (your backend proxies IDVerse, keeping
the secret server-side):

```swift
import IDVerseSDK

final class BackendTransactionService: IDVerseTransactionService {
    let baseURL: URL                       // your backend
    init(baseURL: URL) { self.baseURL = baseURL }

    func createTransaction(_ config: TransactionConfig) async throws -> IDVerseTransaction {
        // POST {baseURL}/idverse/transactions
        // → your backend calls IDVerse Store Transaction
        // (set the exit_redirect_url to the SDK's redirect scheme, see Step 5)
        var req = URLRequest(url: baseURL.appendingPathComponent("idverse/transactions"))
        req.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Response: Decodable { let id: String; let url: URL; let redirectURL: URL }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return IDVerseTransaction(id: r.id, url: r.url, redirectURL: r.redirectURL)
    }

    func fetchResult(transactionId: String) async throws -> IDVerseVerificationResult {
        // GET {baseURL}/idverse/transactions/{id}/result
        // → your backend calls IDVerse Get Results
        let url = baseURL.appendingPathComponent("idverse/transactions/\(transactionId)/result")
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Response: Decodable { let outcome: String; let extractedData: [String: String]? }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return IDVerseVerificationResult(
            transactionId: transactionId,
            outcome: IDVerseVerificationResult.Outcome(rawValue: r.outcome) ?? .pending,
            extractedData: r.extractedData)
    }
}
```

The SDK also ships `RemoteTransactionService(backendBaseURL:)` as a scaffold for
this exact pattern — its body is a `TODO` until your backend contract is
finalised. For local development with no backend, use `MockTransactionService`
(see [Local development](#step-6--local-development-without-a-backend) below).

> **`DirectTransactionService`** (calls IDVerse sandbox directly with a hardcoded
> key) lives in the example app only and must never ship in production. Keeping it
> out of `Source/` is load-bearing for the "no secrets in the SDK" guarantee.

---

## Step 4 — Present the verification flow

All entry points accept an optional `configuration:` parameter. **Every parameter
is defaulted**, so existing call sites keep compiling unchanged — you only provide
`configuration:` when you want to change behaviour or attach observability.

### SwiftUI — full lifecycle

Presents the flow and returns the real `IDVerseVerificationResult`:

```swift
import SwiftUI
import IDVerseSDK

struct VerifyView: View {
    let service: IDVerseTransactionService
    @State private var present = false
    @State private var result: IDVerseVerificationResult?

    var body: some View {
        Button("Verify identity") { present = true }
            .fullScreenCover(isPresented: $present) {
                IDVerseVerificationFlow(
                    config: TransactionConfig(redirectURL: URL(string: "idverse-sdk://complete")!),
                    service: service
                    // configuration: .default   // optional — see Observability below
                ) { outcome in
                    present = false
                    if case .success(let r) = outcome { result = r }
                }
                .ignoresSafeArea()
            }
    }
}
```

### SwiftUI — lean (you already have a transaction URL)

Returns `IDVerseStatus` (`.completed`/`.cancelled`) rather than the full result:

```swift
IDVerseVerificationView(
    request: IDVerseVerificationRequest(
        transactionURL: transactionURL,
        redirectURL: URL(string: "idverse-sdk://complete")!
    ),
    // configuration: .default   // optional
    onFinish: { status in
        // status is .completed or .cancelled
    }
)
```

### UIKit — full lifecycle

`async` facade callable from any view controller:

```swift
let result = try await IDVerse.runVerification(
    TransactionConfig(redirectURL: URL(string: "idverse-sdk://complete")!),
    using: service,
    from: self            // self is a UIViewController
    // configuration: .default is implicit; pass it to customise
)
```

### UIKit — lean

```swift
let status = try await IDVerse.verify(
    IDVerseVerificationRequest(
        transactionURL: url,
        redirectURL: URL(string: "idverse-sdk://complete")!
    ),
    from: self
    // configuration: .default is implicit
)
```

---

## Step 5 — Handle the result, and the redirect contract

```swift
switch result.outcome {
case .passed:  // proceed
case .failed:  // reject
case .refer:   // manual review required
case .pending: // NOT final — wait for your backend's webhook (see below)
}

result.extractedData   // [String: String]? — e.g. full_name, document_number
result.checks          // [IDVerseCheck]?   — each check has a name + pass/fail
```

**Redirect URL contract:**

Completion is detected when the web flow navigates to the `redirectURL` you pass
in (a custom scheme, e.g. `idverse-sdk://complete`). This URL must match the
`exit_redirect_url` your backend set on the transaction when calling Store
Transaction. You do **not** need to register the scheme in `Info.plist` — the SDK
intercepts the navigation inside the webview before it leaves the app.

**`.pending` is not final:**

The SDK polls `fetchResult` after the redirect and retries until the outcome
resolves or `resultPollingTimeout` elapses (default 60 s). If polling times out,
the SDK returns a result with outcome `.pending` — it does **not** throw. The
**authoritative** outcome always arrives via the **webhook to your backend**. Gate
any irreversible decisions on the webhook, not on the in-app result.

---

## Step 6 — Local development without a backend

Use `MockTransactionService` to exercise the full app flow with canned data:

```swift
let mock = MockTransactionService(
    transaction: IDVerseTransaction(
        id: "tx_demo",
        url: URL(string: "https://<a-real-transaction-url>")!,
        redirectURL: URL(string: "idverse-sdk://complete")!),
    result: IDVerseVerificationResult(
        transactionId: "tx_demo",
        outcome: .passed,
        extractedData: ["full_name": "Jane Demo"]))
```

The example app (`ios-sdk/Examples/IDVerseApp`) demonstrates both paths: paste a
real transaction URL to drive the live journey, or tap "Preview result screen
(mock)" to see the result UI with no webview. Note that a placeholder `url` won't
load a real flow — the webview will time out after ~30 s with a clear error.

---

## Observability (optional)

Pass an `IDVerseConfiguration` with an event handler to receive a stream of
PII-safe `IDVerseEvent`s for every verification run:

```swift
let config = IDVerseConfiguration(
    observability: .events { event in
        // event.name  — a stable, PII-free string key (safe as an analytics event name)
        // event.transactionId — the IDVerse transaction id, if known at that point
        analytics.log(event.name, ["txId": event.transactionId ?? "-"])
    }
    // webViewLoadTimeout, resultPollingTimeout, retryPolicy — all defaulted
)

// UIKit
let result = try await IDVerse.runVerification(txConfig, using: service, from: self, configuration: config)

// SwiftUI
IDVerseVerificationFlow(config: txConfig, service: service, configuration: config) { outcome in … }
```

With the default `.disabled` observability there is no handler, but the SDK still
writes redacted `os.Logger` breadcrumbs (event name is logged `.public`,
transaction id is `.private`) — visible in Console.app without any integrator
wiring.

**Event names by phase:**

| Phase | Events |
|---|---|
| Start | `started`, `transactionCreateStarted`, `transactionCreateSucceeded` |
| WebView | `presented`, `webViewLoaded`, `webContentProcessTerminated`, `redirectMatched` |
| Result | `resultFetchStarted`, `retrying`, `resultPending`, `resultPollingTimedOut` |
| Terminal | `completed`, `cancelled`, `failed` |

**Payload safety:** event associated values carry _only_ transaction ids, the
`IDVerseVerificationResult.Outcome` enum, `IDVerseFailureCategory` (a typed
category, never a raw error message), and numeric counters. No URL, token,
document data, name, date of birth, or raw payload can appear in an event — PII
safety is structural (enforced by the type shape), not just a convention. Events
are safe to forward directly to an analytics or observability backend.

---

## Resilience (automatic)

The following behaviours are on by default and require no configuration:

- **Transient-error retry.** Network operations (transaction create and result
  fetch) are retried up to 3 times with exponential backoff (0.5 s initial, 4 s
  cap, ±20% jitter). The default policy retries transient `URLError`s (timeout,
  connection lost, host unreachable, DNS failure, not connected) and
  conservatively retries unknown errors. To narrow retries for typed backend
  errors, supply a custom `retryPolicy`:

  ```swift
  let config = IDVerseConfiguration(
      retryPolicy: IDVerseRetryPolicy(
          maxAttempts: 3, initialDelay: 0.5, maxDelay: 4.0, jitter: 0.2,
          isRetryable: { error in
              IDVerseRetryPolicy.defaultIsRetryable(error)
          }
      )
  )
  ```

- **Result polling.** After the redirect the SDK polls `fetchResult` while the
  outcome is `.pending`, backing off between attempts (1 s → 5 s cap), up to
  `resultPollingTimeout` (default 60 s). If polling times out the SDK returns the
  final `.pending` result rather than throwing — reconcile via the webhook.

- **Idempotent transaction creation.** The orchestrator generates a UUID
  `idempotencyKey` once per run and reuses it across all create-retry attempts, so
  your backend can deduplicate retried requests. Wire the key through your
  backend's Store Transaction call to fully activate deduplication; the SDK sends
  it unconditionally.

- **Configurable WebView load timeout.** Default 30 s; override via
  `IDVerseConfiguration(webViewLoadTimeout:)`. The watchdog is
  backgrounding-aware — it pauses when the app backgrounds so it cannot fire while
  the OS suspends the process.

- **WebView content-process recovery.** If WebKit's renderer is jettisoned the
  SDK automatically reloads the transaction URL once. A second termination fails
  cleanly with a `webContentLoadFailed` error.

- **Cancellation hygiene.** External Swift `Task` cancellation and SwiftUI view
  teardown (e.g. sheet dismissed) both cancel the in-flight verification cleanly
  through the same code path — no leaked continuations or orphaned webviews.

---

## API reference

### Entry points

All entry points accept `configuration: IDVerseConfiguration = .default` — the
parameter is always optional; existing call sites require no changes.

| Method | Returns | Use when |
|---|---|---|
| `IDVerse.runVerification(_:using:from:configuration:)` | `IDVerseVerificationResult` | Full lifecycle (create → present → fetch) — UIKit |
| `IDVerse.verify(_:from:configuration:)` | `IDVerseStatus` | You already have a transaction URL — UIKit |
| `IDVerseVerificationFlow(config:service:configuration:onFinish:)` | `IDVerseVerificationResult` | Full lifecycle — SwiftUI |
| `IDVerseVerificationView(request:configuration:onFinish:)` | `IDVerseStatus` | Lean, you already have a transaction URL — SwiftUI |

### `IDVerseTransactionService` protocol

```swift
public protocol IDVerseTransactionService {
    func createTransaction(_ config: TransactionConfig) async throws -> IDVerseTransaction
    func fetchResult(transactionId: String) async throws -> IDVerseVerificationResult
}
```

**Built-in implementations:**

- `RemoteTransactionService(backendBaseURL:)` — scaffold for the backend-proxy
  pattern; wire your backend contract here. Use in production.
- `MockTransactionService` — returns canned data. Use for local development and
  UI iteration without real credentials.

### Key models

```swift
// SDK-behaviour config (distinct from per-transaction data)
struct IDVerseConfiguration {
    var observability: IDVerseObservability   // default .disabled
    var webViewLoadTimeout: TimeInterval      // default 30 s
    var resultPollingTimeout: TimeInterval    // default 60 s
    var retryPolicy: IDVerseRetryPolicy       // default .default
    static let default: IDVerseConfiguration
}

// Input to the full-lifecycle API
struct TransactionConfig {
    let flowType: String
    var customerReference: String?
    let redirectURL: URL
    var idempotencyKey: String   // default ""; orchestrator generates a per-run UUID if empty
}

// Input to the lean API
struct IDVerseVerificationRequest {
    let transactionURL: URL
    let redirectURL: URL
    var showsCloseButton: Bool   // default true
    var transactionId: String?   // default nil; populated by the orchestrator on full-lifecycle runs
}

// What a transaction service returns
struct IDVerseTransaction {
    let id: String
    let url: URL
    let redirectURL: URL
}

// Result from the full-lifecycle API
struct IDVerseVerificationResult {
    let transactionId: String
    let outcome: Outcome          // .passed / .failed / .refer / .pending
    let extractedData: [String: String]?
    let checks: [IDVerseCheck]?
    let rawJSON: Data?
    enum Outcome: String { case passed, failed, refer, pending }
}

// Result from the lean API
enum IDVerseStatus { case completed, cancelled }

struct IDVerseCheck { let name: String; let passed: Bool? }
```

### `IDVerseError`

```swift
enum IDVerseError: Error {
    case invalidTransactionURL
    case cameraPermissionDenied
    case microphonePermissionDenied
    case webContentLoadFailed(underlying: Error)
    case transactionCreationFailed(underlying: Error)
    case resultFetchFailed(underlying: Error)
    case cancelled
}
```

### Observability types

```swift
// Attach a handler
IDVerseConfiguration(
    observability: .events { (event: IDVerseEvent) in … }
)
// or silence (the default):
IDVerseConfiguration(observability: .disabled)

// IDVerseEvent exposes:
event.name           // String — stable PII-free key, safe as an analytics event name
event.transactionId  // String? — the transaction id, if known at that point

// IDVerseFailureCategory — typed taxonomy (no raw error messages)
// .cameraPermissionDenied | .microphonePermissionDenied | .webContentLoadFailed
// | .transactionCreationFailed | .resultFetchFailed | .timedOut | .cancelled | .unknown

// IDVerseOperation — identifies which step is retrying
// .createTransaction | .fetchResult
```

### `IDVerseRetryPolicy`

```swift
struct IDVerseRetryPolicy {
    var maxAttempts: Int          // default 3
    var initialDelay: TimeInterval // default 0.5 s
    var maxDelay: TimeInterval    // default 4.0 s
    var jitter: Double            // default 0.2 (±20%)
    var isRetryable: (Error) -> Bool
    static let default: IDVerseRetryPolicy   // retries transient URLErrors
    static let none: IDVerseRetryPolicy      // 1 attempt, no retry
    static func defaultIsRetryable(_ error: Error) -> Bool
}
```

---

## Security checklist

- [ ] No IDVerse API key or client secret anywhere in the app binary or its
      bundled config.
- [ ] Transactions created by your backend (Store Transaction), never by the app
      directly.
- [ ] Final decisions gated on the backend webhook, not the in-app result.
- [ ] `DirectTransactionService` (sandbox key hardcoded) used in the example app
      only — never shipped in a production build.
- [ ] Telemetry is PII-safe by design — events and logs carry no document data,
      names, dates of birth, or raw error messages; a compliance reviewer can
      assert this from the event type's shape alone.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Spinner then a load error after ~30 s | The transaction URL didn't load — it's a placeholder/unreachable, or the network failed. Use a real transaction URL from IDVerse. |
| Immediate `cameraPermissionDenied` | Camera permission was declined, or the `NSCameraUsageDescription` usage string (Step 2) is missing from `Info.plist`. |
| Immediate `microphonePermissionDenied` | Microphone permission was declined, or the `NSMicrophoneUsageDescription` usage string (Step 2) is missing from `Info.plist`. |
| Flow returns `.cancelled` | User tapped Close before finishing the journey. |
| Result is `.pending` in-app | The SDK polls up to 60 s but IDVerse may not have finalised yet — always consume the backend webhook for the authoritative outcome. |
| `WKWebView` "web-browser-engine entitlement" in logs | Benign WebKit console noise; not an error. |
| "No such module 'IDVerseSDK'" | Verify the package is added to the target's **Frameworks, Libraries, and Embedded Content**. Clean (⌘⇧K) and rebuild. |
| "Module compiled with Swift X cannot be imported by Swift Y" | Clean the build folder and ensure Xcode and the Swift toolchain versions match. |

---

## Current status

The transaction API is **stubbed** pending a live IDVerse contract:
`RemoteTransactionService.createTransaction` and `fetchResult` throw
`notImplemented` until wired to a real backend. The SDK presentation layer,
completion detection, observability, resilience, and result handling are complete
and tested — wire your backend (Step 3) to go live.
