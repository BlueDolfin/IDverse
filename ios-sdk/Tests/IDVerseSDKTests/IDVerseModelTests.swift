import XCTest
@testable import IDVerseSDK

final class IDVerseModelTests: XCTestCase {
    func test_outcome_rawValues() {
        XCTAssertEqual(IDVerseVerificationResult.Outcome.passed.rawValue, "passed")
        XCTAssertEqual(IDVerseVerificationResult.Outcome.failed.rawValue, "failed")
        XCTAssertEqual(IDVerseVerificationResult.Outcome.refer.rawValue, "refer")
        XCTAssertEqual(IDVerseVerificationResult.Outcome.pending.rawValue, "pending")
    }

    func test_request_defaultsShowsCloseButtonTrue() {
        let req = IDVerseVerificationRequest(
            transactionURL: URL(string: "https://idkit.co/t/abc")!,
            redirectURL: URL(string: "idverse-sdk://complete")!)
        XCTAssertTrue(req.showsCloseButton)
    }

    func test_result_equatable() {
        let a = IDVerseVerificationResult(transactionId: "1", outcome: .passed)
        let b = IDVerseVerificationResult(transactionId: "1", outcome: .passed)
        XCTAssertEqual(a, b)
    }

    func test_transactionConfig_defaultFlowType() {
        let cfg = TransactionConfig(redirectURL: URL(string: "idverse-sdk://complete")!)
        XCTAssertEqual(cfg.flowType, "single_doc")
    }

    func test_request_defaultsShowsOriginHeaderTrue() {
        let req = IDVerseVerificationRequest(
            transactionURL: URL(string: "https://idkit.co/t")!,
            redirectURL: URL(string: "idverse-sdk://complete")!)
        XCTAssertTrue(req.showsOriginHeader)
    }
}
