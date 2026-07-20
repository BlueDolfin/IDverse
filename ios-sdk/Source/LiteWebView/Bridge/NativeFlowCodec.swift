import Foundation

/// JSON plumbing between the script-message world (Any) and typed contracts.
enum NativeFlowCodec {
    static func decodeArgs<A: Decodable>(_ jsonObject: Any) throws -> A {
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonObject)
            return try JSONDecoder().decode(A.self, from: data)
        } catch {
            throw NativeFlowError.invalidArguments(String(describing: error))
        }
    }

    static func encodeResult<R: Encodable>(_ value: R) throws -> Any {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw NativeFlowError.failed("Result encoding failed: \(String(describing: error))")
        }
    }
}
