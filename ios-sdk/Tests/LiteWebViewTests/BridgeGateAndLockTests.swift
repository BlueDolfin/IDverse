import XCTest
@testable import LiteWebView

final class BridgeGateAndLockTests: XCTestCase {
    private let allowList = OriginAllowList(entries: [.exact(host: "verify.example.org", port: 443)])

    // MARK: BridgeGate
    func test_permits_allowListedHTTPSMainFrame() {
        let gate = BridgeGate(allowList: allowList, bundledBridgePage: nil)
        XCTAssertTrue(gate.permits(origin: WebOrigin(scheme: "https", host: "verify.example.org", port: nil),
                                   isMainFrame: true, documentURL: nil))
    }
    func test_denies_subframe_evenIfAllowListed() {
        let gate = BridgeGate(allowList: allowList, bundledBridgePage: nil)
        XCTAssertFalse(gate.permits(origin: WebOrigin(scheme: "https", host: "verify.example.org", port: nil),
                                    isMainFrame: false, documentURL: nil))
    }
    func test_denies_httpOrigin() {
        let gate = BridgeGate(allowList: allowList, bundledBridgePage: nil)
        XCTAssertFalse(gate.permits(origin: WebOrigin(scheme: "http", host: "verify.example.org", port: nil),
                                    isMainFrame: true, documentURL: nil))
    }
    func test_denies_portMismatch() {
        let gate = BridgeGate(allowList: allowList, bundledBridgePage: nil)
        XCTAssertFalse(gate.permits(origin: WebOrigin(scheme: "https", host: "verify.example.org", port: 8443),
                                    isMainFrame: true, documentURL: nil))
    }
    func test_permits_exactBundledPage() {
        let page = URL(fileURLWithPath: "/bundle/bridge-demo.html")
        let gate = BridgeGate(allowList: allowList, bundledBridgePage: page)
        XCTAssertTrue(gate.permits(origin: WebOrigin(scheme: "file", host: "", port: nil),
                                   isMainFrame: true,
                                   documentURL: URL(fileURLWithPath: "/bundle/bridge-demo.html")))
    }
    func test_denies_otherLocalFile() {
        let page = URL(fileURLWithPath: "/bundle/bridge-demo.html")
        let gate = BridgeGate(allowList: allowList, bundledBridgePage: page)
        XCTAssertFalse(gate.permits(origin: WebOrigin(scheme: "file", host: "", port: nil),
                                    isMainFrame: true,
                                    documentURL: URL(fileURLWithPath: "/bundle/other.html")))
    }
    func test_denies_fileOrigin_whenNoBundledPageConfigured() {
        let gate = BridgeGate(allowList: allowList, bundledBridgePage: nil)
        XCTAssertFalse(gate.permits(origin: WebOrigin(scheme: "file", host: "", port: nil),
                                    isMainFrame: true,
                                    documentURL: URL(fileURLWithPath: "/bundle/bridge-demo.html")))
    }
    func test_denies_nilOrigin() {
        let gate = BridgeGate(allowList: allowList, bundledBridgePage: nil)
        XCTAssertFalse(gate.permits(origin: nil, isMainFrame: true, documentURL: nil))
    }

    // MARK: NativeFlowLock (container-wide, spec §6)
    @MainActor func test_lock_singleFlight_anyFlowID() {
        let lock = NativeFlowLock()
        XCTAssertTrue(lock.begin())
        XCTAssertFalse(lock.begin())   // second flow of ANY id → busy
        lock.end()
        XCTAssertTrue(lock.begin())    // released exactly on completion
    }

    // MARK: BundledPageValidator (spec §5a: must resolve inside the app bundle)
    func test_validator_acceptsPageInsideBundle() {
        let bundle = URL(fileURLWithPath: "/app/Demo.app")
        let page = URL(fileURLWithPath: "/app/Demo.app/bridge-demo.html")
        XCTAssertEqual(BundledPageValidator.validate(page, bundleURL: bundle), page.standardizedFileURL)
    }
    func test_validator_rejectsPageOutsideBundle() {
        let bundle = URL(fileURLWithPath: "/app/Demo.app")
        XCTAssertNil(BundledPageValidator.validate(URL(fileURLWithPath: "/tmp/evil.html"), bundleURL: bundle))
    }
    func test_validator_rejectsPrefixSpoof() {
        // "/app/Demo.appEvil/x.html" must not pass a naive hasPrefix("/app/Demo.app") check.
        let bundle = URL(fileURLWithPath: "/app/Demo.app")
        XCTAssertNil(BundledPageValidator.validate(URL(fileURLWithPath: "/app/Demo.appEvil/x.html"), bundleURL: bundle))
    }
    func test_validator_rejectsTraversalEscape() {
        let bundle = URL(fileURLWithPath: "/app/Demo.app")
        XCTAssertNil(BundledPageValidator.validate(URL(fileURLWithPath: "/app/Demo.app/../outside.html"), bundleURL: bundle))
    }
    func test_validator_rejectsNilAndNonFile() {
        let bundle = URL(fileURLWithPath: "/app/Demo.app")
        XCTAssertNil(BundledPageValidator.validate(nil, bundleURL: bundle))
        XCTAssertNil(BundledPageValidator.validate(URL(string: "https://example.com/x.html")!, bundleURL: bundle))
    }
    func test_validator_rejectsSymlinkEscape() throws {
        // A symlink INSIDE the bundle aliasing a file OUTSIDE it must be rejected —
        // path standardization alone cannot catch this; symlink resolution must.
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = root.appendingPathComponent("Demo.app")
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let outside = root.appendingPathComponent("evil.html")
        try "x".write(to: outside, atomically: true, encoding: .utf8)
        let link = bundle.appendingPathComponent("page.html")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertNil(BundledPageValidator.validate(link, bundleURL: bundle))
    }
    func test_validator_acceptsRealFileThroughSymlinkedTempPrefix() throws {
        // /var vs /private/var: both sides are canonicalized, so a real in-bundle file
        // validates even when the bundle path itself sits under a symlinked prefix.
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = root.appendingPathComponent("Demo.app")
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let page = bundle.appendingPathComponent("bridge-demo.html")
        try "x".write(to: page, atomically: true, encoding: .utf8)
        XCTAssertNotNil(BundledPageValidator.validate(page, bundleURL: bundle))
    }
}
