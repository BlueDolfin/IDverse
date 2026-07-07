#if canImport(UIKit)
import UIKit
import WebKit
import AVFoundation

public final class IDVerseWebViewController: UIViewController {
    private let request: IDVerseVerificationRequest
    private var onFinish: @MainActor (Result<WebFlowOutcome, IDVerseError>) -> Void
    private lazy var allowList = OriginAllowList(transactionURL: request.transactionURL)
    private let matcher: IDVerseRedirectMatcher
    private lazy var navigationPolicy = NavigationPolicy(matcher: matcher, allowList: allowList)
    private var didBlockNavigation = false

    private var webView: WKWebView!
    private let spinner = UIActivityIndicatorView(style: .large)
    private let configuration: IDVerseConfiguration
    private let emitter: IDVerseEventEmitter
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

    init(request: IDVerseVerificationRequest,
         configuration: IDVerseConfiguration = .default,
         emitter: IDVerseEventEmitter = IDVerseEventEmitter(.disabled, category: "flow"),
         onFinish: @escaping @MainActor (Result<WebFlowOutcome, IDVerseError>) -> Void) {
        self.request = request
        self.configuration = configuration
        self.emitter = emitter
        self.onFinish = onFinish
        self.matcher = IDVerseRedirectMatcher(redirectURL: request.redirectURL)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
            limitsNavigationsToAppBoundDomains: configuration.limitsNavigationsToAppBoundDomains)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.customUserAgent = WebViewConfigurationFactory.chromeUserAgent
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

    /// Native trust bar OUTSIDE the webview — web content cannot draw over it.
    /// State is derived live from webView.url; never a hardcoded label.
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
        switch OriginHeaderState.derive(url: url, allowList: allowList) {
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

    /// The web flow needs the camera (document + selfie) AND the microphone (liveness video).
    /// Both are pre-flighted before loading so a denial is a typed failure up front instead of
    /// a getUserMedia call silently dying mid-journey.
    private func loadAfterMediaPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] videoGranted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard videoGranted else {
                    self.finish(.failure(.cameraPermissionDenied))
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] audioGranted in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        guard audioGranted else {
                            self.finish(.failure(.microphonePermissionDenied))
                            return
                        }
                        self.startFlow()
                    }
                }
            }
        }
    }

    private func startFlow() {
        didBlockNavigation = false
        emitter.emit(.presented(transactionId: request.transactionId))
        observeAppLifecycle()
        startLoadWatchdog()
        awaitingLoad = true
        webView.load(URLRequest(url: request.transactionURL,
                                timeoutInterval: max(0, configuration.webViewLoadTimeout)))
    }

    /// iOS cannot prevent screen recording/mirroring, only detect it. While the screen is
    /// captured, cover the webview (ID document + face are on screen) with an opaque shield.
    /// The Close button stays on top so the user is never trapped.
    private func setupCaptureShield() {
        captureShield.backgroundColor = .systemBackground
        captureShield.frame = view.bounds
        captureShield.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let label = UILabel()
        label.text = "Verification is hidden while the screen is being recorded or mirrored."
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

        // Above the webview, below the spinner and Close button added in setupChrome().
        view.insertSubview(captureShield, aboveSubview: webView)
        NotificationCenter.default.addObserver(self, selector: #selector(capturedDidChange),
            name: UIScreen.capturedDidChangeNotification, object: nil)
        capturedDidChange()
    }

    @objc private func capturedDidChange() {
        captureShield.isHidden = !UIScreen.main.isCaptured
    }

    /// Fails the flow if the FIRST page never loads within `configuration.webViewLoadTimeout`.
    /// Cancelled on the first `didFinish`, so a legitimately long in-progress
    /// journey (capture/liveness can take minutes) is never interrupted.
    private func startLoadWatchdog() {
        loadWatchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.didFinish else { return }
            self.spinner.stopAnimating()
            self.finish(.failure(.webContentLoadFailed(
                NSError(domain: "IDVerseSDK", code: NSURLErrorTimedOut,
                        userInfo: [NSLocalizedDescriptionKey:
                            "The verification page did not load. Check the transaction URL and your connection."]))))
        }
        loadWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, configuration.webViewLoadTimeout), execute: item)
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
        finish(.success(WebFlowOutcome(status: .cancelled, transactionId: request.transactionId)))
    }

    func setOnFinish(_ handler: @escaping @MainActor (Result<WebFlowOutcome, IDVerseError>) -> Void) {
        self.onFinish = handler
    }

    func cancelFromOutside() {
        finish(.success(WebFlowOutcome(status: .cancelled, transactionId: request.transactionId)))
    }

    private func finish(_ outcome: Result<WebFlowOutcome, IDVerseError>) {
        guard !didFinish else { return }
        didFinish = true
        loadWatchdog?.cancel()   // release the controller promptly; don't linger until the deadline
        onFinish(outcome)
    }
}

extension IDVerseWebViewController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame == true
        switch navigationPolicy.decide(url: navigationAction.request.url, isMainFrame: isMainFrame) {
        case .finishFlow(let match):
            decisionHandler(.cancel)
            emitter.emit(.redirectMatched(transactionId: match.transactionId ?? request.transactionId))
            finish(.success(WebFlowOutcome(status: .completed,
                                           transactionId: match.transactionId ?? request.transactionId)))
        case .allow:
            decisionHandler(.allow)
        case .block:
            didBlockNavigation = true
            decisionHandler(.cancel)
            emitter.emit(.navigationBlocked(transactionId: request.transactionId))
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadWatchdog?.cancel()
        awaitingLoad = false
        spinner.stopAnimating()
        if !firstLoadDone { firstLoadDone = true; emitter.emit(.webViewLoaded(transactionId: request.transactionId)) }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadWatchdog?.cancel()
        spinner.stopAnimating()
        finish(.failure(.webContentLoadFailed(error)))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // A navigation we deliberately cancelled surfaces here as "cancelled" /
        // "frame load interrupted" (102) — not a real load failure. If the blocked
        // navigation was the initial load, the watchdog still fails the flow.
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
        finish(.failure(.webContentLoadFailed(error)))
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        emitter.emit(.webContentProcessTerminated(transactionId: request.transactionId))
        if reloadedAfterTermination {
            finish(.failure(.webContentLoadFailed(
                NSError(domain: "IDVerseSDK", code: NSURLErrorCannotConnectToHost,
                        userInfo: [NSLocalizedDescriptionKey: "The verification view crashed and could not be recovered."]))))
            return
        }
        reloadedAfterTermination = true
        didBlockNavigation = false
        startLoadWatchdog()
        awaitingLoad = true
        webView.load(URLRequest(url: request.transactionURL, timeoutInterval: max(0, configuration.webViewLoadTimeout)))
    }
}

extension IDVerseWebViewController: WKUIDelegate {
    public func webView(_ webView: WKWebView,
                        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                        initiatedByFrame frame: WKFrameInfo,
                        type: WKMediaCaptureType,
                        decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(allowList.allows(host: origin.host) ? .grant : .deny)
    }
}
#endif
