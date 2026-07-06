import Foundation

/// Decides whether the webview may grant camera/microphone to a web origin.
/// Fails closed: only the transaction's own host and known IDVerse domains are allowed.
struct MediaOriginAllowList {
    private let allowedHosts: Set<String>
    private let allowedSuffixes: [String]

    init(transactionURL: URL,
         knownSuffixes: [String] = [".idkit.co", ".idverse.com"]) {
        var hosts = Set<String>()
        if let h = transactionURL.host?.lowercased() { hosts.insert(h) }
        self.allowedHosts = hosts
        self.allowedSuffixes = knownSuffixes + ["idkit.co", "idverse.com"]
    }

    func allows(host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        if allowedHosts.contains(host) { return true }
        return allowedSuffixes.contains { suffix in
            suffix.hasPrefix(".") ? host.hasSuffix(suffix) : host == suffix
        }
    }
}
