import XCTest
@testable import IDVerseSDK

final class TransactionServiceTests: XCTestCase {
    func test_mock_returnsConfiguredTransactionAndResult() async throws {
        let tx = IDVerseTransaction(
            id: "tx_1",
            url: URL(string: "https://idkit.co/t/abc")!,
            redirectURL: URL(string: "idverse-sdk://complete")!)
        let result = IDVerseVerificationResult(transactionId: "tx_1", outcome: .passed)
        let service = MockTransactionService(transaction: tx, result: result)

        let created = try await service.createTransaction(
            TransactionConfig(redirectURL: URL(string: "idverse-sdk://complete")!))
        let fetched = try await service.fetchResult(transactionId: "tx_1")

        XCTAssertEqual(created, tx)
        XCTAssertEqual(fetched, result)
    }

    func test_remote_isNotImplementedYet() async {
        let service = RemoteTransactionService(backendBaseURL: URL(string: "https://example.com")!)
        do {
            _ = try await service.createTransaction(
                TransactionConfig(redirectURL: URL(string: "idverse-sdk://complete")!))
            XCTFail("expected error")
        } catch IDVerseError.transactionCreationFailed(_) {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
