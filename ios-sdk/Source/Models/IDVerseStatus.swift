import Foundation

/// Webview-level outcome (did the user finish the journey or close it).
public enum IDVerseStatus: Equatable {
    case completed
    case cancelled
}
