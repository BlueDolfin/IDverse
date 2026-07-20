import Foundation

struct VerificationOrchestrator {
    let service: IDVerseTransactionService
    let configuration: IDVerseConfiguration
    let emitter: IDVerseEventEmitter
    let sleep: @Sendable (TimeInterval) async throws -> Void
    let now: @Sendable () -> TimeInterval
    let present: (IDVerseVerificationRequest) async throws -> WebFlowOutcome

    init(service: IDVerseTransactionService,
         configuration: IDVerseConfiguration = .default,
         emitter: IDVerseEventEmitter = IDVerseEventEmitter(.disabled, category: "flow"),
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
         present: @escaping (IDVerseVerificationRequest) async throws -> WebFlowOutcome) {
        self.service = service; self.configuration = configuration; self.emitter = emitter
        self.sleep = sleep; self.now = now; self.present = present
    }

    func run(_ config: TransactionConfig) async throws -> IDVerseVerificationResult {
        let emitter = self.emitter
        emitter.emit(.started)
        var config = config
        if config.idempotencyKey.isEmpty { config.idempotencyKey = UUID().uuidString }

        emitter.emit(.transactionCreateStarted)
        let transaction = try await withRetry(configuration.retryPolicy, operation: .createTransaction,
                                              emit: { emitter.emit($0) }, sleep: sleep) {
            try await service.createTransaction(config)
        }
        emitter.emit(.transactionCreateSucceeded(transactionId: transaction.id))

        var request = IDVerseVerificationRequest(transactionURL: transaction.url,
                                                 redirectURL: transaction.redirectURL)
        request.transactionId = transaction.id
        let outcome = try await present(request)
        guard outcome.status == .completed else { throw IDVerseError.cancelled }

        let id = outcome.transactionId ?? transaction.id
        emitter.emit(.resultFetchStarted(transactionId: id))
        var result = try await fetch(id)

        let deadline = now() + max(0, configuration.resultPollingTimeout)
        var pollDelay = 1.0
        while result.outcome == .pending && now() < deadline {
            emitter.emit(.resultPending(transactionId: id))
            try await sleep(pollDelay)
            pollDelay = min(5.0, pollDelay * 2)
            result = try await fetch(id)
        }
        if result.outcome == .pending { emitter.emit(.resultPollingTimedOut(transactionId: id)) }
        emitter.emit(.completed(transactionId: id, outcome: result.outcome))
        return result
    }

    private func fetch(_ id: String) async throws -> IDVerseVerificationResult {
        let emitter = self.emitter
        return try await withRetry(configuration.retryPolicy, operation: .fetchResult,
                                   emit: { emitter.emit($0) }, sleep: sleep) {
            try await service.fetchResult(transactionId: id)
        }
    }
}
