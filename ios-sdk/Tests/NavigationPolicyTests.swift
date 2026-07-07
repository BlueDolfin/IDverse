import XCTest
@testable import IDVerseSDK

final class NavigationPolicyTests: XCTestCase {
    private let policy = NavigationPolicy(
        matcher: IDVerseRedirectMatcher(redirectURL: URL(string: "idverse-sdk://complete")!),
        allowList: OriginAllowList(transactionURL: URL(string: "https://verify.idkit.co/t/abc")!))

    func test_finishesFlow_onRedirectMatch_mainFrame() {
        XCTAssertEqual(
            policy.decide(url: URL(string: "idverse-sdk://complete?transactionId=t1"), isMainFrame: true),
            .finishFlow(IDVerseRedirectMatcher.Match(transactionId: "t1")))
    }
    func test_allows_transactionHost_mainFrame() {
        XCTAssertEqual(policy.decide(url: URL(string: "https://verify.idkit.co/step/2"), isMainFrame: true), .allow)
    }
    func test_allows_knownIDVerseHost_mainFrame() {
        XCTAssertEqual(policy.decide(url: URL(string: "https://cdn.idverse.com/page"), isMainFrame: true), .allow)
    }
    func test_blocks_unknownHost_mainFrame() {
        XCTAssertEqual(policy.decide(url: URL(string: "https://evil.example.com/phish"), isMainFrame: true), .block)
    }
    func test_allows_anySubframeNavigation() {
        // Subresources/iframes (CDNs, analytics) must not be broken; the main frame is the trust surface.
        XCTAssertEqual(policy.decide(url: URL(string: "https://evil.example.com/frame"), isMainFrame: false), .allow)
    }
    func test_allows_aboutBlank_mainFrame() {
        // WebKit-internal initial document.
        XCTAssertEqual(policy.decide(url: URL(string: "about:blank"), isMainFrame: true), .allow)
    }
    func test_blocks_nonHTTPSchemes_mainFrame() {
        XCTAssertEqual(policy.decide(url: URL(string: "mailto:x@example.com"), isMainFrame: true), .block)
        XCTAssertEqual(policy.decide(url: URL(string: "tel:+1234567890"), isMainFrame: true), .block)
    }
    func test_blocks_nilURL_mainFrame() {
        XCTAssertEqual(policy.decide(url: nil, isMainFrame: true), .block)
    }
}
