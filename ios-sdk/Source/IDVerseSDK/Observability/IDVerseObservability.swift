import Foundation

public struct IDVerseObservability: Sendable {
    private let handler: (@Sendable (IDVerseEvent) -> Void)?
    public static let disabled = IDVerseObservability(handler: nil)
    public static func events(_ handler: @escaping @Sendable (IDVerseEvent) -> Void) -> IDVerseObservability {
        IDVerseObservability(handler: handler)
    }
    private init(handler: (@Sendable (IDVerseEvent) -> Void)?) { self.handler = handler }
    func deliver(_ event: IDVerseEvent) { handler?(event) }
}
