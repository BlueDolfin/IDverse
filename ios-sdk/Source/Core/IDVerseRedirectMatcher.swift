import Foundation

/// Pure logic that decides whether a navigation target is the flow's exit redirect.
struct IDVerseRedirectMatcher {
    struct Match: Equatable {
        let transactionId: String?
    }

    let redirectURL: URL

    init(redirectURL: URL) {
        self.redirectURL = redirectURL
    }

    func match(_ url: URL?) -> Match? {
        guard let url else { return nil }
        guard url.scheme?.lowercased() == redirectURL.scheme?.lowercased(),
              url.host?.lowercased() == redirectURL.host?.lowercased(),
              url.path == redirectURL.path
        else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let transactionId = items?.first {
            $0.name == "transactionId" || $0.name == "transaction_id"
        }?.value
        return Match(transactionId: transactionId)
    }
}
