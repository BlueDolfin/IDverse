import Foundation

/// Container-wide active-flow lock (spec §6): at most one native flow, of any id and
/// either shape, per container. Released exactly when the flow's one-shot completion fires.
@MainActor
final class NativeFlowLock {
    private(set) var isActive = false
    /// Returns false if a flow is already active (caller replies `busy`).
    func begin() -> Bool {
        guard !isActive else { return false }
        isActive = true
        return true
    }
    func end() { isActive = false }
}
