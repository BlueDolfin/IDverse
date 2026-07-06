import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Delivers an event to the public handler (if any) AND a redacted OSLog breadcrumb.
struct IDVerseEventEmitter: Sendable {
    private let observability: IDVerseObservability
    #if canImport(OSLog)
    private let logger: Logger
    #endif

    init(_ observability: IDVerseObservability, category: String) {
        self.observability = observability
        #if canImport(OSLog)
        self.logger = Logger(subsystem: "com.idverse.sdk", category: category)
        #endif
    }

    func emit(_ event: IDVerseEvent) {
        observability.deliver(event)
        #if canImport(OSLog)
        logger.log("\(event.name, privacy: .public) tx=\(event.transactionId ?? "-", privacy: .private)")
        #endif
    }
}

extension IDVerseEvent {
    /// Stable, PII-free name for logging/telemetry keys.
    var name: String {
        switch self {
        case .started: return "started"
        case .transactionCreateStarted: return "transactionCreateStarted"
        case .transactionCreateSucceeded: return "transactionCreateSucceeded"
        case .presented: return "presented"
        case .webViewLoaded: return "webViewLoaded"
        case .webContentProcessTerminated: return "webContentProcessTerminated"
        case .redirectMatched: return "redirectMatched"
        case .resultFetchStarted: return "resultFetchStarted"
        case .retrying: return "retrying"
        case .resultPending: return "resultPending"
        case .resultPollingTimedOut: return "resultPollingTimedOut"
        case .completed: return "completed"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        }
    }
    /// The correlation id if this event carries one (nil otherwise). Never any other field.
    var transactionId: String? {
        switch self {
        case .transactionCreateSucceeded(let id), .resultFetchStarted(let id),
             .resultPending(let id), .resultPollingTimedOut(let id),
             .completed(let id, _): return id
        case .presented(let id), .webViewLoaded(let id), .webContentProcessTerminated(let id),
             .redirectMatched(let id), .cancelled(let id), .failed(_, let id): return id
        case .started, .transactionCreateStarted, .retrying: return nil
        }
    }
}
