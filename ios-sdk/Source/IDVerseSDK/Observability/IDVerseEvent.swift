import Foundation

public enum IDVerseOperation: String, Sendable { case createTransaction, fetchResult }

public enum IDVerseFailureCategory: String, Sendable {
    case cameraPermissionDenied, microphonePermissionDenied, webContentLoadFailed,
         transactionCreationFailed, resultFetchFailed, timedOut, cancelled, unknown

    public init(_ error: Error) {
        if #available(iOS 13.0, macOS 10.15, *) {
            if error is CancellationError { self = .cancelled; return }
        }
        switch error {
        case IDVerseError.cancelled: self = .cancelled
        case IDVerseError.cameraPermissionDenied: self = .cameraPermissionDenied
        case IDVerseError.microphonePermissionDenied: self = .microphonePermissionDenied
        case IDVerseError.transactionCreationFailed: self = .transactionCreationFailed
        case IDVerseError.resultFetchFailed: self = .resultFetchFailed
        case IDVerseError.webContentLoadFailed(let underlying):
            self = (underlying as NSError).code == NSURLErrorTimedOut ? .timedOut : .webContentLoadFailed
        case IDVerseError.invalidTransactionURL:
            self = .unknown
        default:
            self = .unknown
        }
    }
}

/// PII-safe lifecycle events. Payloads carry only ids/outcomes/categories/counters.
public enum IDVerseEvent: Sendable {
    case started
    case transactionCreateStarted
    case transactionCreateSucceeded(transactionId: String)
    case presented(transactionId: String?)
    case webViewLoaded(transactionId: String?)
    case webContentProcessTerminated(transactionId: String?)
    case redirectMatched(transactionId: String?)
    /// A main-frame navigation to an origin outside the allow-list was cancelled.
    /// Carries no URL/host by design (PII rule) — the flow keeps running.
    case navigationBlocked(transactionId: String?)
    case resultFetchStarted(transactionId: String)
    case retrying(operation: IDVerseOperation, attempt: Int, maxAttempts: Int, reason: IDVerseFailureCategory)
    case resultPending(transactionId: String)
    case resultPollingTimedOut(transactionId: String)
    case completed(transactionId: String, outcome: IDVerseVerificationResult.Outcome)
    case cancelled(transactionId: String?)
    case failed(reason: IDVerseFailureCategory, transactionId: String?)
}
