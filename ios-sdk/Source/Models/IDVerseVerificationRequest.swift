import Foundation

public struct IDVerseVerificationRequest: Equatable {
    public let transactionURL: URL
    public let redirectURL: URL
    public var showsCloseButton: Bool
    public var transactionId: String?

    public init(transactionURL: URL, redirectURL: URL,
                showsCloseButton: Bool = true, transactionId: String? = nil) {
        self.transactionURL = transactionURL
        self.redirectURL = redirectURL
        self.showsCloseButton = showsCloseButton
        self.transactionId = transactionId
    }
}
