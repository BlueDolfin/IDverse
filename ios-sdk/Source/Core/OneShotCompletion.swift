import Foundation

/// Main-actor-isolated resume-exactly-once box. Both the WebView callback and the
/// cancellation path funnel through `resume`; the first wins, later calls are dropped.
@MainActor
final class OneShotCompletion<T> {
    private var done = false
    private let deliver: (Result<T, IDVerseError>) -> Void
    init(_ deliver: @escaping (Result<T, IDVerseError>) -> Void) { self.deliver = deliver }
    func resume(_ result: Result<T, IDVerseError>) {
        guard !done else { return }
        done = true
        deliver(result)
    }
}
