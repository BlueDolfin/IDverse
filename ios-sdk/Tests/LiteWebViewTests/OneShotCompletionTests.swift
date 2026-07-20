import XCTest
@testable import LiteWebView

@MainActor
final class OneShotCompletionTests: XCTestCase {
    private enum TestError: Error { case boom }

    func test_resumesExactlyOnce() {
        var delivered: [Int] = []
        let box = OneShotCompletion<Int, TestError> { if case .success(let v) = $0 { delivered.append(v) } }
        box.resume(.success(1))
        box.resume(.success(2))   // dropped
        box.resume(.failure(.boom))  // dropped
        XCTAssertEqual(delivered, [1])
    }
}
