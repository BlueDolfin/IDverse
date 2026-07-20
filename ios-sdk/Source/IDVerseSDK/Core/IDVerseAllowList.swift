import Foundation
import LiteWebView

/// The IDVerse trust set. Lives in the ADAPTER (spec §4): the core allow-list has zero
/// built-in domains; every IDVerse entry is supplied explicitly here.
enum IDVerseAllowList {
    static func make(transactionURL: URL) -> OriginAllowList {
        var entries: [OriginAllowList.Entry] = [
            .suffix("idkit.co"),
            .suffix("idverse.com"),
            .exact(host: "idkit.co", port: 443),
            .exact(host: "idverse.com", port: 443)
        ]
        if let origin = WebOrigin(url: transactionURL), origin.scheme == "https",
           let port = origin.port {
            entries.append(.exact(host: origin.host, port: port))
        }
        return OriginAllowList(entries: entries)
    }
}
