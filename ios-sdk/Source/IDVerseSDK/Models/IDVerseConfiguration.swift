import Foundation

public struct IDVerseConfiguration: Sendable {
    public var observability: IDVerseObservability
    public var webViewLoadTimeout: TimeInterval
    public var resultPollingTimeout: TimeInterval
    public var retryPolicy: IDVerseRetryPolicy
    /// Opt-in: WebKit-enforced navigation lock to the host app's WKAppBoundDomains.
    /// Requires the INTEGRATOR to declare WKAppBoundDomains in the app's Info.plist;
    /// enabling it without that key blocks ALL navigation. Default off.
    public var limitsNavigationsToAppBoundDomains: Bool

    public static let `default` = IDVerseConfiguration()

    public init(observability: IDVerseObservability = .disabled,
                webViewLoadTimeout: TimeInterval = 30,
                resultPollingTimeout: TimeInterval = 60,
                retryPolicy: IDVerseRetryPolicy = .default,
                limitsNavigationsToAppBoundDomains: Bool = false) {
        self.observability = observability
        self.webViewLoadTimeout = webViewLoadTimeout
        self.resultPollingTimeout = resultPollingTimeout
        self.retryPolicy = retryPolicy
        self.limitsNavigationsToAppBoundDomains = limitsNavigationsToAppBoundDomains
    }
}
