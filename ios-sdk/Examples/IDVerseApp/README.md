# IDVerseApp — Example App

SwiftUI test app for the IDVerseSDK Swift Package. It consumes the SDK via a local SPM dependency and is the primary way to manually smoke-test the webview flow and result UI.

## What it does

The app's `StartView` provides two paths:

- **Run verification flow** — paste a real IDVerse transaction URL and tap the button. The SDK presents a full-screen `WKWebView` running IDVerse's hosted journey (consent → capture → OCR → confirm → liveness → complete). On completion the result screen shows the outcome and any extracted data.
- **Preview result screen (mock)** — skips the webview entirely; `MockTransactionService` returns canned data so you can develop and test the result UI without credentials or a real transaction.

## Setup

### 1. Open the project

Open `IDVerseApp/IDVerseApp.xcodeproj` in Xcode.

### 2. Confirm the local SDK dependency

The project references the IDVerseSDK package locally. If Xcode shows a missing-package error:

1. File → Add Package Dependencies → Add Local
2. Select the `ios-sdk/` directory (one level above `Examples/`)
3. Add the `IDVerseSDK` library to the `IDVerseApp` target

### 3. Select a destination

Choose any iOS 15+ simulator or a connected device. The webview flow and camera require a real device for full functionality; the simulator can run the mock path.

### 4. Build and run (⌘R)

No credentials are needed to launch. Use the mock path to exercise the UI immediately.

## Architecture

```
IDVerseApp/
├── StartView.swift                 # Entry: paste URL or choose mock
├── ResultDisplayView.swift         # Displays IDVerseVerificationResult
├── DirectTransactionService.swift  # Test-only sandbox service (app target)
└── IDVerseApp.swift                # @main app entry
```

The app uses `IDVerseVerificationFlow` (full lifecycle: create → present → fetch) from the SDK. `MockTransactionService` is the default transaction service; swap in `RemoteTransactionService` to point at a real backend, or use `DirectTransactionService` (in the test target only) to call the IDVerse sandbox directly during development.

> **Security:** `DirectTransactionService` exists only in the app/test target and holds sandbox credentials. It must never be used in a distributed build. Production apps must use `RemoteTransactionService` backed by your own server — secrets must not live in the app.

## Info.plist

Camera and microphone usage strings are already configured. They are required because IDVerse's web flow requests camera and microphone access via the browser API inside the WKWebView.

## Current status

The transaction API is **stubbed**. `RemoteTransactionService` throws `notImplemented` until a real backend is wired in. To see the live IDVerse journey:

1. Obtain a real transaction URL from the IDVerse sandbox (via your backend calling Store Transaction).
2. Paste it into the "Run verification flow" field and tap the button.

Without a real URL, use "Preview result screen (mock)" to verify the result UI.

## SDK documentation

See the [iOS Integration Guide](../../Documentation/INTEGRATION_GUIDE.md) for the full public API reference and integration steps.
