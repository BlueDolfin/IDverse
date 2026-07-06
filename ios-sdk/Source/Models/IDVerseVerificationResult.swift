import Foundation

public struct IDVerseVerificationResult: Equatable {
    public enum Outcome: String, Equatable, Sendable {
        case passed, failed, refer, pending
    }

    public let transactionId: String
    public let outcome: Outcome
    public let extractedData: [String: String]?
    public let checks: [IDVerseCheck]?
    public let rawJSON: Data?

    public init(transactionId: String,
                outcome: Outcome,
                extractedData: [String: String]? = nil,
                checks: [IDVerseCheck]? = nil,
                rawJSON: Data? = nil) {
        self.transactionId = transactionId
        self.outcome = outcome
        self.extractedData = extractedData
        self.checks = checks
        self.rawJSON = rawJSON
    }
}

public struct IDVerseCheck: Equatable {
    public let name: String
    public let passed: Bool?
    public init(name: String, passed: Bool?) {
        self.name = name
        self.passed = passed
    }
}
