import Foundation

public struct IDVerseConfiguration: Sendable {
    public var observability: IDVerseObservability
    public var webViewLoadTimeout: TimeInterval
    public var resultPollingTimeout: TimeInterval
    public var retryPolicy: IDVerseRetryPolicy

    public static let `default` = IDVerseConfiguration()

    public init(observability: IDVerseObservability = .disabled,
                webViewLoadTimeout: TimeInterval = 30,
                resultPollingTimeout: TimeInterval = 60,
                retryPolicy: IDVerseRetryPolicy = .default) {
        self.observability = observability
        self.webViewLoadTimeout = webViewLoadTimeout
        self.resultPollingTimeout = resultPollingTimeout
        self.retryPolicy = retryPolicy
    }
}
