import XCTest
import LiteWebView
@testable import IDVerseSDK

final class IDVerseAllowListTests: XCTestCase {
    private let list = IDVerseAllowList.make(
        transactionURL: URL(string: "https://verify.idkit.co/t/abc")!)

    private func origin(_ url: String) -> WebOrigin? { WebOrigin(url: URL(string: url)!) }

    func test_allows_transactionHost() {
        XCTAssertTrue(list.allows(origin("https://verify.idkit.co/x")))
    }
    func test_allows_knownIDVerseSubdomain() {
        XCTAssertTrue(list.allows(origin("https://cdn.idverse.com/x")))
    }
    func test_allows_apexDomain() {
        XCTAssertTrue(list.allows(origin("https://idkit.co/")))
        XCTAssertTrue(list.allows(origin("https://idverse.com/")))
    }
    func test_denies_unrelatedHost() {
        XCTAssertFalse(list.allows(origin("https://evil.example.com/")))
    }
    func test_denies_plainHTTP_documentedTightening() {
        // Spec §7: the one deliberate behavior change — http was accepted before, no longer.
        XCTAssertFalse(list.allows(origin("http://verify.idkit.co/x")))
    }
}
