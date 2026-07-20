import XCTest
@testable import LiteWebView

final class RedirectCompletionRuleTests: XCTestCase {
    private let rule = RedirectCompletionRule(redirectURL: URL(string: "idverse-sdk://complete")!)

    func test_matches_returnsFullURLWithQuery() {
        let url = URL(string: "idverse-sdk://complete?transactionId=t1&x=2")!
        XCTAssertEqual(rule.evaluate(url), .complete(matchedURL: url))
    }
    func test_caseInsensitiveSchemeAndHost() {
        let url = URL(string: "IDVERSE-SDK://COMPLETE")!
        XCTAssertEqual(rule.evaluate(url), .complete(matchedURL: url))
    }
    func test_differentPath_noMatch() {
        XCTAssertEqual(rule.evaluate(URL(string: "idverse-sdk://complete/extra")!), .continueFlow)
    }
    func test_differentScheme_noMatch() {
        XCTAssertEqual(rule.evaluate(URL(string: "https://complete")!), .continueFlow)
    }

    // Effective-port cases (spec §5): same host, different port must NOT complete the flow.
    func test_httpsDefaultPortMatchesExplicit443() {
        let r = RedirectCompletionRule(redirectURL: URL(string: "https://app.example.com/done")!)
        XCTAssertEqual(r.evaluate(URL(string: "https://app.example.com:443/done?ok=1")!),
                       .complete(matchedURL: URL(string: "https://app.example.com:443/done?ok=1")!))
    }
    func test_nonDefaultPort_noMatch() {
        let r = RedirectCompletionRule(redirectURL: URL(string: "https://app.example.com/done")!)
        XCTAssertEqual(r.evaluate(URL(string: "https://app.example.com:8443/done")!), .continueFlow)
    }
    func test_portlessCustomScheme_bothSidesPortless() {
        XCTAssertEqual(rule.evaluate(URL(string: "idverse-sdk://complete:9999")!), .continueFlow)
    }
}
