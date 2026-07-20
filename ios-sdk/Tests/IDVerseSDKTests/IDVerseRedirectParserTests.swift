import XCTest
@testable import IDVerseSDK

final class IDVerseRedirectParserTests: XCTestCase {
    func test_parsesTransactionId_camelCase() {
        XCTAssertEqual(IDVerseRedirectParser.transactionId(
            from: URL(string: "idverse-sdk://complete?transactionId=t1")!), "t1")
    }
    func test_parsesTransactionId_snakeCase() {
        XCTAssertEqual(IDVerseRedirectParser.transactionId(
            from: URL(string: "idverse-sdk://complete?transaction_id=t2")!), "t2")
    }
    func test_nilWhenAbsent() {
        XCTAssertNil(IDVerseRedirectParser.transactionId(
            from: URL(string: "idverse-sdk://complete")!))
    }
}
