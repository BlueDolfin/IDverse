import XCTest
@testable import IDVerseSDK

final class IDVerseRedirectMatcherTests: XCTestCase {
    let redirect = URL(string: "idverse-sdk://complete")!
    var matcher: IDVerseRedirectMatcher { IDVerseRedirectMatcher(redirectURL: redirect) }

    func test_matchesExactRedirect_noQuery() {
        let m = matcher.match(URL(string: "idverse-sdk://complete")!)
        XCTAssertNotNil(m)
        XCTAssertNil(m?.transactionId)
    }

    func test_matchesRedirect_withTransactionIdQuery() {
        let m = matcher.match(URL(string: "idverse-sdk://complete?transactionId=tx_123")!)
        XCTAssertEqual(m?.transactionId, "tx_123")
    }

    func test_matchesRedirect_withSnakeCaseQuery() {
        let m = matcher.match(URL(string: "idverse-sdk://complete?transaction_id=tx_9")!)
        XCTAssertEqual(m?.transactionId, "tx_9")
    }

    func test_matchesRedirect_ignoresUnrelatedQueryParams() {
        // A matching redirect with extra/unrelated query params still matches (query is ignored
        // for the match decision); transactionId is nil when no id param is present.
        let m = matcher.match(URL(string: "idverse-sdk://complete?foo=bar&baz=1")!)
        XCTAssertNotNil(m)
        XCTAssertNil(m?.transactionId)
    }

    func test_doesNotMatch_differentScheme() {
        XCTAssertNil(matcher.match(URL(string: "https://complete")!))
    }

    func test_doesNotMatch_differentHost() {
        XCTAssertNil(matcher.match(URL(string: "idverse-sdk://cancel")!))
    }

    func test_doesNotMatch_idverseJourneyURL() {
        XCTAssertNil(matcher.match(URL(string: "https://idkit.co/t/abc/step")!))
    }

    func test_doesNotMatch_nil() {
        XCTAssertNil(matcher.match(nil))
    }

    // Guard the path comparison against drift: URL.path normalizes a trailing slash away,
    // so both forms of the configured redirect match.
    func test_matches_trailingSlashVariant() {
        let m = IDVerseRedirectMatcher(redirectURL: URL(string: "https://example.com/done")!)
        XCTAssertNotNil(m.match(URL(string: "https://example.com/done/")!))
    }

    func test_matches_percentEncodedEquivalentPath() {
        // URL.path percent-decodes, so an encoding-only difference still matches.
        let m = IDVerseRedirectMatcher(redirectURL: URL(string: "https://example.com/done-now")!)
        XCTAssertNotNil(m.match(URL(string: "https://example.com/done%2Dnow")!))
    }
}
