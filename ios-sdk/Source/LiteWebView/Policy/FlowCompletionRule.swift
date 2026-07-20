import Foundation

public enum CompletionDecision: Equatable, Sendable {
    case continueFlow
    case complete(matchedURL: URL)
    case block
}

/// Decides whether a proposed navigation URL terminates the web flow.
/// The core's completion payload is the URL itself — interpretation belongs to adapters.
public protocol FlowCompletionRule: Sendable {
    func evaluate(_ url: URL) -> CompletionDecision
}

/// Matches a fixed redirect URL by scheme + host + effective port + path.
/// Runs BEFORE the allow-list (spec §5a), so port comparison here is load-bearing:
/// https://host:8443/callback must not satisfy a redirect registered as https://host/callback.
public struct RedirectCompletionRule: FlowCompletionRule, Equatable {
    public let redirectURL: URL

    public init(redirectURL: URL) {
        self.redirectURL = redirectURL
    }

    public func evaluate(_ url: URL) -> CompletionDecision {
        guard url.scheme?.lowercased() == redirectURL.scheme?.lowercased(),
              url.host?.lowercased() == redirectURL.host?.lowercased(),
              effectivePort(url) == effectivePort(redirectURL),
              url.path == redirectURL.path
        else { return .continueFlow }
        return .complete(matchedURL: url)
    }

    private func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}
