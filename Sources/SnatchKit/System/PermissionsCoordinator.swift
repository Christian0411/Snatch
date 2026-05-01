import Foundation
import Combine

/// Tracks Screen Recording permission state across the process lifetime.
/// Caches `.granted` (since once true, the running process can use it
/// freely). `.denied` and `.notDetermined` are differentiated by whether
/// `request()` has been called.
@MainActor
public final class PermissionsCoordinator: ObservableObject {

    public enum PermissionState: Equatable {
        case granted
        case denied
        case notDetermined
    }

    @Published public private(set) var state: PermissionState = .notDetermined

    public var cachedState: PermissionState { state }

    private let adapter: CGScreenCapturePermissionAdapter

    public init(adapter: CGScreenCapturePermissionAdapter = LiveCGScreenCapturePermissionAdapter()) {
        self.adapter = adapter
    }

    /// Synchronously checks the current TCC state. Once we've cached
    /// `.granted`, subsequent calls short-circuit (subsequent CG checks
    /// can return false intermittently in process; we trust our cache).
    @discardableResult
    public func preflight() -> PermissionState {
        if state == .granted { return .granted }
        let granted = adapter.preflight()
        if granted {
            state = .granted
        } else if state != .denied {
            // Don't downgrade from .denied → .notDetermined; deny is sticky.
            state = .notDetermined
        }
        Log.permissions.info("preflight → \(String(describing: self.state), privacy: .public)")
        return state
    }

    /// Fires the system prompt if not yet asked. After the user responds,
    /// state collapses to `.granted` or `.denied` for the rest of the
    /// process lifetime.
    public func request() async -> PermissionState {
        let granted = adapter.request()
        state = granted ? .granted : .denied
        Log.permissions.info("request → \(String(describing: self.state), privacy: .public)")
        return state
    }

    /// Re-runs preflight to detect revocation (e.g., user toggled off in
    /// System Settings). Call from `NSApplication.didBecomeActive` after
    /// returning from a background. Transitions `.granted → .denied` if
    /// the system now says false.
    public func observeRevocation() {
        let liveValue = adapter.preflight()
        if state == .granted && !liveValue {
            state = .denied
            Log.permissions.info("revoked: .granted → .denied")
        } else if !liveValue {
            // no-op: .denied and .notDetermined stay as-is when still false
        } else {
            // liveValue is true — upgrade to granted regardless of prior state
            state = .granted
            Log.permissions.info("re-granted: \(String(describing: self.state), privacy: .public) → .granted")
        }
    }
}
