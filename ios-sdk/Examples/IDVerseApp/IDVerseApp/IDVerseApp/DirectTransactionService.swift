import Foundation
import IDVerseSDK

/// TEST/SANDBOX ONLY, lives in the app (never the SDK): direct IDVerse calls with sandbox creds.
/// SCAFFOLD — wire to the real IDVerse Store Transaction / Get Results once the API reference exists.
final class DirectTransactionService: IDVerseTransactionService {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func createTransaction(_ config: TransactionConfig) async throws -> IDVerseTransaction {
        // TODO: POST {baseURL}/transactions (Store Transaction), Authorization: Bearer apiKey.
        throw IDVerseError.transactionCreationFailed(NSError(domain: "DirectTransactionService", code: -1))
    }

    func fetchResult(transactionId: String) async throws -> IDVerseVerificationResult {
        // TODO: GET {baseURL}/transactions/{transactionId} (Get Results); poll until finalized or timeout.
        throw IDVerseError.resultFetchFailed(NSError(domain: "DirectTransactionService", code: -1))
    }
}
