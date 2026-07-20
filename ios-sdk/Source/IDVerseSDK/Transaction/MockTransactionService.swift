import Foundation

/// Canned transaction + result so the full flow and the test app run with no backend.
public final class MockTransactionService: IDVerseTransactionService {
    private let transaction: IDVerseTransaction
    private let result: IDVerseVerificationResult

    public init(transaction: IDVerseTransaction, result: IDVerseVerificationResult) {
        self.transaction = transaction
        self.result = result
    }

    public func createTransaction(_ config: TransactionConfig) async throws -> IDVerseTransaction {
        transaction
    }

    public func fetchResult(transactionId: String) async throws -> IDVerseVerificationResult {
        result
    }
}
