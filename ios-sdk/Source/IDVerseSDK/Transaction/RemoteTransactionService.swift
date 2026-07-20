import Foundation

/// Production path: calls the integrator's backend, which proxies IDVerse Store Transaction / Get Results.
/// SCAFFOLD — wire to the real backend contract once available.
public final class RemoteTransactionService: IDVerseTransactionService {
    private let backendBaseURL: URL
    private let session: URLSession

    public init(backendBaseURL: URL, session: URLSession = .shared) {
        self.backendBaseURL = backendBaseURL
        self.session = session
    }

    public func createTransaction(_ config: TransactionConfig) async throws -> IDVerseTransaction {
        // TODO: POST {backendBaseURL}/idverse/transactions with config; decode { id, url, redirectURL }.
        throw IDVerseError.transactionCreationFailed(IDVerseNotImplemented(detail: "RemoteTransactionService.createTransaction"))
    }

    public func fetchResult(transactionId: String) async throws -> IDVerseVerificationResult {
        // TODO: GET {backendBaseURL}/idverse/transactions/{transactionId}/result; map to IDVerseVerificationResult.
        throw IDVerseError.resultFetchFailed(IDVerseNotImplemented(detail: "RemoteTransactionService.fetchResult"))
    }
}
