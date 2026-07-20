import Foundation

/// Origin allow-list for privileged decisions. Https-only; matches complete origins
/// (host + effective port), never bare hostnames. Ships with ZERO built-in trust:
/// an empty list allows nothing. Consumers (adapters) supply every entry explicitly.
public struct OriginAllowList: Sendable {
    public enum Entry: Equatable, Sendable {
        /// One exact host at one exact port (pass 443 for default https).
        case exact(host: String, port: Int)
        /// A base domain (leading/trailing dots trimmed) matching any *subdomain*
        /// (never the apex — apex trust stays explicit via `.exact`) at port 443.
        /// Entries that normalize to an empty domain match nothing.
        case suffix(String)
    }

    private let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries.map {
            switch $0 {
            case .exact(let host, let port): return .exact(host: host.lowercased(), port: port)
            case .suffix(let s):
                let domain = s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return .suffix(domain)
            }
        }
    }

    public func allows(_ origin: WebOrigin?) -> Bool {
        guard let origin, origin.scheme == "https", let port = origin.port else { return false }
        return entries.contains { entry in
            switch entry {
            case .exact(let host, let entryPort):
                return origin.host == host && port == entryPort
            case .suffix(let domain):
                return !domain.isEmpty && port == 443 && origin.host.hasSuffix("." + domain)
            }
        }
    }
}
