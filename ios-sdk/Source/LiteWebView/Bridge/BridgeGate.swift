import Foundation

/// Pure trust decision for bridge messages (spec §6). Exactly two kinds of caller pass:
/// an allow-listed https origin in the main frame, or the single exact bundled page.
struct BridgeGate {
    let allowList: OriginAllowList
    let bundledBridgePage: URL?

    func permits(origin: WebOrigin?, isMainFrame: Bool, documentURL: URL?) -> Bool {
        guard isMainFrame, let origin else { return false }
        if origin.scheme == "file" {
            guard let bundledBridgePage, let documentURL else { return false }
            return documentURL.canonicalFileURL == bundledBridgePage.canonicalFileURL
        }
        return allowList.allows(origin)
    }
}
