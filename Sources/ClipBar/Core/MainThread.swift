import Foundation

/// Hops to the main actor from any thread without re-entrancy surprises.
func onMain(_ body: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(body)
    } else {
        DispatchQueue.main.async {
            MainActor.assumeIsolated(body)
        }
    }
}
