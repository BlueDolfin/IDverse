#if canImport(UIKit)
import UIKit
import WebKit

public enum WebViewConfigurationFactory {
    public static func make(limitsNavigationsToAppBoundDomains: Bool = false) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // Sensitive flows: keep no on-disk cookie/cache residue.
        config.websiteDataStore = .nonPersistent()
        // Opt-in engine-enforced backstop to the delegate-level NavigationPolicy gate.
        config.limitsNavigationsToAppBoundDomains = limitsNavigationsToAppBoundDomains
        return config
    }
}
#endif
