import Foundation

public struct LiteWebViewRequest {
    public var url: URL
    public var allowList: OriginAllowList
    public var completionRule: any FlowCompletionRule
    /// The single local asset allowed to load and (if flows are registered) call the bridge.
    /// A `file:` page has no https origin, so the trust bar shows "Origin not verified";
    /// hosts using a bundled page typically set `showsOriginHeader: false`.
    public var bundledBridgePage: URL?
    public var showsCloseButton: Bool
    public var showsOriginHeader: Bool
    public var requiresCamera: Bool
    public var requiresMicrophone: Bool
    public var loadTimeout: TimeInterval
    public var limitsNavigationsToAppBoundDomains: Bool
    public var customUserAgent: String?

    public init(url: URL,
                allowList: OriginAllowList,
                completionRule: any FlowCompletionRule,
                bundledBridgePage: URL? = nil,
                showsCloseButton: Bool = true,
                showsOriginHeader: Bool = true,
                requiresCamera: Bool = false,
                requiresMicrophone: Bool = false,
                loadTimeout: TimeInterval = 30,
                limitsNavigationsToAppBoundDomains: Bool = false,
                customUserAgent: String? = nil) {
        self.url = url
        self.allowList = allowList
        self.completionRule = completionRule
        self.bundledBridgePage = bundledBridgePage
        self.showsCloseButton = showsCloseButton
        self.showsOriginHeader = showsOriginHeader
        self.requiresCamera = requiresCamera
        self.requiresMicrophone = requiresMicrophone
        self.loadTimeout = loadTimeout
        self.limitsNavigationsToAppBoundDomains = limitsNavigationsToAppBoundDomains
        self.customUserAgent = customUserAgent
    }
}

public enum LiteWebViewOutcome: Equatable {
    /// The completion rule matched this URL (query intact). Interpretation is the caller's.
    case completed(URL)
    case cancelled
}

public enum LiteWebViewError: Error {
    case cameraPermissionDenied
    case microphonePermissionDenied
    case contentLoadFailed(Error)
}

/// Observation hooks; a host adapter maps these onto its own event stream.
public struct LiteWebViewEvents {
    /// Fired once permissions are granted, immediately before the first load
    /// (matches the timing of the adapter's legacy `.presented` event).
    public var onFlowStarted: () -> Void = {}
    public var onLoaded: () -> Void = {}
    public var onNavigationBlocked: () -> Void = {}
    public var onCompletionMatched: (URL) -> Void = { _ in }
    public var onContentProcessTerminated: () -> Void = {}
    public init() {}
}
