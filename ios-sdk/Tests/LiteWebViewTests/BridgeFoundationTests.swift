import XCTest
@testable import LiteWebView

final class BridgeFoundationTests: XCTestCase {
    private struct DemoArgs: Decodable, Equatable { let name: String; let count: Int }
    private struct DemoResult: Encodable { let greeting: String }

    func test_errorCodes_matchSpec() {
        XCTAssertEqual(NativeFlowError.unknownFlow("x").code, "unknown_flow")
        XCTAssertEqual(NativeFlowError.invalidArguments("bad").code, "invalid_arguments")
        XCTAssertEqual(NativeFlowError.busy.code, "busy")
        XCTAssertEqual(NativeFlowError.cancelled.code, "cancelled")
        XCTAssertEqual(NativeFlowError.failed("boom").code, "failed")
    }
    func test_successEnvelopeShape() {
        let env = BridgeEnvelope.success(["greeting": "hi"])
        XCTAssertEqual(env["ok"] as? Bool, true)
        XCTAssertEqual((env["value"] as? [String: Any])?["greeting"] as? String, "hi")
    }
    func test_failureEnvelopeShape() {
        let env = BridgeEnvelope.failure(.busy)
        XCTAssertEqual(env["ok"] as? Bool, false)
        let err = env["error"] as? [String: String]
        XCTAssertEqual(err?["code"], "busy")
        XCTAssertNotNil(err?["message"])
    }
    func test_decodeArgs_roundTrip() throws {
        let args: DemoArgs = try NativeFlowCodec.decodeArgs(["name": "Ada", "count": 2])
        XCTAssertEqual(args, DemoArgs(name: "Ada", count: 2))
    }
    func test_decodeArgs_missingField_throwsInvalidArguments() {
        XCTAssertThrowsError(try NativeFlowCodec.decodeArgs(["name": "Ada"]) as DemoArgs) { error in
            guard case NativeFlowError.invalidArguments = error else {
                return XCTFail("expected invalidArguments, got \(error)")
            }
        }
    }
    func test_encodeResult_producesJSONObject() throws {
        let obj = try NativeFlowCodec.encodeResult(DemoResult(greeting: "hello"))
        XCTAssertEqual((obj as? [String: Any])?["greeting"] as? String, "hello")
    }
}
