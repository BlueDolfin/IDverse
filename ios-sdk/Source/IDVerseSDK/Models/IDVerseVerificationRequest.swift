import Foundation

public struct IDVerseVerificationRequest: Equatable {
    public let transactionURL: URL
    public let redirectURL: URL
    public var showsCloseButton: Bool
    /// Native trust bar above the webview showing the live origin. Default on.
    public var showsOriginHeader: Bool
    public var transactionId: String?

    public init(transactionURL: URL, redirectURL: URL,
                showsCloseButton: Bool = true, showsOriginHeader: Bool = true,
                transactionId: String? = nil) {
        self.transactionURL = transactionURL
        self.redirectURL = redirectURL
        self.showsCloseButton = showsCloseButton
        self.showsOriginHeader = showsOriginHeader
        self.transactionId = transactionId
    }
}
