#if canImport(UIKit)
import SwiftUI
import UIKit

/// Full-lifecycle SwiftUI entry: create → present → fetch, returning the real result.
public struct IDVerseVerificationFlow: UIViewControllerRepresentable {
    private let config: TransactionConfig
    private let service: IDVerseTransactionService
    private let configuration: IDVerseConfiguration
    private let onFinish: (Result<IDVerseVerificationResult, IDVerseError>) -> Void

    public init(config: TransactionConfig,
                service: IDVerseTransactionService,
                configuration: IDVerseConfiguration = .default,
                onFinish: @escaping (Result<IDVerseVerificationResult, IDVerseError>) -> Void) {
        self.config = config; self.service = service
        self.configuration = configuration; self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> IDVerseFlowHostController {
        IDVerseFlowHostController(config: config, service: service, configuration: configuration, onFinish: onFinish)
    }

    public func updateUIViewController(_ uiViewController: IDVerseFlowHostController, context: Context) {}

    public static func dismantleUIViewController(_ uiViewController: IDVerseFlowHostController, coordinator: ()) {
        uiViewController.cancel()
    }
}

public final class IDVerseFlowHostController: UIViewController {
    private let config: TransactionConfig
    private let service: IDVerseTransactionService
    private let configuration: IDVerseConfiguration
    private let onFinish: (Result<IDVerseVerificationResult, IDVerseError>) -> Void
    private var started = false
    private var task: Task<Void, Never>?

    init(config: TransactionConfig, service: IDVerseTransactionService,
         configuration: IDVerseConfiguration,
         onFinish: @escaping (Result<IDVerseVerificationResult, IDVerseError>) -> Void) {
        self.config = config; self.service = service
        self.configuration = configuration; self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func cancel() { task?.cancel() }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        task = Task { @MainActor in
            do {
                let result = try await IDVerse.runVerification(config, using: service, from: self, configuration: configuration)
                onFinish(.success(result))
            } catch let error as IDVerseError {
                onFinish(.failure(error))
            } catch {
                onFinish(.failure(.resultFetchFailed(error)))
            }
        }
    }
}
#endif
