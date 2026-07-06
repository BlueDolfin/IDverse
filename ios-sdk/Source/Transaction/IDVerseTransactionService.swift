import Foundation

/// Supplies the transaction lifecycle. Keeps IDVerse secrets out of the SDK:
/// production implementations call the integrator's backend, which proxies IDVerse.
public protocol IDVerseTransactionService {
    func createTransaction(_ config: TransactionConfig) async throws -> IDVerseTransaction
    func fetchResult(transactionId: String) async throws -> IDVerseVerificationResult
}

/// Marker error for unfinished scaffolds.
struct IDVerseNotImplemented: Error {
    let detail: String
}
