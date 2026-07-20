#if canImport(UIKit)
import SwiftUI

public struct IDVerseVerificationView: UIViewControllerRepresentable {
    private let request: IDVerseVerificationRequest
    private let configuration: IDVerseConfiguration
    private let onFinish: (Result<IDVerseStatus, IDVerseError>) -> Void

    public init(request: IDVerseVerificationRequest,
                configuration: IDVerseConfiguration = .default,
                onFinish: @escaping (Result<IDVerseStatus, IDVerseError>) -> Void) {
        self.request = request; self.configuration = configuration; self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> IDVerseWebViewController {
        let emitter = IDVerseEventEmitter(configuration.observability, category: "flow")
        let request = self.request
        let onFinish = self.onFinish
        return IDVerseWebViewController(request: request, configuration: configuration, emitter: emitter) { result in
            // Terminal events mirror IDVerse.verify so observability is entry-point independent.
            switch result {
            case .success(let outcome):
                if outcome.status == .cancelled {
                    emitter.emit(.cancelled(transactionId: outcome.transactionId))
                }
                onFinish(.success(outcome.status))
            case .failure(let error):
                emitter.emit(.failed(reason: IDVerseFailureCategory(error), transactionId: request.transactionId))
                onFinish(.failure(error))
            }
        }
    }

    public func updateUIViewController(_ uiViewController: IDVerseWebViewController, context: Context) {}

    public static func dismantleUIViewController(_ uiViewController: IDVerseWebViewController, coordinator: ()) {
        uiViewController.cancelFromOutside()
    }
}
#endif
