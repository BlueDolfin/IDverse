import Foundation

extension URL {
    /// Canonical form for trusted-file comparisons: normalizes "." / ".." AND resolves
    /// symlinks (a link inside the bundle must not alias content outside it, and
    /// /var vs /private/var aliases must compare equal). Used by NavigationPolicy,
    /// BridgeGate, and BundledPageValidator — never compare raw file paths.
    var canonicalFileURL: URL { standardizedFileURL.resolvingSymlinksInPath() }
}

/// Pure decision logic for main-frame navigations. Fails closed. Order is load-bearing
/// (spec §5a): (1) completion rule, (2) about:, (3) bundled page, (4) scheme guard,
/// (5) origin allow-list. Subframes are unrestricted — the main frame is the trust surface.
public struct NavigationPolicy {
    public enum Decision: Equatable {
        /// The completion rule matched — end the flow; the URL carries the payload.
        case finishFlow(URL)
        case allow
        /// Cancel the navigation; the flow keeps running on its current page.
        case block
    }

    public let completionRule: any FlowCompletionRule
    public let allowList: OriginAllowList
    /// The single local asset allowed to load (spec §5a); nil = no file: URL ever loads.
    public let bundledPage: URL?

    public init(completionRule: any FlowCompletionRule,
                allowList: OriginAllowList,
                bundledPage: URL? = nil) {
        self.completionRule = completionRule
        self.allowList = allowList
        self.bundledPage = bundledPage
    }

    public func decide(url: URL?, isMainFrame: Bool) -> Decision {
        guard isMainFrame else { return .allow }
        guard let url else { return .block }
        switch completionRule.evaluate(url) {
        case .complete(let matched): return .finishFlow(matched)
        case .block: return .block
        case .continueFlow: break
        }
        let scheme = url.scheme?.lowercased()
        if scheme == "about" { return .allow }
        if url.isFileURL {
            if let bundledPage, url.canonicalFileURL == bundledPage.canonicalFileURL {
                return .allow
            }
            return .block
        }
        guard scheme == "http" || scheme == "https" else { return .block }
        return allowList.allows(WebOrigin(url: url)) ? .allow : .block
    }
}
