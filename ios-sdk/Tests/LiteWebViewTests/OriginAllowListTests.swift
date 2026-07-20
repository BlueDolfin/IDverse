import XCTest
@testable import LiteWebView

final class OriginAllowListTests: XCTestCase {
    private let list = OriginAllowList(entries: [
        .exact(host: "verify.example.org", port: 443),
        .exact(host: "alt.example.org", port: 8443),
        .suffix(".cdn.example.org")
    ])

    func test_emptyListTrustsNothing() {
        // Spec §5a/§9: no implicit trust — the core ships zero built-in domains.
        let empty = OriginAllowList(entries: [])
        XCTAssertFalse(empty.allows(WebOrigin(url: URL(string: "https://idkit.co")!)))
        XCTAssertFalse(empty.allows(WebOrigin(url: URL(string: "https://anything.example")!)))
    }
    func test_exactHostDefaultPort() {
        XCTAssertTrue(list.allows(WebOrigin(url: URL(string: "https://verify.example.org/step")!)))
    }
    func test_httpNeverAllowed_evenForListedHost() {
        // Spec §5a: plain-HTTP remote content is always blocked.
        XCTAssertFalse(list.allows(WebOrigin(url: URL(string: "http://verify.example.org/")!)))
    }
    func test_portMismatchDenied() {
        XCTAssertFalse(list.allows(WebOrigin(url: URL(string: "https://verify.example.org:8443/")!)))
    }
    func test_explicitNonDefaultPortAllowedWhenListed() {
        XCTAssertTrue(list.allows(WebOrigin(url: URL(string: "https://alt.example.org:8443/")!)))
    }
    func test_suffixMatchesSubdomain_at443Only() {
        XCTAssertTrue(list.allows(WebOrigin(url: URL(string: "https://a.cdn.example.org/x")!)))
        XCTAssertFalse(list.allows(WebOrigin(url: URL(string: "https://a.cdn.example.org:8443/x")!)))
    }
    func test_suffixDoesNotMatchApex() {
        // ".cdn.example.org" means subdomains; the apex needs its own .exact entry.
        XCTAssertFalse(list.allows(WebOrigin(url: URL(string: "https://cdn.example.org/x")!)))
    }
    func test_nilOriginDenied() {
        XCTAssertFalse(list.allows(nil))
    }
    func test_customSchemeDenied() {
        XCTAssertFalse(list.allows(WebOrigin(url: URL(string: "ftp://verify.example.org")!)))
    }
    func test_suffixAllowsSubdomain() {
        let list = OriginAllowList(entries: [.suffix("example.com")])
        XCTAssertTrue(list.allows(WebOrigin(url: URL(string: "https://api.example.com")!)))
    }
    func test_suffixAllowsNestedSubdomain() {
        let list = OriginAllowList(entries: [.suffix("example.com")])
        XCTAssertTrue(list.allows(WebOrigin(url: URL(string: "https://a.b.example.com")!)))
    }
    func test_suffixDoesNotAllowApex() {
        let list = OriginAllowList(entries: [.suffix("example.com")])
        XCTAssertFalse(list.allows(WebOrigin(url: URL(string: "https://example.com")!)))
    }
    func test_suffixRequiresDomainBoundary() {
        let list = OriginAllowList(entries: [.suffix("example.com")])
        XCTAssertFalse(list.allows(WebOrigin(url: URL(string: "https://evil-example.com")!)))
        XCTAssertFalse(list.allows(WebOrigin(url: URL(string: "https://notexample.com")!)))
    }
    func test_emptyOrDotOnlySuffixMatchesNothing() {
        // A suffix that normalizes to an empty domain must be inert, not a
        // trailing-dot wildcard (https://evil.com./ is a valid FQDN form).
        let list = OriginAllowList(entries: [.suffix(""), .suffix("."), .suffix("..")])
        XCTAssertFalse(list.allows(WebOrigin(url: URL(string: "https://evil.com./x")!)))
        XCTAssertFalse(list.allows(WebOrigin(url: URL(string: "https://evil.com/x")!)))
    }
}
