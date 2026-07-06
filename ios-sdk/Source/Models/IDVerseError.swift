import Foundation

public enum IDVerseError: Error {
    case invalidTransactionURL
    case cameraPermissionDenied
    case microphonePermissionDenied
    case cancelled
    case webContentLoadFailed(Error)
    case transactionCreationFailed(Error)
    case resultFetchFailed(Error)
}

// The wrapped errors come from Foundation networking / WebKit and are never
// mutated after being thrown; crossing concurrency domains with them is safe.
extension IDVerseError: @unchecked Sendable {}

extension IDVerseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidTransactionURL:
            return "The verification transaction URL is invalid."
        case .cameraPermissionDenied:
            return "Camera access was denied. Identity verification needs the camera to capture your ID and a selfie."
        case .microphonePermissionDenied:
            return "Microphone access was denied. Identity verification needs the microphone for the liveness check."
        case .cancelled:
            return "Verification was cancelled."
        case .webContentLoadFailed(let underlying):
            return "The verification page failed to load. (\(underlying.localizedDescription))"
        case .transactionCreationFailed(let underlying):
            return "Creating the verification transaction failed. (\(underlying.localizedDescription))"
        case .resultFetchFailed(let underlying):
            return "Fetching the verification result failed. (\(underlying.localizedDescription))"
        }
    }
}
