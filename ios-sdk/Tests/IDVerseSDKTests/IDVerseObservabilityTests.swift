import XCTest
@testable import IDVerseSDK

final class IDVerseObservabilityTests: XCTestCase {
    func test_events_deliversToHandler() {
        let box = Captured()
        let emitter = IDVerseEventEmitter(.events { box.append($0) }, category: "test")
        emitter.emit(.started)
        emitter.emit(.completed(transactionId: "tx", outcome: .passed))
        XCTAssertEqual(box.count, 2)
    }
    func test_disabled_deliversNothing_butDoesNotCrash() {
        let emitter = IDVerseEventEmitter(.disabled, category: "test")
        emitter.emit(.started)   // OSLog still writes; no handler; must not crash
    }
}

private final class Captured: @unchecked Sendable {
    private let lock = NSLock(); private var events: [IDVerseEvent] = []
    func append(_ e: IDVerseEvent) { lock.lock(); events.append(e); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
}
