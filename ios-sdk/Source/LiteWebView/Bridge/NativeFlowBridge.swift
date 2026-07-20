#if canImport(UIKit)
import UIKit
import WebKit

/// WKScriptMessageHandlerWithReply endpoint. Always replies with the envelope
/// (spec §6); the reply-handler string-error path is reserved for transport failures.
@MainActor
final class NativeFlowBridge: NSObject, WKScriptMessageHandlerWithReply {
    private let registry: NativeFlowRegistry
    private let gate: BridgeGate
    private let lock: NativeFlowLock
    private let presenter: () -> UIViewController?
    /// Terminal path for the in-flight flow; funnels swipe-dismiss, completion, teardown.
    private var finishActiveFlow: ((Result<Any, NativeFlowError>) -> Void)?
    private var presentationWatcher: PresentationWatcher?

    init(registry: NativeFlowRegistry, gate: BridgeGate, lock: NativeFlowLock,
         presenter: @escaping () -> UIViewController?) {
        self.registry = registry
        self.gate = gate
        self.lock = lock
        self.presenter = presenter
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let so = message.frameInfo.securityOrigin
        let origin = WebOrigin(scheme: so.protocol, host: so.host, port: so.port == 0 ? nil : so.port)
        let documentURL = message.frameInfo.request.url ?? message.webView?.url
        guard gate.permits(origin: origin, isMainFrame: message.frameInfo.isMainFrame,
                           documentURL: documentURL) else {
            // Untrusted caller: transport-level rejection, no envelope, no detail.
            replyHandler(nil, "Not permitted.")
            return
        }
        guard let body = message.body as? [String: Any],
              let flowId = body["flowId"] as? String else {
            replyHandler(nil, "Malformed bridge message.")
            return
        }
        let args = body["args"] ?? NSNull()

        guard let flow = registry.flow(for: flowId) else {
            replyHandler(BridgeEnvelope.failure(.unknownFlow(flowId)), nil)
            return
        }
        guard lock.begin() else {
            replyHandler(BridgeEnvelope.failure(.busy), nil)
            return
        }

        // One-shot funnel (spec §8): every terminal path — completion, swipe-dismiss,
        // teardown — resumes exactly once, ON THE MAIN ACTOR. Contract completions are
        // plain closures a flow may call from any queue (e.g. a URLSession callback),
        // so `finish` hops before touching the lock, UIKit, or the reply handler.
        let oneShot = OneShotCompletion<Any, NativeFlowError> { [weak self] result in
            self?.finishActiveFlow = nil
            self?.presentationWatcher = nil
            self?.lock.end()
            switch result {
            case .success(let value): replyHandler(BridgeEnvelope.success(value), nil)
            case .failure(let error): replyHandler(BridgeEnvelope.failure(error), nil)
            }
        }
        let finish: @Sendable (Result<Any, NativeFlowError>) -> Void = { result in
            Task { @MainActor in oneShot.resume(result) }
        }
        finishActiveFlow = finish

        do {
            switch flow {
            case .viewController(let make):
                guard let host = presenter() else {
                    finish(.failure(.failed("No presenter available.")))
                    return
                }
                // The flow may call its completion from any queue; dismissal is UIKit
                // work, so it rides the SAME main-actor hop as the one-shot resume.
                // `presentedFlowVC` is declared before `make` because `viewController` (make's
                // own return value) can't be referenced inside the closure passed to `make`.
                weak var presentedFlowVC: UIViewController?
                let viewController = try make(args) { [weak host] result in
                    Task { @MainActor in
                        // Guard against the swipe-vs-late-completion race: if a swipe-dismiss
                        // already resolved this flow, `presentedFlowVC` is no longer the
                        // top-presented controller (or is nil), so skip the dismiss — otherwise
                        // UIKit forwards it to the container's presenting controller and tears
                        // down the whole webview.
                        if let presentedFlowVC, host?.presentedViewController === presentedFlowVC {
                            host?.dismiss(animated: true)
                        }
                        oneShot.resume(result)
                    }
                }
                presentedFlowVC = viewController
                // Swipe-to-dismiss must reject with `cancelled` and release the lock (spec §8).
                let watcher = PresentationWatcher { finish(.failure(.cancelled)) }
                self.presentationWatcher = watcher
                // Set the delegate before presenting (required for early adaptive callbacks)
                // AND reassert after presentation completes: with .automatic style, UIKit
                // resolves the actual presentation controller at presentation time, and the
                // one we configured up front is not guaranteed to be the one in use.
                viewController.presentationController?.delegate = watcher
                host.present(viewController, animated: true) {
                    viewController.presentationController?.delegate = watcher
                }
            case .takeover(let run):
                guard let host = presenter() else {
                    finish(.failure(.failed("No presenter available.")))
                    return
                }
                try run(args, host) { result in finish(result) }
            }
        } catch let error as NativeFlowError {
            finish(.failure(error))
        } catch {
            finish(.failure(.failed(String(describing: error))))
        }
    }

    /// Container teardown (spec §8): cancel any in-flight flow so the promise
    /// is rejected and the lock released.
    func cancelActiveFlow() {
        finishActiveFlow?(.failure(.cancelled))
    }
}

/// UIAdaptivePresentationControllerDelegate hop — fires when the user swipes the
/// presented flow away, which bypasses the flow's own completion.
@MainActor
private final class PresentationWatcher: NSObject, UIAdaptivePresentationControllerDelegate {
    private let onInteractiveDismiss: () -> Void
    init(onInteractiveDismiss: @escaping () -> Void) {
        self.onInteractiveDismiss = onInteractiveDismiss
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onInteractiveDismiss()
    }
}
#endif
