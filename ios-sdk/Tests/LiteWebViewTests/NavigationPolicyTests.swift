import XCTest
@testable import LiteWebView

final class NavigationPolicyTests: XCTestCase {
    private let allowList = OriginAllowList(entries: [.exact(host: "verify.example.org", port: 443)])
    private lazy var policy = NavigationPolicy(
        completionRule: RedirectCompletionRule(redirectURL: URL(string: "idverse-sdk://complete")!),
        allowList: allowList)

    // Regression guard (spec §5a): a custom-scheme completion redirect must finish the
    // flow even though the https-only allow-list would block it.
    func test_finishesFlow_customSchemeRedirect_beforeAllowList() {
        let url = URL(string: "idverse-sdk://complete?transactionId=t1")!
        XCTAssertEqual(policy.decide(url: url, isMainFrame: true), .finishFlow(url))
    }
    func test_allows_listedHTTPSHost() {
        XCTAssertEqual(policy.decide(url: URL(string: "https://verify.example.org/s/2")!, isMainFrame: true), .allow)
    }
    func test_blocks_unlistedHost() {
        XCTAssertEqual(policy.decide(url: URL(string: "https://evil.example.com/x")!, isMainFrame: true), .block)
    }
    func test_blocks_plainHTTP_onListedHost() {
        // Spec §7: the one deliberate behavior change.
        XCTAssertEqual(policy.decide(url: URL(string: "http://verify.example.org/x")!, isMainFrame: true), .block)
    }
    func test_allows_subframesUnrestricted() {
        XCTAssertEqual(policy.decide(url: URL(string: "https://evil.example.com/frame")!, isMainFrame: false), .allow)
    }
    func test_allows_aboutBlank() {
        XCTAssertEqual(policy.decide(url: URL(string: "about:blank")!, isMainFrame: true), .allow)
    }
    func test_blocks_nonHTTPSchemes() {
        XCTAssertEqual(policy.decide(url: URL(string: "mailto:x@example.com")!, isMainFrame: true), .block)
        XCTAssertEqual(policy.decide(url: URL(string: "tel:+123")!, isMainFrame: true), .block)
    }
    func test_blocks_nilURL() {
        XCTAssertEqual(policy.decide(url: nil, isMainFrame: true), .block)
    }

    // Bundled-page cases (spec §5a step 3 + §9).
    func test_allows_exactBundledPage() {
        let page = URL(fileURLWithPath: "/app/bundle/bridge-demo.html")
        let p = NavigationPolicy(
            completionRule: RedirectCompletionRule(redirectURL: URL(string: "x://done")!),
            allowList: allowList, bundledPage: page)
        XCTAssertEqual(p.decide(url: URL(fileURLWithPath: "/app/bundle/bridge-demo.html"), isMainFrame: true), .allow)
    }
    func test_blocks_siblingFileInSameDirectory() {
        let page = URL(fileURLWithPath: "/app/bundle/bridge-demo.html")
        let p = NavigationPolicy(
            completionRule: RedirectCompletionRule(redirectURL: URL(string: "x://done")!),
            allowList: allowList, bundledPage: page)
        XCTAssertEqual(p.decide(url: URL(fileURLWithPath: "/app/bundle/other.html"), isMainFrame: true), .block)
    }
    func test_blocks_anyFileURL_whenNoBundledPageConfigured() {
        XCTAssertEqual(policy.decide(url: URL(fileURLWithPath: "/tmp/x.html"), isMainFrame: true), .block)
    }

    func test_finishesFlow_fileSchemeRedirect_beforeBundledPageBlock() {
        // Ordering guard: step 1 (completion rule) must also win over step 3's
        // file: handling — a file-scheme completion redirect finishes the flow
        // even though no bundledPage is configured and file: URLs are otherwise blocked.
        let redirect = URL(fileURLWithPath: "/done/complete.html")
        let p = NavigationPolicy(
            completionRule: RedirectCompletionRule(redirectURL: redirect),
            allowList: allowList)
        XCTAssertEqual(p.decide(url: URL(fileURLWithPath: "/done/complete.html"), isMainFrame: true),
                       .finishFlow(URL(fileURLWithPath: "/done/complete.html")))
    }
}
