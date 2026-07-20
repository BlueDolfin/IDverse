#if canImport(UIKit)
import UIKit

/// Chrome-on-iOS UA, per IDVerse's WKWebView guidance — a VENDOR requirement, so it
/// lives in the adapter; the core accepts any UA via LiteWebViewRequest.customUserAgent.
enum IDVerseUserAgent {
    /// The OS version tracks the device; the CriOS version is fixed —
    /// MAINTENANCE: bump periodically (last set to Chrome 126, mid-2024).
    static let chrome: String = {
        let osVersion = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(osVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.153 Mobile/15E148 Safari/604.1"
    }()
}
#endif
