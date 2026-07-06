import XCTest
@testable import IDVerseSDK

final class MediaOriginAllowListTests: XCTestCase {
    private let list = MediaOriginAllowList(
        transactionURL: URL(string: "https://verify.idkit.co/t/abc")!)

    func test_allows_transactionHost() {
        XCTAssertTrue(list.allows(host: "verify.idkit.co"))
    }
    func test_allows_knownIDVerseSubdomain() {
        XCTAssertTrue(list.allows(host: "cdn.idverse.com"))
    }
    func test_allows_apexDomain() {
        // Documents intent: the IDVerse apex domains are allowed, not just subdomains.
        XCTAssertTrue(list.allows(host: "idkit.co"))
        XCTAssertTrue(list.allows(host: "idverse.com"))
    }
    func test_denies_unrelatedHost() {
        XCTAssertFalse(list.allows(host: "evil.example.com"))
    }
    func test_denies_nilOrEmpty() {
        XCTAssertFalse(list.allows(host: nil))
        XCTAssertFalse(list.allows(host: ""))
    }
}
