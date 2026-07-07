# IDVerse iOS SDK — Developer Guide

This guide is for people who own and extend the SDK code. For integrating the SDK
into an app, see `INTEGRATION_GUIDE.md` in the same folder.

---

## 1. What the SDK is (and why it is a WebView wrapper)

IDVerse has **no native mobile SDK**. Its identity-verification journey
(consent → document capture → OCR → confirm details → liveness → complete) is a
**hosted web flow** served by IDVerse's servers. The SDK therefore wraps that flow
in an embedded `WKWebView` and provides a clean native Swift API around it. It does
**not** do native capture, OCR, or liveness — those all run inside IDVerse's web
flow on IDVerse's servers.

The integration follows IDVerse's three-phase model:

```
Phase 1 — Initiate     Your backend calls IDVerse "Store Transaction"  → transaction URL
Phase 2 — Run flow     App loads that URL in a WKWebView; user completes the journey
Phase 3 — Consume      Your backend receives the result via webhook / "Get Results"
```

Keep this split in mind when reading the code:

- **Native (ours):** the public API, the webview container and its chrome, camera
  permission, completion detection, and create→present→fetch lifecycle orchestration.
- **Web (IDVerse's):** every pixel of the verification journey.

The lifecycle is always: *your backend creates a transaction → the app loads its
URL in the webview → IDVerse redirects to a known URL when done → your backend
fetches the authoritative result.*

---

## 2. Architecture and layered design

### Two layers, one compile guard

The package is split so that all logic is unit-testable on the macOS host and all
iOS-only code is isolated behind a compile guard:

```
Public API (facade + SwiftUI)
  IDVerse.runVerification / IDVerse.verify
  IDVerseVerificationFlow (full)  ·  IDVerseVerificationView (lean)
        │
        ├── Orchestration (Foundation)
        │     VerificationOrchestrator · WebFlowOutcome · IDVerseRedirectMatcher
        │
        ├── Presentation (iOS · UIKit/WebKit)
        │     IDVerseWebViewController · WebViewConfigurationFactory · OriginAllowList
        │
        ├── Transaction services (Foundation)
        │     IDVerseTransactionService (protocol) · MockTransactionService · RemoteTransactionService (scaffold)
        │
        ├── Observability (Foundation)
        │     IDVerseEvent · IDVerseObservability · IDVerseEventEmitter
        │
        └── Models (Foundation)
              Request · Transaction · Result(+Outcome,Check) · TransactionConfig
              IDVerseConfiguration · Status · Error
              IDVerseRetryPolicy (+ RetryRunner · OneShotCompletion in Core)
```

- **Foundation layer** (`Models/`, `Core/IDVerseRedirectMatcher`,
  `Core/VerificationOrchestrator`, `Core/WebFlowOutcome`,
  `Core/OriginAllowList`, `Core/IDVerseRetryPolicy`, `Core/RetryRunner`,
  `Core/OneShotCompletion`, `Observability/*`, `Transaction/*`): no UIKit/WebKit
  imports — compiles on macOS 11+ and is unit-tested via `swift test`.
- **iOS presentation layer** (`Core/IDVerseWebViewController`,
  `Core/WebViewConfigurationFactory`, `Core/IDVerseVerificationView`,
  `Core/IDVerseVerificationFlow`, `IDVerse.swift`): wrapped in
  `#if canImport(UIKit)`; verified by building for iOS and a manual smoke test.

**The rule that makes this work:** every file that imports `UIKit` or `WebKit`
must be wrapped in `#if canImport(UIKit) … #endif`. On the macOS host those files
compile to nothing, so `swift test` can run the pure logic. If you add iOS-only
code and forget the guard, `swift build`/`swift test` breaks on macOS — that is
the signal.

### Components

| Component | Responsibility |
|---|---|
| `IDVerse` (facade) | `runVerification(_:using:from:configuration:)` (full lifecycle → `IDVerseVerificationResult`) and `verify(_:from:configuration:)` (lean → `IDVerseStatus`). Presents the controller via a `OneShotCompletion` box + `withTaskCancellationHandler`. Emits boundary events (`.cancelled`, `.failed`). `configuration:` defaults to `.default`. |
| `IDVerseVerificationFlow` | SwiftUI full-lifecycle entry: hosts a controller that runs `runVerification` once and returns the real result. Cancels the in-flight `Task` in `dismantleUIViewController` for clean SwiftUI teardown. |
| `IDVerseVerificationView` | SwiftUI lean entry: presents an already-created transaction URL, returns webview-level status. |
| `IDVerseWebViewController` | Full-screen `WKWebView` host: native loader/close/error, camera-permission gate, redirect detection, fail-closed media-capture grant. Load timeout from `configuration.webViewLoadTimeout`; backgrounding-safe watchdog. Content-process recovery: reloads once on first WebKit renderer termination, fails on second. Emits `.presented`, `.webViewLoaded`, `.webContentProcessTerminated`, `.redirectMatched`, `.navigationBlocked`. Main-frame navigation is gated by `NavigationPolicy` (fail-closed origin allow-list). |
| `VerificationOrchestrator` | Sequencing with retry, idempotency, result polling, and event emission: `createTransaction` (retry + fixed idempotency key per run) → `present` → `fetchResult` (retry) → poll while `.pending` up to `resultPollingTimeout`. Injects `present`/`sleep`/`now` so it stays UIKit-free and testable. |
| `IDVerseTransactionService` | Protocol for the transaction lifecycle. `MockTransactionService` (canned data) and `RemoteTransactionService` (backend-proxy scaffold) ship in the SDK. |
| `IDVerseRedirectMatcher` | Pure logic that recognises the exit-redirect URL (scheme+host+path, query-tolerant) and extracts the transaction id. |
| `OriginAllowList` | Pure, fail-closed allow-list: camera/mic granted only to the transaction host + known IDVerse domains. |
| `WebViewConfigurationFactory` | Builds the `WKWebViewConfiguration` (inline media, JS, Chrome UA, non-persistent data store). |
| `IDVerseConfiguration` | Single SDK-behaviour config value type (`Sendable`): `observability`, `webViewLoadTimeout` (default 30 s), `resultPollingTimeout` (default 60 s), `retryPolicy` (default `.default`), `limitsNavigationsToAppBoundDomains` (default `false`, opt-in WebKit-enforced navigation lock). Every entry point accepts it defaulted — existing call sites compile unchanged. |
| `IDVerseObservability` | PII-safe event sink (`Sendable`). `.disabled` (default) or `.events { handler }`. Redacted `os.Logger` breadcrumbs emit even when disabled. |
| `IDVerseEvent` | Public lifecycle event enum (`Sendable`). Cases cover the full lifecycle from `.started` through `.completed`/`.cancelled`/`.failed`. Payloads carry only ids / `Outcome` / `IDVerseFailureCategory` / counters — no URL, token, raw error, or document data. |
| `IDVerseRetryPolicy` | Public retry config (`Sendable`): `maxAttempts`, `initialDelay`, `maxDelay`, `jitter`, `isRetryable`. `.default` (3 attempts, exponential backoff 0.5–4 s ± 20% jitter, transient `URLError`s retryable) and `.none` (1 attempt) ship. Integrators supply a custom `isRetryable` for typed backend errors. |
| Core resilience (internal) | `RetryRunner` — `withRetry` generic helper: exponential backoff, `.retrying` events before each sleep, `CancellationError` always propagates. `OneShotCompletion<T>` — `@MainActor` resume-exactly-once box; all exit paths funnel through it, first wins. |
| Models | `IDVerseVerificationRequest`, `IDVerseTransaction`, `TransactionConfig` (+`idempotencyKey`), `IDVerseVerificationResult` (+`Outcome` (also `Sendable`), `IDVerseCheck`), `IDVerseStatus`, `IDVerseError`, `IDVerseOperation`, `IDVerseFailureCategory`. |

### Data flow (full lifecycle)

```
runVerification(txConfig, using: service, from: vc, configuration: config)
  events ──────────────────────────────────────────────────────────────────►
  emit .started
  1. [retry loop] emit .transactionCreateStarted
     service.createTransaction(txConfig)          → IDVerseTransaction { id, url, redirectURL }
     emit .transactionCreateSucceeded(transactionId:)
     (idempotency key fixed for all retry attempts — duplicate creates not issued)
  2. present IDVerseWebViewController(url, configuration:)
       AVCapture permission → emit .presented
       load url in WKWebView → emit .webViewLoaded (once)
       (watchdog: backgrounding-safe, fires after webViewLoadTimeout)
       (on WebKit crash: reload once → emit .webContentProcessTerminated; 2nd crash → fail)
  3. user completes IDVerse's web journey
  4. IDVerse navigates to redirectURL             → matcher detects (main frame only)
       emit .redirectMatched(transactionId:)      → WebFlowOutcome(.completed, txId)
  5. emit .resultFetchStarted; [retry loop]
     service.fetchResult(redirectTxId ?? id)      → IDVerseVerificationResult
  6. [polling loop while .pending and within resultPollingTimeout]
       emit .resultPending; sleep (backoff 1→5 s); re-fetch
       if still .pending at timeout: emit .resultPollingTimedOut
  emit .completed(transactionId:outcome:)
  → returns the final result (outcome may be .pending — webhook is authoritative)

  on error:   emit .failed(reason: IDVerseFailureCategory(error), transactionId:)  (facade)
  on cancel:  emit .cancelled(transactionId:)                                       (facade)
```

### Security model

- **No IDVerse secrets in the app.** The SDK ships only `MockTransactionService`
  and `RemoteTransactionService` (which calls *your* backend). The backend holds
  the IDVerse API secret and calls Store Transaction / Get Results. A
  `DirectTransactionService` that calls IDVerse with a sandbox key lives only in
  the example app and must never ship to production.
- **Non-persistent web storage** (`websiteDataStore = .nonPersistent()`) — no
  on-disk cookie/cache residue after a verification.
- **Fail-closed media permission** — the webview may use the camera/mic only for
  the transaction's host and known IDVerse domains; all other origins are denied.
- **Main-frame-only completion** — the exit-redirect is honoured only for
  main-frame navigations, so sub-frame URLs cannot spoof completion.
- **`.pending` is authoritative-deferred** — `fetchResult` right after the
  redirect may return `.pending`; the SDK polls up to `resultPollingTimeout` and
  may still return `.pending` if that expires. The webhook to your backend is the
  source of truth for the final outcome.
- **PII-safe telemetry** — events and `os.Logger` breadcrumbs carry only
  ids / `Outcome` / `IDVerseFailureCategory` / counters, enforced structurally
  by the `IDVerseEvent` type's shape. No URL, token, raw error message, extracted
  document data, name, or DOB can appear in a telemetry payload.

---

## 3. File map

```
Source/
  IDVerse.swift                         (iOS)  Public facade — the main entry points
  Models/                               (Foundation) Public value types
    IDVerseConfiguration.swift            SDK-behaviour config (observability/timeouts/retry)
    IDVerseError.swift
    IDVerseStatus.swift
    IDVerseVerificationRequest.swift
    IDVerseTransaction.swift
    IDVerseVerificationResult.swift
    TransactionConfig.swift
  Observability/                        (Foundation) PII-safe event system
    IDVerseEvent.swift                    Public event enum, IDVerseOperation, IDVerseFailureCategory
    IDVerseObservability.swift            Public handler-attachment type
    IDVerseEventEmitter.swift             Internal: delivers to handler + redacted OSLog
  Transaction/                          (Foundation) The "talk to IDVerse" seam
    IDVerseTransactionService.swift       protocol (+ internal IDVerseNotImplemented)
    MockTransactionService.swift          canned data, for dev/tests
    RemoteTransactionService.swift        backend-proxy SCAFFOLD (throws notImplemented)
  Core/
    IDVerseRedirectMatcher.swift        (Foundation) Detects the exit-redirect URL
    IDVerseRetryPolicy.swift            (Foundation) Public retry config + defaultIsRetryable
    RetryRunner.swift                   (Foundation) Internal withRetry() — exponential backoff
    OneShotCompletion.swift             (Foundation) Internal resume-exactly-once box
    VerificationOrchestrator.swift      (Foundation) Sequences create→present→fetch (retry/poll/events)
    WebFlowOutcome.swift                (Foundation) internal { status, transactionId }
    OriginAllowList.swift               (Foundation) Fail-closed camera/mic origin gate
    NavigationPolicy.swift              (Foundation) Fail-closed main-frame origin gate
    OriginHeaderState.swift             (Foundation) Live origin-header state derivation
    WebViewConfigurationFactory.swift   (iOS)  Builds the WKWebViewConfiguration
    IDVerseWebViewController.swift      (iOS)  The WKWebView host (the heart of the UI)
    IDVerseVerificationView.swift       (iOS)  SwiftUI wrapper — lean (status only)
    IDVerseVerificationFlow.swift       (iOS)  SwiftUI wrapper — full lifecycle (real result)
Tests/                                  (Foundation) unit tests for the logic layer
Examples/IDVerseApp/                    SwiftUI app that consumes the package
```

---

## 4. The models (`Source/Models/`)

Plain `Sendable`-friendly value types. Every public struct has an **explicit
`public init`** — Swift's synthesised memberwise init is `internal`, so without
it an integrator in another module cannot construct these.

- **`IDVerseConfiguration`** — the SDK-behaviour config, distinct from per-transaction
  data. Fields (all defaulted): `observability: IDVerseObservability` (default
  `.disabled`), `webViewLoadTimeout: TimeInterval` (default `30`),
  `resultPollingTimeout: TimeInterval` (default `60`), `retryPolicy: IDVerseRetryPolicy`
  (default `.default`), `limitsNavigationsToAppBoundDomains: Bool` (default
  `false`; opt-in WebKit-enforced navigation lock — requires the host app's
  `WKAppBoundDomains` Info.plist key). `static let default` gives a zero-config value; all entry
  points accept `configuration: IDVerseConfiguration = .default` so existing call
  sites keep compiling unchanged.
- **`IDVerseVerificationRequest`** — input to the *lean* path: `transactionURL`
  (what to load), `redirectURL` (how completion is detected), `showsCloseButton`,
  `showsOriginHeader` (default `true`; native trust bar above the webview showing
  the live origin), `transactionId: String?` (default `nil`; set by the orchestrator
  before passing to `present` so the controller and events carry the id without the
  caller needing to supply it).
- **`TransactionConfig`** — input to the *full* path: `flowType`,
  `customerReference?`, `redirectURL`, `idempotencyKey: String` (default `""`; the
  orchestrator generates a UUID per run if empty, reusing it across retries so a
  repeated create is idempotent). This type is the per-transaction request;
  `IDVerseConfiguration` is the SDK-behaviour config — they are separate by design.
- **`IDVerseTransaction`** — what a transaction service returns: `id`, `url`,
  `redirectURL`.
- **`IDVerseVerificationResult`** — the real outcome: `transactionId`,
  `outcome` (`.passed/.failed/.refer/.pending`), `extractedData?`, `checks?`,
  `rawJSON?`. **`.pending` is a valid success** — it means "the journey ended but
  the backend has not finalised; reconcile via the webhook." `Outcome` is `Sendable`.
- **`IDVerseStatus`** — `.completed`/`.cancelled`, the *webview-level* outcome
  (did the user finish or close), distinct from the verification `Outcome`.
- **`IDVerseError`** — the public error enum (`invalidTransactionURL`,
  `cameraPermissionDenied`, `microphonePermissionDenied`, `cancelled`,
  `webContentLoadFailed`, `transactionCreationFailed`, `resultFetchFailed`).
  The three `…Failed` cases wrap an underlying `Error`.

---

## 5. The transaction seam (`Source/Transaction/`)

This is how the SDK gets a transaction and fetches a result **without holding any
IDVerse secret**. It is the most important extension point.

- **`IDVerseTransactionService`** (protocol): `createTransaction(_:) ->
  IDVerseTransaction` and `fetchResult(transactionId:) -> IDVerseVerificationResult`.
  Anyone can implement it.
- **`MockTransactionService`** — returns a canned transaction + result. Used by
  the orchestrator tests and the example app's "preview result" path.
- **`RemoteTransactionService`** — the **production shape**: it is meant to call
  *your backend* (which proxies IDVerse Store Transaction / Get Results). It is a
  **scaffold** today: both methods `throw IDVerseError.…Failed(IDVerseNotImplemented(…))`
  until the backend contract exists. `IDVerseNotImplemented` is deliberately
  `internal` so it stays out of the public surface.
- **`DirectTransactionService`** lives in the **example app**, not here, because
  it holds a sandbox key. That separation is intentional and load-bearing for the
  "no secrets in the SDK" guarantee — do not move it into `Source/`.

---

## 6. The logic core (`Source/Core/`, Foundation)

These are pure and fully unit-tested — the parts you can reason about without a
webview.

### `IDVerseRedirectMatcher`

Decides whether a navigation target **is** the exit redirect. It matches
`scheme + host + path` of the configured `redirectURL` (case-insensitive,
**ignoring the query string**) and extracts a transaction id from a
`transactionId` or `transaction_id` query item. Isolating this means the tricky
"did the flow finish?" decision is testable without WebKit. Returns a
`Match { transactionId: String? }`.

### `IDVerseRetryPolicy` (public) and `RetryRunner` (internal)

**`IDVerseRetryPolicy`** is the public config for retry behaviour:
`maxAttempts`, `initialDelay`, `maxDelay`, `jitter`, and an `isRetryable`
predicate. `static let default` (3 attempts, 0.5 s initial, 4.0 s max, 0.2
jitter) retries transient `URLError`s (timedOut, networkConnectionLost,
cannotConnect/FindHost, dnsLookupFailed, notConnectedToInternet). It **never**
retries `CancellationError` or `IDVerseError.cancelled`. Unknown errors are **not**
retried (fail fast); integrators override `isRetryable` to opt typed transient
backend errors into retries.
`static let none` skips all retries (1 attempt).

**`RetryRunner`** (`withRetry`) is the internal free function that executes the
policy: N attempts, N−1 `.retrying` events (emitted before each sleep), clamped
exponential backoff ± jitter. `sleep` and `now` are injected so tests run with no
real delay.

### `OneShotCompletion<T>` (internal)

A `@MainActor final class` that is a **resume-exactly-once box**. Both the
WebView callback and the cancellation path (`cancelFromOutside`) funnel through
`resume(_:)` — the first wins; later calls are silently dropped. This eliminates
the continuation-crash risk and makes all exit paths (redirect / Close / error /
Task cancel / SwiftUI teardown) safe to race.

### `WebFlowOutcome` (internal)

`{ status: IDVerseStatus, transactionId: String? }`. The *internal* result of
presenting the webview — webview-level status plus the id IDVerse may have put in
the redirect. It is **internal on purpose**: the public surface is
`IDVerseStatus`/`IDVerseVerificationResult`, not this plumbing type.

### `VerificationOrchestrator`

The pure sequencer for the full lifecycle. Takes the presentation step as an
**injected closure** (`present: (Request) async throws -> WebFlowOutcome`) so it
stays UIKit-free and testable. `run(_:)` performs the full
retry/idempotency/poll/events flow:

```
run(config):
  emit .started
  if config.idempotencyKey is empty → assign UUID once (reused across retries)

  emit .transactionCreateStarted
  tx = withRetry(retryPolicy, .createTransaction) { service.createTransaction(config) }
  emit .transactionCreateSucceeded(transactionId: tx.id)

  request = IDVerseVerificationRequest(transactionURL: tx.url, redirectURL: tx.redirectURL)
  request.transactionId = tx.id
  outcome = present(request)   // injected; real impl shows the webview
  guard outcome.status == .completed else { throw .cancelled }

  id = outcome.transactionId ?? tx.id   // redirect id wins; fall back to created id
  emit .resultFetchStarted(transactionId: id)
  result = withRetry(retryPolicy, .fetchResult) { service.fetchResult(transactionId: id) }

  // Result polling: while .pending and within resultPollingTimeout deadline
  deadline = now() + max(0, resultPollingTimeout)
  pollDelay = 1.0
  while result.outcome == .pending && now() < deadline:
    emit .resultPending(transactionId: id)
    sleep(pollDelay)
    pollDelay = min(5.0, pollDelay × 2)   // backoff 1→2→4→5
    result = withRetry(retryPolicy, .fetchResult) { service.fetchResult(transactionId: id) }

  if result.outcome == .pending: emit .resultPollingTimedOut(transactionId: id)
  emit .completed(transactionId: id, outcome: result.outcome)
  return result   // may be .pending — webhook is authoritative
```

The idempotency key is generated *once before* the create-retry loop, so a
retried create carries the same key every attempt — the backend can deduplicate.

### `OriginAllowList`

A **fail-closed** gate for the webview's camera/mic permission. Built from the
transaction URL's host plus known IDVerse suffixes (`.idkit.co`, `.idverse.com`
and their apexes). `allows(host:)` returns true only for those; **nil/empty/any
other origin → false.** This is why the controller can safely grant getUserMedia
only to IDVerse and deny everything else.

### `NavigationPolicy`

Decides what to do with a webview navigation, given the redirect matcher and
the `OriginAllowList`. **Fail-closed** on the main frame: the exit redirect
finishes the flow, an allowed `http`/`https` origin (or `about:`) is allowed,
and everything else — including a `nil` URL or an unknown scheme — is
`.block`ed. Sub-frame navigations are unrestricted; the main frame is the only
trust surface.

### `OriginHeaderState`

The trust state shown in the native origin header, derived live from the
webview's current URL against the same `OriginAllowList` — never a hardcoded
label. **`https`-only verified semantics:** a `nil`/`about:` URL is `.loading`;
a verified `https` host on the allow-list is `.verified(host:)`; anything else
(including a plain `http` origin) is `.unverified`.

---

## 7. The iOS presentation layer (`Source/Core/`, guarded)

### `WebViewConfigurationFactory`

Builds the `WKWebViewConfiguration` with the settings IDVerse's flow requires (and
that are easy to get wrong): `allowsInlineMediaPlayback = true`,
`mediaTypesRequiringUserActionForPlayback = []`, JS via
`defaultWebpagePreferences.allowsContentJavaScript`, and a **non-persistent**
data store (no on-disk cookie/cache residue after a verification). It also vends
the Chrome-iOS `chromeUserAgent` constant. The UA is applied to the `WKWebView`
itself (it is a `WKWebView` property, not a config property).

### `IDVerseWebViewController` — the heart of the UI

A full-screen `WKWebView` host. Init takes `request`, `configuration` (defaulted
`.default`), `emitter` (defaulted `.disabled` flow emitter), and an `onFinish`
closure.

- **Setup:** builds the webview from the factory, sets the Chrome UA, becomes
  `WKNavigationDelegate` + `WKUIDelegate`, adds a native spinner and (optionally)
  a Close button.
- **Media permission gate (`loadAfterMediaPermissions`):** requests
  `AVCaptureDevice` video then audio permission *before* loading (the web flow
  needs the camera for capture and the microphone for liveness); camera denied →
  finishes with `.cameraPermissionDenied`, microphone denied →
  `.microphonePermissionDenied`; both granted → emits
  `.presented(transactionId:)`, observes app lifecycle notifications, starts the
  load watchdog, and loads the transaction URL.
- **Load watchdog (`startLoadWatchdog`):** a `DispatchWorkItem` that fires after
  `configuration.webViewLoadTimeout` and fails the flow with a clear timeout error
  **if the first page never loads** — so a dead/placeholder URL surfaces an error
  instead of spinning forever. It is **cancelled on the first `didFinish`** so a
  legitimately long in-progress journey (capture/liveness takes minutes) is never
  interrupted. It is also cancelled in `finish()` so the controller releases
  promptly.
- **Backgrounding-aware watchdog:** `appDidBackground` cancels the watchdog
  (suspended wall-clock cannot trip it); `appWillForeground` re-arms it only if
  the first load has not finished and the flow is not done. Lifecycle observers are
  removed in `deinit`.
- **Content-process recovery (`webViewWebContentProcessDidTerminate`):** emits
  `.webContentProcessTerminated(transactionId:)`; on the **first** termination
  reloads the URL (guarded by `reloadedAfterTermination`) and re-arms the watchdog;
  on a **second** termination fails with `.webContentLoadFailed`.
- **Completion detection (`decidePolicyFor`):** only for **main-frame**
  navigations (`navigationAction.targetFrame?.isMainFrame == true`), it asks the
  matcher; on a match it cancels the navigation, emits
  `.redirectMatched(transactionId:)`, and finishes `.completed` with the redirect's
  transactionId. The main-frame guard prevents a sub-frame URL from spoofing
  completion. Main-frame navigations are also gated by `NavigationPolicy` — a
  fail-closed origin allow-list; off-list navigations are cancelled and emit
  `.navigationBlocked` without ending the flow.
- **`webView(_:didFinish:)`:** cancels the watchdog, stops the spinner, and emits
  `.webViewLoaded(transactionId:)` exactly **once** (guarded by `firstLoadDone`).
- **Media permission (`requestMediaCapturePermissionFor`):** grants only if
  `allowList.allows(host: origin.host)`, else `.deny` — fail closed.
- **`finish(_:)`:** guarded by a `didFinish` flag so the outcome is delivered
  **exactly once**, no matter which path (redirect, close, load error) fires first.
- **`setOnFinish(_:)` / `cancelFromOutside()`:** the facade replaces the initial
  no-op `onFinish` with `setOnFinish` to wire the `OneShotCompletion` box, and
  calls `cancelFromOutside()` on Task cancellation — both route through the same
  `finish(.success(.cancelled, …))` path. `onFinish` is `@MainActor`-typed.

**Five controller events** (emitted by the controller, disjoint from the
orchestrator's events): `.presented`, `.webViewLoaded`,
`.webContentProcessTerminated`, `.redirectMatched`, `.navigationBlocked`.

The delegate methods must be `public` — Swift requires public witnesses for the
public `WKNavigationDelegate`/`WKUIDelegate` conformances.

### `IDVerseVerificationView` (SwiftUI, lean)

A `UIViewControllerRepresentable` that builds its own `IDVerseEventEmitter` from
`configuration.observability` and constructs `IDVerseWebViewController(request:
configuration:emitter:onFinish:)`. Maps the `WebFlowOutcome` down to the public
`IDVerseStatus` (`result.map { $0.status }`). Use it when you already have a
transaction URL. Takes `configuration: IDVerseConfiguration = .default`.

### `IDVerseVerificationFlow` (SwiftUI, full)

The full-lifecycle SwiftUI entry. Takes `configuration: IDVerseConfiguration = .default`.
It hosts an `IDVerseFlowHostController` which, in `viewDidAppear` (guarded to run
**once** via a `started` flag), calls `IDVerse.runVerification(config, using:
service, from: self, configuration: configuration)` and delivers the real
`IDVerseVerificationResult`.

**`dismantleUIViewController`** calls `uiViewController.cancel()` → `task?.cancel()`
so when SwiftUI tears the view down (e.g. a cover sheet is dismissed) the in-flight
verification cancels cleanly through the same `withTaskCancellationHandler` →
`cancelFromOutside()` path as an external Task cancel.

The host controller is `public` (it is the representable's `UIViewControllerType`,
which a public representable's `makeUIViewController` must return) but its `init`
is `internal` — so it can be built from the same module but not constructed by
integrators directly.

---

## 8. The facade (`Source/IDVerse.swift`, guarded, `@MainActor`)

- **`runVerification(_:using:from:configuration:)`** — full lifecycle.
  `configuration` defaulted `.default`. Builds **one** `IDVerseEventEmitter(
  configuration.observability, category: "flow")` shared by the orchestrator and
  the controller. Wires a `VerificationOrchestrator` whose `present` closure calls
  the private `present(_:from:configuration:emitter:)`. On cancellation emits
  `.cancelled(transactionId: nil)`; on other `IDVerseError` emits `.failed(reason:
  IDVerseFailureCategory(error), transactionId: nil)`.
- **`verify(_:from:configuration:)`** — lean. `configuration` defaulted `.default`.
  Builds its own shared emitter. Calls `present` and, if the outcome is `.cancelled`,
  emits `.cancelled(transactionId: outcome.transactionId)`. Still **returns**
  `.cancelled` (does not throw). On thrown errors emits `.failed`.
- **`present(_:from:configuration:emitter:)`** (private) — bridges callback → async
  via `withCheckedThrowingContinuation`. Constructs the controller with an initial
  no-op `onFinish`, then:
  1. Creates an `OneShotCompletion<WebFlowOutcome>` box whose delivery block
     dismisses the presenter then resumes the continuation.
  2. Calls `controller.setOnFinish { box.resume($0) }` to wire the box.
  3. Wraps the continuation in `withTaskCancellationHandler` — on cancel fires
     `Task { @MainActor in controller.cancelFromOutside() }`.
  4. Presents the controller full-screen.

  The `OneShotCompletion` box guarantees the continuation resumes exactly once on
  every exit path (redirect / failure / Close / external Task cancel / SwiftUI
  teardown). `@MainActor` isolation is handled by annotating the `onFinish` closure
  type; `MainActor.assumeIsolated` is not used (iOS 17+ only; the target is iOS 15).

---

## 9. Observability layer (`Source/Observability/`)

The observability layer provides PII-safe, structured lifecycle events with no
third-party dependencies.

### Types

- **`IDVerseObservability`** (public) — the handler-attachment value. `static let
  disabled` (no handler); `static func events(_ handler: @Sendable (IDVerseEvent)
  -> Void)` to attach a closure. Pass via `IDVerseConfiguration.observability`.
- **`IDVerseEvent`** (public enum, `Sendable`) — 14 lifecycle events. Cases:
  `.started`, `.transactionCreateStarted`,
  `.transactionCreateSucceeded(transactionId:)`, `.presented(transactionId:)`,
  `.webViewLoaded(transactionId:)`, `.webContentProcessTerminated(transactionId:)`,
  `.redirectMatched(transactionId:)`, `.resultFetchStarted(transactionId:)`,
  `.retrying(operation:attempt:maxAttempts:reason:)`,
  `.resultPending(transactionId:)`, `.resultPollingTimedOut(transactionId:)`,
  `.completed(transactionId:outcome:)`, `.cancelled(transactionId:)`,
  `.failed(reason:transactionId:)`. Convenience accessors: `event.name` (stable
  PII-free string key) and `event.transactionId: String?`.
- **`IDVerseOperation`** (public enum) — `.createTransaction`, `.fetchResult`.
  Used in `.retrying` to identify which step is being retried.
- **`IDVerseFailureCategory`** (public enum) — sanitised error taxonomy:
  `cameraPermissionDenied`, `microphonePermissionDenied`, `webContentLoadFailed`,
  `transactionCreationFailed`,
  `resultFetchFailed`, `timedOut`, `cancelled`, `unknown`. `public init(_ error:
  Error)` maps any thrown error to a category without carrying the raw message.
  Used in `.retrying` and `.failed`.
- **`IDVerseEventEmitter`** (internal struct, `Sendable`) — the delivery
  mechanism. `init(_ observability: IDVerseObservability, category: String)`.
  `emit(_ event:)` delivers to the public handler (if any) AND writes a **redacted
  `os.Logger` breadcrumb**: `"\(event.name, privacy: .public) tx=\(id, privacy:
  .private)"` — the event name is `.public` (visible in Console.app), the
  transaction id is `.private` (redacted on device, visible only with a profile),
  nothing else is logged.

### Three-way event ownership (disjoint partition)

Each event is emitted by exactly one component, no gaps and no overlaps per run:

| Component | Events |
|---|---|
| **Orchestrator** | `.started`, `.transactionCreateStarted`, `.transactionCreateSucceeded`, `.resultFetchStarted`, `.resultPending`, `.resultPollingTimedOut`, `.completed`; `.retrying` via `withRetry` |
| **WebView controller** | `.presented`, `.webViewLoaded`, `.webContentProcessTerminated`, `.redirectMatched`, `.navigationBlocked` |
| **Facade** | `.cancelled`, `.failed` |

### PII by construction

Event associated values can only carry ids (`String`), the `Outcome` enum,
`IDVerseFailureCategory`, or integer counters. No URL, token, raw error message,
extracted document data, name, DOB, or vendor payload can appear in an event or
the OSLog line. This structural constraint — not a convention — is what lets a
compliance team assert the telemetry is PII-free.

To wire observability:

```swift
let config = IDVerseConfiguration(
    observability: .events { event in
        analytics.log(event.name, ["txId": event.transactionId ?? "-"])
    },
    webViewLoadTimeout: 30,
    resultPollingTimeout: 60,
    retryPolicy: .default)
try await IDVerse.runVerification(txConfig, using: service, from: vc, configuration: config)
```

With `.disabled` (the default), no handler runs — but the redacted `os.Logger`
breadcrumbs still emit, which is useful for debugging in Console.app.

---

## 10. Control-flow summaries

**Full lifecycle (`IDVerseVerificationFlow` / `runVerification`):**

```
viewDidAppear → runVerification
  → emit .started
  → (idempotency key generated)
  → emit .transactionCreateStarted
  → [withRetry] service.createTransaction → emit .transactionCreateSucceeded
  → emit .presented (controller, after camera grant)
  → present: show WKWebView → load url
  → user completes → main-frame redirect → emit .redirectMatched → WebFlowOutcome(.completed, id)
  → emit .resultFetchStarted
  → [withRetry] service.fetchResult → [poll while .pending] → emit .completed
  → IDVerseVerificationResult  (onFinish .success)
```

**Cancel paths:**
- User taps Close → `closeTapped` → `finish(.success(.cancelled))` → OneShotCompletion
  → orchestrator `guard .completed else throw .cancelled` → facade emits `.cancelled`
  → `onFinish(.failure(.cancelled))`.
- External Task cancel → `withTaskCancellationHandler` → `cancelFromOutside()` → same
  `finish(.success(.cancelled))` path.
- SwiftUI teardown → `dismantleUIViewController` → `task.cancel()` → same path.

**Dead URL:** load never finishes → watchdog (`webViewLoadTimeout`) →
`.webContentLoadFailed`.

**Transient network error:** `withRetry` catches, emits `.retrying`, sleeps
(exponential backoff), retries up to `maxAttempts`. Exhausted → throws.

**WebKit process crash:** `.webContentProcessTerminated` emitted → first crash
reloads; second crash → `.webContentLoadFailed`.

**Camera denied:** permission gate → `.cameraPermissionDenied`.

**Microphone denied:** permission gate → `.microphonePermissionDenied`.

**Result pending:** orchestrator polls up to `resultPollingTimeout` (backoff
1→2→4→5 s), emitting `.resultPending` before each poll. If still `.pending` at
deadline, emits `.resultPollingTimedOut` then `.completed` and returns the
`.pending` result — reconcile via webhook.

---

## 11. Build and test workflow

### Opening the SDK in Xcode

1. Open Xcode.
2. File → Open (⌘O).
3. Navigate to `ios-sdk/` and select `Package.swift`.

From there you can run the unit tests with Product → Test (⌘U).

### Terminal commands

```bash
# Run all logic tests (macOS host, no simulator needed)
cd ios-sdk
swift test

# Run a single test suite
swift test --filter IDVerseRedirectMatcherTests

# Verify macOS compilation (also guards the #if canImport(UIKit) boundary)
swift build

# Compile iOS-only code (WKWebView, UIKit)
xcodebuild -scheme IDVerseSDK -destination 'generic/platform=iOS' build

# Build the example app
xcodebuild \
  -project ios-sdk/Examples/IDVerseApp/IDVerseApp/IDVerseApp.xcodeproj \
  -scheme IDVerseApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

Adjust the simulator name to match one returned by `xcrun simctl list devices available`.

### SDK-developer troubleshooting

**`swift test` fails with a missing UIKit symbol**
The file importing `UIKit` or `WebKit` is not wrapped in `#if canImport(UIKit)`.
Add the guard — that is the intended compile boundary.

**"Module compiled with Swift X cannot be imported by Swift Y"**
Clean the build folder and ensure Xcode and the Swift toolchain versions match.

**`xcodebuild` for iOS fails with "No such module 'IDVerseSDK'"**
Verify the scheme resolves the local package. Opening `Package.swift` directly
and running the scheme from there is the simplest path.

---

## 12. Conventions and gotchas

- **`#if canImport(UIKit)`** on every UIKit/WebKit file, or you break `swift test`
  on the macOS host.
- **Public type / internal init** is the pattern for the controllers: the class
  must be `public` (SwiftUI representable return type) but the init stays
  `internal` so integrators go through the facade, and internal types like
  `WebFlowOutcome` do not leak into a public init's signature.
- **Delegate witnesses must be `public`** for public `@objc` protocol conformances
  (`WKNavigationDelegate`, `WKUIDelegate`).
- **Keep secrets out of `Source/`.** Transaction creation that needs a key belongs
  in the integrator's backend (`RemoteTransactionService`) or the example app
  (`DirectTransactionService`), never the SDK target.
- **`.pending` is not a failure.** Do not "fix" it by throwing — it is the
  documented contract; the webhook is authoritative.
- **Every public struct needs an explicit `public init`.** Swift's synthesised
  memberwise init is `internal`; without the explicit version an integrator in
  another module cannot construct the type.

---

## 13. Tests (`Tests/`)

The logic layer is unit-tested via `swift test` (59 tests as of the navigation
policy + origin header slice):

- `IDVerseModelTests` — model construction, `Outcome` raw values, equality, defaults.
- `IDVerseRedirectMatcherTests` — match/reject/extract, query tolerance.
- `TransactionServiceTests` — mock returns configured values; remote throws.
- `VerificationOrchestratorTests` — id selection (`??` fallback), cancellation skips
  fetch, retry/idempotency/poll behaviour, event sequence.
- `OriginAllowListTests` — host/subdomain/apex allowed, unrelated/nil denied.
- `IDVerseConfigurationTests` — default values, memberwise init, Sendable.
- `IDVerseEventTests` — all cases, `name` accessor, `transactionId` accessor.
- `IDVerseObservabilityTests` — `.disabled` delivers nothing; `.events` delivers to handler.
- `OneShotCompletionTests` — first-wins, subsequent calls dropped.
- `RetryRunnerTests` — attempts, backoff, jitter, `.retrying` events, cancellation propagation.
- `NavigationPolicyTests` — finishFlow/allow/block decisions, main-frame fail-closed
  gate, sub-frame unrestricted.
- `OriginHeaderStateTests` — loading/verified/unverified derivation, https-only.

The webview controller, SwiftUI wrappers, and facade are **build-verified** and
smoke-tested in the example app, because they require live WebKit.

**Testing strategy at a glance:**

| Scope | How |
|---|---|
| Foundation logic | `swift test` on macOS host — models, redirect matcher, orchestrator, services, allow-list. Fast, no simulator. |
| iOS UI | `xcodebuild -scheme IDVerseSDK -destination 'generic/platform=iOS'` + manual smoke test in the example app. WebKit must be live. |

---

## 14. Further development (roadmap)

The roadmap is ordered by dependency and value.

### Tier 0 — hygiene (done)

- Example app deployment target corrected to 15.0 (matches the SDK).
- Real camera + microphone usage strings.
- Docs accuracy — README, ARCHITECTURE, INTEGRATION_GUIDE rewritten for the
  webview SDK; stale native/FaceAccess docs removed.

### Tier 1 — enterprise foundation (no IDVerse access required)

1. **Privacy and compliance** — `PrivacyInfo.xcprivacy` manifest + App Store
   data-safety; screen-capture detection (`UIScreen.isCaptured` +
   `capturedDidChangeNotification` → obscure/pause the sensitive flow;
   `userDidTakeScreenshotNotification` → log/warn). iOS can **detect**, not
   **prevent**, screenshots in a normal app — do not overpromise prevention.
   Plus clear-on-cancel.
2. **Swift 6 strict concurrency** — `Sendable` conformances and an
   actor-isolation audit (the SDK is concurrency-sensitive: continuations,
   `@MainActor`).
3. **CI/CD** — GitHub Actions: `swift test` + iOS build matrix +
   SwiftLint/SwiftFormat quality gates.

### Tier 2 — real backend integration (gated on IDVerse access)

Not just "fill in a URL" — an auditable pipeline:

- Backend reference implementation (Store Transaction / Get Results proxy).
- Webhook signature verification.
- Retry policy (bounded, backoff, dead-letter).
- Result state machine (`pending → finalizing → final`).
- Audit logging.
- Data-retention boundaries.
- Typed result contracts — decode the real Get Results schema.
- TLS pinning for integrator-backend calls — opt-in, off by default, with backup
  pins and a rotation policy. Never applied to the IDVerse webview (outside the
  integrator's control).

### Tier 3 — distribution and scale

- SemVer tags, `CHANGELOG`, optional XCFramework binary / CocoaPods.
- DocC documentation.
- API maturity — async/await + a completion-handler API.
- Accessibility/UX — VoiceOver on the native chrome, localization, themeable
  loader/close/error.
- Broader testing — XCUITest smoke of present/cancel/timeout paths.

---

## 15. Current status

- The **transaction API is stubbed** (`RemoteTransactionService` throws
  `IDVerseError.…Failed(IDVerseNotImplemented(…))`) — wiring a real backend
  (Store Transaction / Get Results / webhook) is the gating piece for live
  verification. The seam is ready; see the Tier 2 roadmap.
- The **observability + resilience slice** (events, retry/backoff, polling,
  process recovery, cancellation, `IDVerseConfiguration`) is **complete and
  merged to `main`**.
- The **trust-hardening slice** (fail-closed `NavigationPolicy` main-frame gate,
  live origin header, opt-in App-Bound Domains) is **complete and merged to
  `main`**. All 59 unit tests pass; iOS and macOS builds are warning-free. A
  manual smoke test of the origin header on a real device is the remaining
  verification step.
- **No SemVer tags, no `CHANGELOG`, no Package version yet** — versioning and
  distribution are a Tier 3 item. The working integration form is
  `.package(path: "../ios-sdk")`.
