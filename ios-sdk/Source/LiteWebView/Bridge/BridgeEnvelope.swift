import Foundation

/// The native→JS response envelope (spec §6). The reply handler's string-error path
/// cannot carry structure, so the bridge ALWAYS replies successfully with this shape
/// and the injected wrapper translates `ok:false` into a thrown Error.
enum BridgeEnvelope {
    static func success(_ value: Any) -> [String: Any] {
        ["ok": true, "value": value]
    }
    static func failure(_ error: NativeFlowError) -> [String: Any] {
        ["ok": false, "error": ["code": error.code, "message": error.message]]
    }
}
