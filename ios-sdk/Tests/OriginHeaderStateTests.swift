import XCTest
@testable import IDVerseSDK

final class OriginHeaderStateTests: XCTestCase {
    private let allowList = OriginAllowList(transactionURL: URL(string: "https://verify.idkit.co/t/abc")!)

    func test_loading_whenNoURLYet() {
        XCTAssertEqual(OriginHeaderState.derive(url: nil, allowList: allowList), .loading)
    }
    func test_loading_forAboutBlank() {
        XCTAssertEqual(OriginHeaderState.derive(url: URL(string: "about:blank"), allowList: allowList), .loading)
    }
    func test_verified_httpsAllowedHost_lowercased() {
        XCTAssertEqual(OriginHeaderState.derive(url: URL(string: "https://Verify.IDKit.co/step/2"), allowList: allowList),
                       .verified(host: "verify.idkit.co"))
    }
    func test_unverified_httpsUnknownHost() {
        XCTAssertEqual(OriginHeaderState.derive(url: URL(string: "https://evil.example.com/x"), allowList: allowList),
                       .unverified)
    }
    func test_unverified_plainHTTPEvenOnAllowedHost() {
        // The lock implies TLS; http is never "verified".
        XCTAssertEqual(OriginHeaderState.derive(url: URL(string: "http://verify.idkit.co/x"), allowList: allowList),
                       .unverified)
    }
}
