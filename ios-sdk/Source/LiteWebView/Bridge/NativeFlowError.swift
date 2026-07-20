import Foundation

/// Errors delivered to the page as `{ok:false, error:{code, message}}` rejections.
/// Only `message` strings cross the bridge — native error types never leak to JS.
public enum NativeFlowError: Error, Equatable {
    case unknownFlow(String)
    case invalidArguments(String)
    case busy
    case cancelled
    case failed(String)

    public var code: String {
        switch self {
        case .unknownFlow: return "unknown_flow"
        case .invalidArguments: return "invalid_arguments"
        case .busy: return "busy"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        }
    }

    public var message: String {
        switch self {
        case .unknownFlow(let id): return "No native flow registered for id '\(id)'."
        case .invalidArguments(let detail): return "Invalid arguments: \(detail)"
        case .busy: return "A native flow is already running."
        case .cancelled: return "The native flow was cancelled."
        case .failed(let detail): return detail
        }
    }
}
