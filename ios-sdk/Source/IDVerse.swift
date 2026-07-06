#if canImport(UIKit)
import UIKit

@MainActor
public enum IDVerse {
    public static func runVerification(_ config: TransactionConfig,
                                       using service: IDVerseTransactionService,
                                       from presenter: UIViewController,
                                       configuration: IDVerseConfiguration = .default) async throws -> IDVerseVerificationResult {
        let emitter = IDVerseEventEmitter(configuration.observability, category: "flow")
        do {
            let orchestrator = VerificationOrchestrator(
                service: service, configuration: configuration, emitter: emitter) { request in
                    try await present(request, from: presenter, configuration: configuration, emitter: emitter)
                }
            return try await orchestrator.run(config)
        } catch is CancellationError {
            emitter.emit(.cancelled(transactionId: nil)); throw IDVerseError.cancelled
        } catch let error as IDVerseError {
            if case .cancelled = error { emitter.emit(.cancelled(transactionId: nil)) }
            else { emitter.emit(.failed(reason: IDVerseFailureCategory(error), transactionId: nil)) }
            throw error
        }
    }

    public static func verify(_ request: IDVerseVerificationRequest,
                              from presenter: UIViewController,
                              configuration: IDVerseConfiguration = .default) async throws -> IDVerseStatus {
        let emitter = IDVerseEventEmitter(configuration.observability, category: "flow")
        do {
            // Cancellation (external Task cancel or Close) returns a .cancelled outcome rather
            // than throwing, so emit the terminal event here — observability is entry-point
            // independent. The controller never emits .cancelled itself; each entry point
            // (verify here, IDVerseVerificationView for SwiftUI) emits its own terminal events.
            let outcome = try await present(request, from: presenter, configuration: configuration, emitter: emitter)
            if outcome.status == .cancelled {
                emitter.emit(.cancelled(transactionId: outcome.transactionId))
            }
            return outcome.status
        } catch is CancellationError {
            emitter.emit(.cancelled(transactionId: request.transactionId)); throw IDVerseError.cancelled
        } catch let error as IDVerseError {
            emitter.emit(.failed(reason: IDVerseFailureCategory(error), transactionId: request.transactionId)); throw error
        }
    }

    private static func present(_ request: IDVerseVerificationRequest,
                                from presenter: UIViewController,
                                configuration: IDVerseConfiguration,
                                emitter: IDVerseEventEmitter) async throws -> WebFlowOutcome {
        let controller = IDVerseWebViewController(request: request, configuration: configuration, emitter: emitter) { _ in }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<WebFlowOutcome, Error>) in
                let box = OneShotCompletion<WebFlowOutcome> { result in
                    presenter.dismiss(animated: true) {
                        switch result {
                        case .success(let o): cont.resume(returning: o)
                        case .failure(let e): cont.resume(throwing: e)
                        }
                    }
                }
                controller.setOnFinish { box.resume($0) }
                controller.modalPresentationStyle = .fullScreen
                presenter.present(controller, animated: true)
            }
        } onCancel: {
            Task { @MainActor in
                controller.cancelFromOutside()
            }
        }
    }
}
#endif
