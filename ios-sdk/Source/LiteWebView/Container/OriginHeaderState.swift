import Foundation

/// Trust state shown in the native origin header. Derived from the webview's live
/// URL against the allow-list — never hardcoded — so the label is evidence, not decoration.
public enum OriginHeaderState: Equatable {
    case loading
    case verified(host: String)
    case unverified

    public static func derive(url: URL?, allowList: OriginAllowList) -> OriginHeaderState {
        guard let url else { return .loading }
        if url.scheme?.lowercased() == "about" { return .loading }
        guard let origin = WebOrigin(url: url), allowList.allows(origin) else { return .unverified }
        return .verified(host: origin.host)
    }
}
