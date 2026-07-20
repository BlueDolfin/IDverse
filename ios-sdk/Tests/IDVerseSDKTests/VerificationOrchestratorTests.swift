import XCTest
@testable import IDVerseSDK

private final class SpyService: IDVerseTransactionService, @unchecked Sendable {
    var createKeys: [String] = []
    var createError: Error?
    var results: [IDVerseVerificationResult]   // returned in order across fetch calls
    var fetchCount = 0
    let tx = IDVerseTransaction(id: "tx_1", url: URL(string: "https://idkit.co/t")!,
                                redirectURL: URL(string: "idverse-sdk://complete")!)
    init(results: [IDVerseVerificationResult], createError: Error? = nil) {
        self.results = results; self.createError = createError
    }
    func createTransaction(_ config: TransactionConfig) async throws -> IDVerseTransaction {
        createKeys.append(config.idempotencyKey)
        if let e = createError, createKeys.count < 3 { throw e }  // fail first 2, succeed on 3rd
        return tx
    }
    func fetchResult(transactionId: String) async throws -> IDVerseVerificationResult {
        defer { fetchCount += 1 }
        return results[min(fetchCount, results.count - 1)]
    }
}

final class NameLog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    func add(_ n: String) { lock.lock(); names.append(n); lock.unlock() }
    func all() -> [String] { lock.lock(); defer { lock.unlock() }; return names }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = 0.0
    func tick() -> TimeInterval { lock.lock(); defer { lock.unlock() }; let v = t; t += 10; return v }
}

@MainActor
final class VerificationOrchestratorTests: XCTestCase {
    private func makeOrchestrator(_ service: IDVerseTransactionService,
                                  events: @escaping @Sendable (IDVerseEvent) -> Void = { _ in },
                                  present: @escaping (IDVerseVerificationRequest) async throws -> WebFlowOutcome)
        -> VerificationOrchestrator {
        VerificationOrchestrator(
            service: service,
            configuration: IDVerseConfiguration(resultPollingTimeout: 100, retryPolicy: .default),
            emitter: IDVerseEventEmitter(.events(events), category: "test"),
            sleep: { _ in }, now: { 0 },
            present: present)
    }
    private let config = TransactionConfig(redirectURL: URL(string: "idverse-sdk://complete")!)
    private func result(_ o: IDVerseVerificationResult.Outcome) -> IDVerseVerificationResult {
        IDVerseVerificationResult(transactionId: "tx_1", outcome: o)
    }

    func test_happyPath_returnsResult() async throws {
        let service = SpyService(results: [result(.passed)])
        let o = makeOrchestrator(service) { _ in WebFlowOutcome(status: .completed, transactionId: nil) }
        let r = try await o.run(config)
        XCTAssertEqual(r.outcome, .passed)
    }

    func test_createRetry_usesSameIdempotencyKey() async throws {
        let service = SpyService(results: [result(.passed)], createError: URLError(.timedOut))
        let o = makeOrchestrator(service) { _ in WebFlowOutcome(status: .completed, transactionId: nil) }
        _ = try await o.run(config)
        XCTAssertEqual(service.createKeys.count, 3)                 // 2 failures + success
        XCTAssertEqual(Set(service.createKeys).count, 1)           // SAME key every retry
        XCTAssertFalse(service.createKeys[0].isEmpty)              // generated
    }

    func test_pollsWhilePending_thenReturnsFinal() async throws {
        let service = SpyService(results: [result(.pending), result(.pending), result(.passed)])
        let log = NameLog()
        let o = makeOrchestrator(service, events: { log.add($0.name) }) { _ in WebFlowOutcome(status: .completed, transactionId: nil) }
        let r = try await o.run(config)
        XCTAssertEqual(r.outcome, .passed)
        XCTAssertEqual(log.all().filter { $0 == "resultPending" }.count, 2)
        XCTAssertFalse(log.all().contains("resultPollingTimedOut"))
    }

    func test_pollingTimeout_returnsLatestPending_emitsTimedOut() async throws {
        let service = SpyService(results: [result(.pending)])
        let log = NameLog()
        let clock = Clock()
        let o = VerificationOrchestrator(
            service: service, configuration: IDVerseConfiguration(resultPollingTimeout: 1),
            emitter: IDVerseEventEmitter(.events { log.add($0.name) }, category: "test"),
            sleep: { _ in }, now: { clock.tick() },
            present: { _ in WebFlowOutcome(status: .completed, transactionId: nil) })
        let r = try await o.run(config)
        XCTAssertEqual(r.outcome, .pending)
        XCTAssertTrue(log.all().contains("resultPollingTimedOut"))
    }

    func test_cancelled_throwsCancelled_noFetch() async {
        let service = SpyService(results: [result(.passed)])
        let o = makeOrchestrator(service) { _ in WebFlowOutcome(status: .cancelled, transactionId: nil) }
        do { _ = try await o.run(config); XCTFail() }
        catch IDVerseError.cancelled { XCTAssertEqual(service.fetchCount, 0) }
        catch { XCTFail("unexpected \(error)") }
    }

    func test_redirectTransactionId_overridesCreatedId() async throws {
        let service = SpyService(results: [result(.passed)])
        var fetchedWith: String?
        final class Recorder: IDVerseTransactionService, @unchecked Sendable {
            let inner: SpyService; var onFetch: (String) -> Void
            init(_ i: SpyService, _ f: @escaping (String) -> Void) { inner = i; onFetch = f }
            func createTransaction(_ c: TransactionConfig) async throws -> IDVerseTransaction { try await inner.createTransaction(c) }
            func fetchResult(transactionId: String) async throws -> IDVerseVerificationResult { onFetch(transactionId); return try await inner.fetchResult(transactionId: transactionId) }
        }
        let rec = Recorder(service) { fetchedWith = $0 }
        let o = makeOrchestrator(rec) { _ in WebFlowOutcome(status: .completed, transactionId: "tx_redirect") }
        _ = try await o.run(config)
        XCTAssertEqual(fetchedWith, "tx_redirect")
    }
}
