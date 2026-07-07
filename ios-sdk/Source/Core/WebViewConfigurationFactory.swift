#if canImport(UIKit)
import UIKit
import WebKit

enum WebViewConfigurationFactory {
    /// Chrome-on-iOS UA, per IDVerse's WKWebView guidance. The OS version tracks the device
    /// so the string doesn't rot with new iOS releases; the CriOS version is fixed —
    /// MAINTENANCE: bump it periodically (last set to Chrome 126, mid-2024).
    static let chromeUserAgent: String = {
        let osVersion = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(osVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.153 Mobile/15E148 Safari/604.1"
    }()

    static func make(limitsNavigationsToAppBoundDomains: Bool = false) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // Identity verification: keep no on-disk cookie/cache residue.
        config.websiteDataStore = .nonPersistent()
        // Opt-in engine-enforced backstop to the delegate-level NavigationPolicy gate.
        config.limitsNavigationsToAppBoundDomains = limitsNavigationsToAppBoundDomains
        return config
    }
}
#endif
