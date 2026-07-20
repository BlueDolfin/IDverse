import XCTest
@testable import LiteWebView

final class WebOriginTests: XCTestCase {
    func test_httpsDefaultPort() {
        let o = WebOrigin(url: URL(string: "https://Example.COM/path")!)
        XCTAssertEqual(o, WebOrigin(scheme: "https", host: "example.com", port: 443))
    }
    func test_explicitPortPreserved() {
        let o = WebOrigin(url: URL(string: "https://example.com:8443/x")!)
        XCTAssertEqual(o?.port, 8443)
    }
    func test_httpDefaultPort() {
        XCTAssertEqual(WebOrigin(url: URL(string: "http://example.com")!)?.port, 80)
    }
    func test_customSchemeHasNilPort() {
        XCTAssertEqual(WebOrigin(url: URL(string: "idverse-sdk://complete")!)?.port, nil)
    }
    func test_nilForHostlessURL() {
        XCTAssertNil(WebOrigin(url: URL(string: "about:blank")!))
    }
    func test_manualInitAppliesDefaultPort() {
        // WKSecurityOrigin reports port 0 for scheme-default; callers pass nil then.
        XCTAssertEqual(WebOrigin(scheme: "HTTPS", host: "A.b", port: nil),
                       WebOrigin(scheme: "https", host: "a.b", port: 443))
    }
}
