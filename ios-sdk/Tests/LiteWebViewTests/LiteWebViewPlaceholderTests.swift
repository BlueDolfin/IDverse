import XCTest
@testable import LiteWebView

final class LiteWebViewPlaceholderTests: XCTestCase {
    func test_targetLinks() {
        XCTAssertFalse(LiteWebViewInfo.version.isEmpty)
    }
}
