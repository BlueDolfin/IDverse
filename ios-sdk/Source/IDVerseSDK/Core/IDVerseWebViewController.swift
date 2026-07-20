#if canImport(UIKit)
import UIKit
import LiteWebView

/// IDVerse-configured wrapper around the LiteWebView container. Public API unchanged
/// (spec §7); all container behavior (trust bar, navigation lock, capture shield,
/// watchdog, permissions) lives in LiteWebViewController.
public final class IDVerseWebViewController: UIViewController {
    private let request: IDVerseVerificationRequest
    private let emitter: IDVerseEventEmitter
    private var onFinish: @MainActor (Result<WebFlowOutcome, IDVerseError>) -> Void
    private var container: LiteWebViewController!

    init(request: IDVerseVerificationRequest,
         configuration: IDVerseConfiguration = .default,
         emitter: IDVerseEventEmitter = IDVerseEventEmitter(.disabled, category: "flow"),
         onFinish: @escaping @MainActor (Result<WebFlowOutcome, IDVerseError>) -> Void) {
        self.request = request
        self.emitter = emitter
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)

        var events = LiteWebViewEvents()
        let transactionId = request.transactionId
        events.onFlowStarted = { [emitter] in emitter.emit(.presented(transactionId: transactionId)) }
        events.onLoaded = { [emitter] in emitter.emit(.webViewLoaded(transactionId: transactionId)) }
        events.onNavigationBlocked = { [emitter] in emitter.emit(.navigationBlocked(transactionId: transactionId)) }
        events.onCompletionMatched = { [emitter] url in
            emitter.emit(.redirectMatched(transactionId: IDVerseRedirectParser.transactionId(from: url) ?? transactionId))
        }
        events.onContentProcessTerminated = { [emitter] in
            emitter.emit(.webContentProcessTerminated(transactionId: transactionId))
        }

        let liteRequest = LiteWebViewRequest(
            url: request.transactionURL,
            allowList: IDVerseAllowList.make(transactionURL: request.transactionURL),
            completionRule: RedirectCompletionRule(redirectURL: request.redirectURL),
            showsCloseButton: request.showsCloseButton,
            showsOriginHeader: request.showsOriginHeader,
            requiresCamera: true,
            requiresMicrophone: true,
            loadTimeout: configuration.webViewLoadTimeout,
            limitsNavigationsToAppBoundDomains: configuration.limitsNavigationsToAppBoundDomains,
            customUserAgent: IDVerseUserAgent.chrome)

        container = LiteWebViewController(request: liteRequest, events: events) { [weak self] result in
            self?.deliver(result)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        addChild(container)
        container.view.frame = view.bounds
        container.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(container.view)
        container.didMove(toParent: self)
    }

    private func deliver(_ result: Result<LiteWebViewOutcome, LiteWebViewError>) {
        switch result {
        case .success(.completed(let url)):
            onFinish(.success(WebFlowOutcome(
                status: .completed,
                transactionId: IDVerseRedirectParser.transactionId(from: url) ?? request.transactionId)))
        case .success(.cancelled):
            onFinish(.success(WebFlowOutcome(status: .cancelled, transactionId: request.transactionId)))
        case .failure(.cameraPermissionDenied):
            onFinish(.failure(.cameraPermissionDenied))
        case .failure(.microphonePermissionDenied):
            onFinish(.failure(.microphonePermissionDenied))
        case .failure(.contentLoadFailed(let underlying)):
            onFinish(.failure(.webContentLoadFailed(underlying)))
        }
    }

    func setOnFinish(_ handler: @escaping @MainActor (Result<WebFlowOutcome, IDVerseError>) -> Void) {
        self.onFinish = handler
    }

    func cancelFromOutside() {
        container.cancelFromOutside()
    }
}
#endif
