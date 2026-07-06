import Foundation

public struct IDVerseTransaction: Equatable {
    public let id: String
    public let url: URL
    public let redirectURL: URL
    public init(id: String, url: URL, redirectURL: URL) {
        self.id = id
        self.url = url
        self.redirectURL = redirectURL
    }
}
