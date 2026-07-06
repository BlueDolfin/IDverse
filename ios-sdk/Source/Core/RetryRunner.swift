import Foundation

/// Runs `body`, retrying per `policy` with clamped exponential backoff + jitter.
/// Emits `.retrying` BEFORE each sleep. `sleep` is injected so tests run with no real delay.
func withRetry<T>(_ policy: IDVerseRetryPolicy,
                  operation: IDVerseOperation,
                  emit: @Sendable (IDVerseEvent) -> Void,
                  sleep: @Sendable (TimeInterval) async throws -> Void,
                  _ body: () async throws -> T) async throws -> T {
    let maxAttempts = max(1, policy.maxAttempts)
    let initial = max(0, policy.initialDelay)
    let cap = max(initial, max(0, policy.maxDelay))
    let jitter = min(1, max(0, policy.jitter))
    var attempt = 1
    while true {
        do { return try await body() }
        catch {
            if error is CancellationError { throw error }   // cancellation always propagates, never retried
            if attempt >= maxAttempts || !policy.isRetryable(error) { throw error }
            emit(.retrying(operation: operation, attempt: attempt, maxAttempts: maxAttempts,
                           reason: IDVerseFailureCategory(error)))
            let base = min(cap, initial * pow(2, Double(attempt - 1)))
            let delay = jitter == 0 ? base : base * (1 + Double.random(in: -jitter...jitter))
            try await sleep(max(0, delay))
            attempt += 1
        }
    }
}
