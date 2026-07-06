import Foundation

public struct IDVerseRetryPolicy: Sendable {
    public var maxAttempts: Int
    public var initialDelay: TimeInterval
    public var maxDelay: TimeInterval
    public var jitter: Double
    public var isRetryable: @Sendable (Error) -> Bool

    public init(maxAttempts: Int, initialDelay: TimeInterval, maxDelay: TimeInterval,
                jitter: Double, isRetryable: @escaping @Sendable (Error) -> Bool) {
        self.maxAttempts = maxAttempts; self.initialDelay = initialDelay
        self.maxDelay = maxDelay; self.jitter = jitter; self.isRetryable = isRetryable
    }

    public static let `default` = IDVerseRetryPolicy(
        maxAttempts: 3, initialDelay: 0.5, maxDelay: 4.0, jitter: 0.2,
        isRetryable: IDVerseRetryPolicy.defaultIsRetryable)
    public static let none = IDVerseRetryPolicy(
        maxAttempts: 1, initialDelay: 0, maxDelay: 0, jitter: 0, isRetryable: { _ in false })

    public static let defaultIsRetryable: @Sendable (Error) -> Bool = { error in
        if error is CancellationError { return false }
        if case IDVerseError.cancelled = error { return false }
        let underlying: Error = {
            switch error {
            case IDVerseError.transactionCreationFailed(let u),
                 IDVerseError.resultFetchFailed(let u),
                 IDVerseError.webContentLoadFailed(let u): return u
            default: return error
            }
        }()
        if let urlError = underlying as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet: return true
            default: return false
            }
        }
        return false  // unknown → fail fast (a deterministic failure shouldn't cost 3 attempts + backoff);
                      // integrators with typed backend errors opt into retrying them via isRetryable
    }
}
