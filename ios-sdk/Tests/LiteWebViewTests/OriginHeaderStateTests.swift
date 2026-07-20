import XCTest
@testable import LiteWebView

final class OriginHeaderStateTests: XCTestCase {
    private let allowList = OriginAllowList(entries: [.exact(host: "verify.example.org", port: 443)])

    func test_loading_whenNoURLYet() {
        XCTAssertEqual(OriginHeaderState.derive(url: nil, allowList: allowList), .loading)
    }
    func test_loading_forAboutBlank() {
        XCTAssertEqual(OriginHeaderState.derive(url: URL(string: "about:blank"), allowList: allowList), .loading)
    }
    func test_verified_httpsAllowedHost_lowercased() {
        XCTAssertEqual(OriginHeaderState.derive(url: URL(string: "https://Verify.Example.ORG/step/2"), allowList: allowList),
                       .verified(host: "verify.example.org"))
    }
    func test_unverified_httpsUnknownHost() {
        XCTAssertEqual(OriginHeaderState.derive(url: URL(string: "https://evil.example.com/x"), allowList: allowList),
                       .unverified)
    }
    func test_unverified_plainHTTPEvenOnAllowedHost() {
        XCTAssertEqual(OriginHeaderState.derive(url: URL(string: "http://verify.example.org/x"), allowList: allowList),
                       .unverified)
    }
    func test_unverified_portMismatch() {
        XCTAssertEqual(OriginHeaderState.derive(url: URL(string: "https://verify.example.org:8443/x"), allowList: allowList),
                       .unverified)
    }
}
