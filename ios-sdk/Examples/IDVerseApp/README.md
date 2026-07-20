# IDVerseApp — Example App: how to use and test it

SwiftUI test app for this package's two library products, consumed via a local
SPM dependency. It is the primary way to manually smoke-test both:

- **IDVerseSDK** — the full verification lifecycle (create → present webview →
  result): *Run verification flow* and *Preview result screen (mock)*.
- **LiteWebView** — the reusable controlled-webview core and its web→native
  bridge: *Bridge demo*.

## Setup

### 1. Open the project

Open `IDVerseApp/IDVerseApp.xcodeproj` in Xcode.

### 2. Confirm the local SDK dependency

The project references the package locally, linking both the `IDVerseSDK` and
`LiteWebView` products. If Xcode shows a missing-package error:

1. File → Add Package Dependencies → Add Local
2. Select the `ios-sdk/` directory (one level above `Examples/`)
3. Add both the `IDVerseSDK` and `LiteWebView` libraries to the `IDVerseApp` target

### 3. Select a destination

Any iOS 15+ simulator or connected device. The real IDVerse journey needs a
physical device (document capture and liveness need a real camera); the mock
path and the bridge demo run fine on any simulator.

### 4. Build and run (⌘R)

No credentials are needed to launch. Command-line build:

```bash
xcodebuild -project IDVerseApp/IDVerseApp.xcodeproj -scheme IDVerseApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

If the bare device name resolves to an unavailable OS, pin one (e.g.
`name=iPhone 16,OS=18.5`) — pick from `xcrun simctl list devices available`.

## The three demos on the start screen

### 1. Run verification flow (IDVerseSDK)

Loads a real IDVerse transaction URL in the SDK's controlled webview and runs
the hosted journey (consent → capture → OCR → confirm → liveness → complete).

**You need a real transaction URL.** Transactions are created server-side via
IDVerse's Store Transaction API; the app deliberately contains no API secrets.
Obtain a URL from your backend or IDVerse staging environment and either paste
it into the text field, or prefill it via the run scheme (Product → Scheme →
Edit Scheme → Run → Environment Variables):

- `IDVERSE_TX_URL` — transaction URL to prefill;
- `IDVERSE_REDIRECT` — optional completion-redirect override (default
  `idverse-sdk://complete`; must match the redirect the transaction was
  created with).

What to expect when it works:

1. Camera and microphone permission prompts — both are pre-flighted; denying
   either fails the flow immediately with a typed error.
2. The webview opens full screen with the **trust bar**: a green lock plus the
   current host once an allow-listed https page loads.
3. Navigation to any origin outside the allow-list is blocked (the flow keeps
   running on its current page). Plain-HTTP is always blocked.
4. When the journey ends, IDVerse navigates to the redirect URL; the SDK
   intercepts it, closes the webview, and the result screen appears.

Note: the app wires the flow through `MockTransactionService`, so the
*displayed result* is canned demo data even after a real journey — real
results need a backend (`RemoteTransactionService`, or the
`DirectTransactionService` scaffold for sandbox development).

### 2. Preview result screen (mock)

Renders the result UI with canned data — no webview, no network, no
credentials. Use it to develop and verify the result screen instantly.

### 3. Bridge demo (LiteWebView)

A bundled local page (`bridge-demo.html`) registered as the container's single
trusted `bundledBridgePage`, plus a native `greet` flow. Manual test checklist:

1. Open **Bridge demo** → the local page loads (the exact bundled-page
   exception at work; any other `file:` URL would be blocked).
2. Tap **Run native "greet" flow** → native sheet appears; tap **Return to web
   page** → the page shows `resolved: {"greeting":"Hello"}` — the
   request/response round trip.
3. Run again and **swipe the sheet down** → `rejected: code=cancelled …` —
   interactive dismissal rejects the page's promise and releases the flow lock.
4. Tap run **twice quickly** → second call shows `rejected: code=busy …` —
   one native flow at a time, container-wide.
5. Go back and confirm the verification demo still behaves as before.

## Automated tests

Package logic tests run on the macOS host — no simulator needed:

```bash
cd ../..            # ios-sdk/
swift test          # full suite: LiteWebViewTests + IDVerseSDKTests
```

Compile checks for the iOS-only (WebKit/UIKit) code and this app:

```bash
xcodebuild -scheme IDVerseSDK -destination 'generic/platform=iOS' build
xcodebuild -project Examples/IDVerseApp/IDVerseApp/IDVerseApp.xcodeproj \
  -scheme IDVerseApp -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Behavior that needs live WebKit (script injection, reply handlers,
`loadFileURL`) is verified by the manual checklists above by design; all pure
logic (navigation policy, origin matching, envelope/codec, locking,
bundled-page validation) is covered by `swift test`.

## Architecture

```
IDVerseApp/
├── StartView.swift                 # Entry: paste URL, mock preview, bridge demo
├── ResultDisplayView.swift         # Displays IDVerseVerificationResult
├── BridgeDemoView.swift            # LiteWebView container + native greet flow
├── bridge-demo.html                # Bundled page calling executeNativeFlow
├── DirectTransactionService.swift  # Test-only sandbox service (app target)
└── IDVerseApp.swift                # @main app entry
```

> **Security:** `DirectTransactionService` exists only in the app target and
> would hold sandbox credentials. It must never ship in a distributed build.
> Production apps must use `RemoteTransactionService` backed by your own
> server — secrets must not live in the app.

## Info.plist

Camera and microphone usage strings are already configured — IDVerse's web
flow requests both via the browser API inside the WKWebView.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Spinner, then "The verification page did not load" after ~30 s | Placeholder/expired/unreachable transaction URL — the first-load watchdog fired. Paste a fresh, real URL. |
| Flow fails immediately with a camera/microphone error | Permission denied. Re-enable in Settings → Privacy, or `xcrun simctl privacy booted reset all`. |
| A page inside the journey won't open | Its origin is off the allow-list — the navigation gate working as designed. |
| Trust bar shows "Origin not verified" | Top-level page isn't an allow-listed https origin. Expected for `file:` pages, which is why the bridge demo hides the trust bar. |
| Capture/liveness won't complete on a simulator | Expected — use a physical device for the real journey. |
| Build can't find the simulator | Pin the OS in the destination, e.g. `name=iPhone 16,OS=18.5`. |

## SDK documentation

See the [iOS Integration Guide](../../Documentation/INTEGRATION_GUIDE.md) for
the full public API reference and the
[iOS Developer Guide](../../Documentation/DEVELOPER_GUIDE.md) for architecture
internals.
