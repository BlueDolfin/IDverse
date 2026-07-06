import XCTest
@testable import IDVerseSDK

final class RetryRunnerTests: XCTestCase {
    private func recordingSleep() -> (@Sendable (TimeInterval) async throws -> Void, @Sendable () -> [TimeInterval]) {
        let store = Delays()
        return ({ store.append($0) }, { store.all })
    }

    func test_succeedsFirstTry_noRetry() async throws {
        let (sleep, delays) = recordingSleep()
        var calls = 0
        let r = try await withRetry(.default, operation: .fetchResult, emit: { _ in }, sleep: sleep) {
            calls += 1; return 42
        }
        XCTAssertEqual(r, 42); XCTAssertEqual(calls, 1); XCTAssertEqual(delays().count, 0)
    }

    func test_retriesUpToMaxThenThrows_emitsRetryingBeforeEachSleep() async {
        let (sleep, delays) = recordingSleep()
        let events = Events()
        let policy = IDVerseRetryPolicy(maxAttempts: 3, initialDelay: 1, maxDelay: 10, jitter: 0, isRetryable: { _ in true })
        var calls = 0
        do {
            _ = try await withRetry(policy, operation: .createTransaction, emit: { events.record($0) }, sleep: sleep) {
                calls += 1; throw URLError(.timedOut)
            }
            XCTFail("expected throw")
        } catch {}
        XCTAssertEqual(calls, 3)                       // 3 attempts
        XCTAssertEqual(delays().count, 2)              // 2 sleeps between 3 attempts
        XCTAssertEqual(delays(), [1, 2])               // exponential, no jitter
        XCTAssertEqual(events.all().count, 2)          // one retrying per sleep
        if case .retrying(.createTransaction, 1, 3, _) = events.all()[0] {} else { XCTFail() }
    }

    func test_stopsWhenNotRetryable() async {
        let (sleep, _) = recordingSleep()
        let policy = IDVerseRetryPolicy(maxAttempts: 5, initialDelay: 1, maxDelay: 1, jitter: 0, isRetryable: { _ in false })
        var calls = 0
        do { _ = try await withRetry(policy, operation: .fetchResult, emit: { _ in }, sleep: sleep) { calls += 1; throw URLError(.badURL) }; XCTFail() }
        catch {}
        XCTAssertEqual(calls, 1)
    }

    func test_clampsMaxAttemptsToOne() async {
        let (sleep, _) = recordingSleep()
        let policy = IDVerseRetryPolicy(maxAttempts: 0, initialDelay: 1, maxDelay: 1, jitter: 0, isRetryable: { _ in true })
        var calls = 0
        do { _ = try await withRetry(policy, operation: .fetchResult, emit: { _ in }, sleep: sleep) { calls += 1; throw URLError(.timedOut) }; XCTFail() }
        catch {}
        XCTAssertEqual(calls, 1)
    }

    func test_cancellation_propagates_regardlessOfPolicy() async {
        // Even with an always-retry policy, a CancellationError must propagate, not retry.
        let policy = IDVerseRetryPolicy(maxAttempts: 5, initialDelay: 0, maxDelay: 0,
                                        jitter: 0, isRetryable: { _ in true })
        var calls = 0
        do {
            _ = try await withRetry(policy, operation: .fetchResult, emit: { _ in }, sleep: { _ in }) {
                calls += 1
                throw CancellationError()
            }
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            XCTAssertEqual(calls, 1)   // not retried despite isRetryable: { _ in true }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func test_defaultIsRetryable() {
        let p = IDVerseRetryPolicy.defaultIsRetryable
        XCTAssertTrue(p(URLError(.timedOut)))
        XCTAssertTrue(p(IDVerseError.transactionCreationFailed(URLError(.networkConnectionLost))))
        XCTAssertFalse(p(URLError(.badURL)))
        XCTAssertFalse(p(CancellationError()))
        XCTAssertFalse(p(IDVerseError.cancelled))
        XCTAssertFalse(p(NSError(domain: "Custom", code: 1)))   // unknown → fail fast; override to opt in
    }
}

private final class Delays: @unchecked Sendable {
    private let lock = NSLock(); private var d: [TimeInterval] = []
    func append(_ t: TimeInterval) { lock.lock(); d.append(t); lock.unlock() }
    var all: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return d }
}

final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [IDVerseEvent] = []
    func record(_ e: IDVerseEvent) { lock.lock(); items.append(e); lock.unlock() }
    func all() -> [IDVerseEvent] { lock.lock(); defer { lock.unlock() }; return items }
}
