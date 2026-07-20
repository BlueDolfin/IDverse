import XCTest
@testable import LiteWebView

final class BridgeScriptTests: XCTestCase {
    func test_scriptDefinesExecuteNativeFlow_andTranslatesEnvelope() {
        let s = BridgeScript.source
        XCTAssertTrue(s.contains("window.LiteWebView"))
        XCTAssertTrue(s.contains("executeNativeFlow"))
        XCTAssertTrue(s.contains("messageHandlers.\(BridgeScript.handlerName).postMessage"))
        // Envelope translation (spec §6): ok:false → thrown Error carrying code.
        XCTAssertTrue(s.contains("response.ok"))
        XCTAssertTrue(s.contains("throw"))
    }
    func test_handlerNameIsStable() {
        XCTAssertEqual(BridgeScript.handlerName, "liteWebViewBridge")
    }
}
