import Foundation

/// Main-actor-isolated resume-exactly-once box. Every terminal path (completion,
/// error, cancellation, teardown) funnels through `resume`; the first wins.
@MainActor
public final class OneShotCompletion<T, E: Error> {
    private var done = false
    private let deliver: (Result<T, E>) -> Void
    public init(_ deliver: @escaping (Result<T, E>) -> Void) { self.deliver = deliver }
    public func resume(_ result: Result<T, E>) {
        guard !done else { return }
        done = true
        deliver(result)
    }
}
