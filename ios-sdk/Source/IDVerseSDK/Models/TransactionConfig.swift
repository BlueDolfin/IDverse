import Foundation

public struct TransactionConfig {
    public var flowType: String
    public var customerReference: String?
    public var redirectURL: URL
    public var idempotencyKey: String

    public init(flowType: String = "single_doc",
                customerReference: String? = nil,
                redirectURL: URL,
                idempotencyKey: String = "") {
        self.flowType = flowType
        self.customerReference = customerReference
        self.redirectURL = redirectURL
        self.idempotencyKey = idempotencyKey
    }
}
