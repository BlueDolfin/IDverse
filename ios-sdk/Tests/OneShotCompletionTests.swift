import XCTest
@testable import IDVerseSDK

@MainActor
final class OneShotCompletionTests: XCTestCase {
    func test_resumesExactlyOnce() {
        var delivered: [Int] = []
        let box = OneShotCompletion<Int> { if case .success(let v) = $0 { delivered.append(v) } }
        box.resume(.success(1))
        box.resume(.success(2))   // dropped
        box.resume(.failure(.cancelled))  // dropped
        XCTAssertEqual(delivered, [1])
    }
}
