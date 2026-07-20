import Foundation

/// A web security origin: scheme + host + effective port. Privileged decisions
/// (navigation, media grants, the bridge) compare complete origins, never bare hostnames.
public struct WebOrigin: Equatable, Sendable {
    public let scheme: String
    public let host: String
    /// Effective port: explicit if present, else the scheme default (443/80), else nil.
    public let port: Int?

    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = url.port ?? WebOrigin.defaultPort(for: scheme)
    }

    public init(scheme: String, host: String, port: Int?) {
        let s = scheme.lowercased()
        self.scheme = s
        self.host = host.lowercased()
        self.port = port ?? WebOrigin.defaultPort(for: s)
    }

    static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}
