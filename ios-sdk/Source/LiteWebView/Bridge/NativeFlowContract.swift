#if canImport(UIKit)
import UIKit

/// Shape A (spec §6): the host returns a view controller; the container presents it,
/// delivers the encoded result to the page, and dismisses on completion.
public protocol ViewControllerNativeFlow {
    associatedtype Args: Decodable
    associatedtype FlowResult: Encodable
    @MainActor func makeViewController(args: Args,
                                       completion: @escaping (Result<FlowResult, NativeFlowError>) -> Void) -> UIViewController
}

/// Shape B (spec §6): the host takes over navigation entirely and MUST always call
/// `completion` — the container can only guarantee cancellation on its own teardown.
public protocol TakeoverNativeFlow {
    associatedtype Args: Decodable
    associatedtype FlowResult: Encodable
    @MainActor func takeover(args: Args,
                             presenter: UIViewController,
                             completion: @escaping (Result<FlowResult, NativeFlowError>) -> Void)
}
#endif
