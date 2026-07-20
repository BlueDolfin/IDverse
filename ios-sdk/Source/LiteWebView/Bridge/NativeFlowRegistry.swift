#if canImport(UIKit)
import UIKit

/// Type-erased runner. Args arrive as a JSON object (Any) from the script message;
/// results leave as a JSON object for the reply envelope. The closures are @MainActor
/// so they may call the contracts' @MainActor requirements without hopping.
enum AnyNativeFlow {
    case viewController(make: @MainActor (Any, @escaping (Result<Any, NativeFlowError>) -> Void) throws -> UIViewController)
    case takeover(run: @MainActor (Any, UIViewController, @escaping (Result<Any, NativeFlowError>) -> Void) throws -> Void)
}

/// Host-registered native flows, keyed by flow id. Flow id, Args and FlowResult shapes
/// are the agreed web/native contract. Empty registry → the bridge is never attached.
/// A type conforming to BOTH `ViewControllerNativeFlow` and `TakeoverNativeFlow` must be
/// registered via an explicit cast to one protocol to disambiguate the `register` overloads.
@MainActor
public final class NativeFlowRegistry {
    private var flows: [String: AnyNativeFlow] = [:]

    public init() {}

    public var isEmpty: Bool { flows.isEmpty }

    public func register<F: ViewControllerNativeFlow>(_ id: String, _ flow: F) {
        flows[id] = .viewController(make: { argsJSON, completion in
            let args: F.Args = try NativeFlowCodec.decodeArgs(argsJSON)
            return flow.makeViewController(args: args) { result in
                completion(result.flatMap { value in
                    Result { try NativeFlowCodec.encodeResult(value) }
                        .mapError { $0 as? NativeFlowError ?? .failed(String(describing: $0)) }
                })
            }
        })
    }

    public func register<F: TakeoverNativeFlow>(_ id: String, _ flow: F) {
        flows[id] = .takeover(run: { argsJSON, presenter, completion in
            let args: F.Args = try NativeFlowCodec.decodeArgs(argsJSON)
            flow.takeover(args: args, presenter: presenter) { result in
                completion(result.flatMap { value in
                    Result { try NativeFlowCodec.encodeResult(value) }
                        .mapError { $0 as? NativeFlowError ?? .failed(String(describing: $0)) }
                })
            }
        })
    }

    func flow(for id: String) -> AnyNativeFlow? { flows[id] }
}
#endif
