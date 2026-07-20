import XCTest
@testable import IDVerseSDK

final class IDVerseConfigurationTests: XCTestCase {
    func test_defaults() {
        let c = IDVerseConfiguration.default
        XCTAssertEqual(c.webViewLoadTimeout, 30)
        XCTAssertEqual(c.resultPollingTimeout, 60)
        XCTAssertEqual(c.retryPolicy.maxAttempts, 3)
    }
    func test_transactionConfig_idempotencyKeyDefaultsEmpty() {
        let cfg = TransactionConfig(redirectURL: URL(string: "idverse-sdk://complete")!)
        XCTAssertEqual(cfg.idempotencyKey, "")
    }
    func test_request_transactionIdDefaultsNil() {
        let r = IDVerseVerificationRequest(transactionURL: URL(string: "https://idkit.co/t")!,
                                           redirectURL: URL(string: "idverse-sdk://complete")!)
        XCTAssertNil(r.transactionId)
    }
    func test_appBoundDomains_defaultsOff() {
        // Opt-in only: enabling it without WKAppBoundDomains in the HOST app's
        // Info.plist blocks all navigation, so the SDK must never default it on.
        XCTAssertFalse(IDVerseConfiguration.default.limitsNavigationsToAppBoundDomains)
        XCTAssertTrue(IDVerseConfiguration(limitsNavigationsToAppBoundDomains: true)
            .limitsNavigationsToAppBoundDomains)
    }
}
