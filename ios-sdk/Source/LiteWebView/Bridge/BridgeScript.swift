import Foundation

/// The injected page API (spec §6). Injected .atDocumentStart, main frame only,
/// and ONLY when at least one flow is registered.
enum BridgeScript {
    static let handlerName = "liteWebViewBridge"

    static let source = """
    (function () {
      if (window.LiteWebView) { return; }
      window.LiteWebView = {
        executeNativeFlow: async function (flowId, args) {
          const response = await window.webkit.messageHandlers.liteWebViewBridge.postMessage({
            flowId: String(flowId),
            args: args === undefined ? null : args
          });
          if (!response || response.ok !== true) {
            const failure = (response && response.error) || { code: "failed", message: "Bridge transport failure." };
            const error = new Error(failure.message);
            error.code = failure.code;
            throw error;
          }
          return response.value;
        }
      };
    })();
    """
}
