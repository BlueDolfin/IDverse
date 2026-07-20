import Foundation

/// IDVerse's half of the old redirect matcher: interpret the completion URL the core
/// hands back (transactionId may be canonicalized in the exit redirect).
enum IDVerseRedirectParser {
    static func transactionId(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "transactionId" || $0.name == "transaction_id" }?
            .value
    }
}
