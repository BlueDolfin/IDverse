#if canImport(UIKit)
import UIKit
import WebKit
import AVFoundation

@MainActor
public final class LiteWebViewController: UIViewController {
    private let request: LiteWebViewRequest
    private let nativeFlows: NativeFlowRegistry
    private let events: LiteWebViewEvents
    private var onFinish: @MainActor (Result<LiteWebViewOutcome, LiteWebViewError>) -> Void
    /// Spec §5a: only a page that provably lives inside the app bundle gets the exception.
    /// A configured page outside the bundle is treated as not configured at all.
    private lazy var bundledPage: URL? = BundledPageValidator.validate(
        request.bundledBridgePage, bundleURL: Bundle.main.bundleURL)
    private lazy var navigationPolicy = NavigationPolicy(completionRule: request.completionRule,
                                                         allowList: request.allowList,
                                                         bundledPage: bundledPage)
    private var didBlockNavigation = false

    private var webView: WKWebView!
    private var bridge: NativeFlowBridge?
    private let spinner = UIActivityIndicatorView(style: .large)
    private var reloadedAfterTermination = false
    private var firstLoadDone = false
    private var awaitingLoad = false
    private var didFinish = false
    private var loadWatchdog: DispatchWorkItem?
    private let captureShield = UIView()
    private let originHeader = UIView()
    private let originLock = UIImageView()
    private let originLabel = UILabel()
    private var urlObservation: NSKeyValueObservation?

    public init(request: LiteWebViewRequest,
                nativeFlows: NativeFlowRegistry? = nil,
                events: LiteWebViewEvents = LiteWebViewEvents(),
                onFinish: @escaping @MainActor (Result<LiteWebViewOutcome, LiteWebViewError>) -> Void) {
        self.request = request
        // `NativeFlowRegistry()` is @MainActor-isolated, so it cannot appear as a
        // literal default-argument value on a `public` init (default-argument
        // generators for public API are compiled as nonisolated symbols for ABI
        // reasons, regardless of the enclosing type's own isolation). Constructing
        // the empty-registry default here, inside the (MainActor-isolated) body,
        // preserves the stated "defaults to no registered flows" behavior.
        self.nativeFlows = nativeFlows ?? NativeFlowRegistry()
        self.events = events
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Host dismissed/popped us directly: cancel any in-flight native flow so the
        // page's promise rejects and the lock releases (spec §8 teardown guarantee).
        if isBeingDismissed || isMovingFromParent {
            bridge?.cancelActiveFlow()
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        if request.showsOriginHeader { setupOriginHeader() }
        setupWebView()
        setupChrome()
        setupCaptureShield()
        loadAfterMediaPermissions()
    }

    private func setupWebView() {
        let config = WebViewConfigurationFactory.make(
            limitsNavigationsToAppBoundDomains: request.limitsNavigationsToAppBoundDomains)
        attachBridgeIfNeeded(to: config)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        if let userAgent = request.customUserAgent { webView.customUserAgent = userAgent }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view.addSubview(webView)

        let top = request.showsOriginHeader
            ? webView.topAnchor.constraint(equalTo: originHeader.bottomAnchor)
            : webView.topAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([
            top,
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if request.showsOriginHeader {
            urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                self?.updateOriginHeader(for: webView.url)
            }
        }
    }

    /// Opt-in (spec §6): zero registered flows → no script injected, no handler attached.
    private func attachBridgeIfNeeded(to config: WKWebViewConfiguration) {
        guard !nativeFlows.isEmpty else { return }
        let gate = BridgeGate(allowList: request.allowList,
                              bundledBridgePage: bundledPage)
        let bridge = NativeFlowBridge(registry: nativeFlows, gate: gate, lock: NativeFlowLock(),
                                      presenter: { [weak self] in self })
        self.bridge = bridge
        config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page,
                                                             name: BridgeScript.handlerName)
        config.userContentController.addUserScript(WKUserScript(source: BridgeScript.source,
                                                                injectionTime: .atDocumentStart,
                                                                forMainFrameOnly: true))
    }

    /// Native trust bar OUTSIDE the webview — web content cannot draw over it.
    private func setupOriginHeader() {
        originHeader.translatesAutoresizingMaskIntoConstraints = false
        originHeader.backgroundColor = .secondarySystemBackground
        view.addSubview(originHeader)

        originLock.translatesAutoresizingMaskIntoConstraints = false
        originLock.contentMode = .scaleAspectFit
        originLabel.translatesAutoresizingMaskIntoConstraints = false
        originLabel.font = .preferredFont(forTextStyle: .footnote)
        originLabel.lineBreakMode = .byTruncatingMiddle
        originHeader.addSubview(originLock)
        originHeader.addSubview(originLabel)

        NSLayoutConstraint.activate([
            originHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            originHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            originHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            originHeader.heightAnchor.constraint(equalToConstant: 36),

            originLabel.centerXAnchor.constraint(equalTo: originHeader.centerXAnchor, constant: 10),
            originLabel.centerYAnchor.constraint(equalTo: originHeader.centerYAnchor),
            originLabel.widthAnchor.constraint(lessThanOrEqualTo: originHeader.widthAnchor, multiplier: 0.6),
            originLock.trailingAnchor.constraint(equalTo: originLabel.leadingAnchor, constant: -6),
            originLock.centerYAnchor.constraint(equalTo: originHeader.centerYAnchor),
            originLock.widthAnchor.constraint(equalToConstant: 14),
            originLock.heightAnchor.constraint(equalToConstant: 14)
        ])
        updateOriginHeader(for: nil)
    }

    private func updateOriginHeader(for url: URL?) {
        switch OriginHeaderState.derive(url: url, allowList: request.allowList) {
        case .loading:
            originLock.image = UIImage(systemName: "lock")
            originLock.tintColor = .secondaryLabel
            originLabel.text = "Loading…"
            originLabel.textColor = .secondaryLabel
        case .verified(let host):
            originLock.image = UIImage(systemName: "lock.fill")
            originLock.tintColor = .systemGreen
            originLabel.text = host
            originLabel.textColor = .label
        case .unverified:
            originLock.image = UIImage(systemName: "exclamationmark.triangle.fill")
            originLock.tintColor = .systemOrange
            originLabel.text = "Origin not verified"
            originLabel.textColor = .systemOrange
        }
    }

    private func setupChrome() {
        spinner.center = view.center
        spinner.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin,
                                    .flexibleLeftMargin, .flexibleRightMargin]
        spinner.startAnimating()
        view.addSubview(spinner)

        if request.showsCloseButton {
            let close = UIButton(type: .system)
            close.setTitle("Close", for: .normal)
            close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            close.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(close)
            NSLayoutConstraint.activate([
                close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
            ])
        }
    }

    /// Required media access is pre-flighted so a denial is a typed failure up front
    /// instead of a getUserMedia call silently dying mid-journey.
    private func loadAfterMediaPermissions() {
        requestIfNeeded(.video, required: request.requiresCamera,
                        failure: .cameraPermissionDenied) { [weak self] in
            guard let self else { return }
            self.requestIfNeeded(.audio, required: self.request.requiresMicrophone,
                                 failure: .microphonePermissionDenied) { [weak self] in
                self?.startFlow()
            }
        }
    }

    private func requestIfNeeded(_ mediaType: AVMediaType, required: Bool,
                                 failure: LiteWebViewError, then proceed: @escaping () -> Void) {
        guard required else { proceed(); return }
        AVCaptureDevice.requestAccess(for: mediaType) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.finish(.failure(failure))
                    return
                }
                proceed()
            }
        }
    }

    private func startFlow() {
        didBlockNavigation = false
        events.onFlowStarted()
        observeAppLifecycle()
        startLoadWatchdog()
        awaitingLoad = true
        loadInitialPage()
    }

    /// Single load path — the crash-recovery reload (below) must go through the same
    /// branch, or a bundled file: page would be reloaded with a plain URLRequest and fail.
    private func loadInitialPage() {
        if request.url.isFileURL {
            webView.loadFileURL(request.url,
                                allowingReadAccessTo: request.url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: request.url,
                                    timeoutInterval: max(0, request.loadTimeout)))
        }
    }

    /// iOS cannot prevent screen recording/mirroring, only detect it. While captured,
    /// cover the webview with an opaque shield. The Close button stays on top.
    private func setupCaptureShield() {
        captureShield.backgroundColor = .systemBackground
        captureShield.frame = view.bounds
        captureShield.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let label = UILabel()
        label.text = "Content is hidden while the screen is being recorded or mirrored."
        label.font = .preferredFont(forTextStyle: .body)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        captureShield.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: captureShield.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: captureShield.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: captureShield.trailingAnchor, constant: -32)
        ])

        view.insertSubview(captureShield, aboveSubview: webView)
        NotificationCenter.default.addObserver(self, selector: #selector(capturedDidChange),
            name: UIScreen.capturedDidChangeNotification, object: nil)
        capturedDidChange()
    }

    @objc private func capturedDidChange() {
        captureShield.isHidden = !UIScreen.main.isCaptured
    }

    /// Fails the flow if the FIRST page never loads within `request.loadTimeout`.
    private func startLoadWatchdog() {
        loadWatchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.didFinish else { return }
            self.spinner.stopAnimating()
            self.finish(.failure(.contentLoadFailed(
                NSError(domain: "LiteWebView", code: NSURLErrorTimedOut,
                        userInfo: [NSLocalizedDescriptionKey:
                            "The page did not load. Check the URL and your connection."]))))
        }
        loadWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, request.loadTimeout), execute: item)
    }

    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    @objc private func appDidBackground() { loadWatchdog?.cancel() }
    @objc private func appWillForeground() { if awaitingLoad && !didFinish { startLoadWatchdog() } }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func closeTapped() {
        finish(.success(.cancelled))
    }

    func setOnFinish(_ handler: @escaping @MainActor (Result<LiteWebViewOutcome, LiteWebViewError>) -> Void) {
        self.onFinish = handler
    }

    public func cancelFromOutside() {
        finish(.success(.cancelled))
    }

    private func finish(_ outcome: Result<LiteWebViewOutcome, LiteWebViewError>) {
        guard !didFinish else { return }
        didFinish = true
        loadWatchdog?.cancel()
        bridge?.cancelActiveFlow()   // teardown cancels any in-flight native flow (spec §8)
        onFinish(outcome)
    }
}

extension LiteWebViewController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame == true
        switch navigationPolicy.decide(url: navigationAction.request.url, isMainFrame: isMainFrame) {
        case .finishFlow(let matchedURL):
            decisionHandler(.cancel)
            events.onCompletionMatched(matchedURL)
            finish(.success(.completed(matchedURL)))
        case .allow:
            decisionHandler(.allow)
        case .block:
            didBlockNavigation = true
            decisionHandler(.cancel)
            events.onNavigationBlocked()
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadWatchdog?.cancel()
        awaitingLoad = false
        spinner.stopAnimating()
        if !firstLoadDone { firstLoadDone = true; events.onLoaded() }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadWatchdog?.cancel()
        spinner.stopAnimating()
        finish(.failure(.contentLoadFailed(error)))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // A navigation we deliberately cancelled surfaces here as "cancelled" /
        // "frame load interrupted" (102) — not a real load failure.
        let nsError = error as NSError
        let deliberateCancel =
            (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) ||
            (nsError.domain == "WebKitErrorDomain" && nsError.code == 102)
        if didBlockNavigation, deliberateCancel {
            didBlockNavigation = false
            return
        }
        loadWatchdog?.cancel()
        spinner.stopAnimating()
        finish(.failure(.contentLoadFailed(error)))
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        events.onContentProcessTerminated()
        if reloadedAfterTermination {
            finish(.failure(.contentLoadFailed(
                NSError(domain: "LiteWebView", code: NSURLErrorCannotConnectToHost,
                        userInfo: [NSLocalizedDescriptionKey: "The web view crashed and could not be recovered."]))))
            return
        }
        reloadedAfterTermination = true
        didBlockNavigation = false
        startLoadWatchdog()
        awaitingLoad = true
        loadInitialPage()
    }
}

extension LiteWebViewController: WKUIDelegate {
    public func webView(_ webView: WKWebView,
                        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                        initiatedByFrame frame: WKFrameInfo,
                        type: WKMediaCaptureType,
                        decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let webOrigin = WebOrigin(scheme: origin.protocol, host: origin.host,
                                  port: origin.port == 0 ? nil : origin.port)
        decisionHandler(request.allowList.allows(webOrigin) ? .grant : .deny)
    }
}
#endif
