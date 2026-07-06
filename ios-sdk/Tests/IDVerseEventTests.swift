import XCTest
@testable import IDVerseSDK

final class IDVerseEventTests: XCTestCase {
    func test_failureCategory_mapsIDVerseErrors() {
        XCTAssertEqual(IDVerseFailureCategory(IDVerseError.cameraPermissionDenied), .cameraPermissionDenied)
        XCTAssertEqual(IDVerseFailureCategory(IDVerseError.microphonePermissionDenied), .microphonePermissionDenied)
        XCTAssertEqual(IDVerseFailureCategory(IDVerseError.cancelled), .cancelled)
        XCTAssertEqual(IDVerseFailureCategory(IDVerseError.invalidTransactionURL), .unknown)
        XCTAssertEqual(IDVerseFailureCategory(IDVerseError.transactionCreationFailed(URLError(.timedOut))), .transactionCreationFailed)
        XCTAssertEqual(IDVerseFailureCategory(IDVerseError.resultFetchFailed(URLError(.timedOut))), .resultFetchFailed)
    }
    func test_failureCategory_mapsCancellationError() {
        XCTAssertEqual(IDVerseFailureCategory(CancellationError()), .cancelled)
    }
    func test_failureCategory_mapsLoadTimeoutNSError() {
        let timeout = NSError(domain: "IDVerseSDK", code: NSURLErrorTimedOut)
        XCTAssertEqual(IDVerseFailureCategory(IDVerseError.webContentLoadFailed(timeout)), .timedOut)
    }
    func test_failureCategory_unknownDefault() {
        XCTAssertEqual(IDVerseFailureCategory(URLError(.badURL)), .unknown)
    }
}
