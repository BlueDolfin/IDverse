import Foundation

/// Internal result of presenting the webview: the webview-level status plus the
/// transactionId parsed from the exit-redirect (IDVerse may canonicalize the id there).
struct WebFlowOutcome: Equatable {
    let status: IDVerseStatus
    let transactionId: String?
}
