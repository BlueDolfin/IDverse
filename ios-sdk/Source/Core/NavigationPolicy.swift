import Foundation

/// Pure decision logic for webview navigations. Fails closed on the main frame:
/// anything that is not the exit redirect, an allowed origin, or WebKit-internal
/// (about:) is blocked. Subframes are unrestricted — the main frame is the trust surface.
struct NavigationPolicy {
    enum Decision: Equatable {
        /// The exit redirect was hit — end the flow with this match.
        case finishFlow(IDVerseRedirectMatcher.Match)
        case allow
        /// Cancel the navigation; the flow keeps running on its current page.
        case block
    }

    let matcher: IDVerseRedirectMatcher
    let allowList: OriginAllowList

    func decide(url: URL?, isMainFrame: Bool) -> Decision {
        if isMainFrame, let match = matcher.match(url) { return .finishFlow(match) }
        guard isMainFrame else { return .allow }
        guard let url else { return .block }
        let scheme = url.scheme?.lowercased()
        if scheme == "about" { return .allow }
        guard scheme == "http" || scheme == "https" else { return .block }
        return allowList.allows(host: url.host) ? .allow : .block
    }
}
