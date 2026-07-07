import Foundation

/// Trust state shown in the native origin header. Derived from the webview's live
/// URL against the shared allow-list — never hardcoded — so the label is evidence,
/// not decoration.
enum OriginHeaderState: Equatable {
    case loading
    case verified(host: String)
    case unverified

    static func derive(url: URL?, allowList: OriginAllowList) -> OriginHeaderState {
        guard let url else { return .loading }
        let scheme = url.scheme?.lowercased()
        if scheme == "about" { return .loading }
        guard scheme == "https",
              let host = url.host?.lowercased(),
              allowList.allows(host: host) else { return .unverified }
        return .verified(host: host)
    }
}
