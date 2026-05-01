import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Test seam over CoreGraphics's screen-capture permission API.
/// Production uses `LiveCGScreenCapturePermissionAdapter`; tests inject
/// `FakeAdapter` (defined in tests) implementing this protocol.
public protocol CGScreenCapturePermissionAdapter: Sendable {
    /// Returns true if the process currently has Screen Recording permission
    /// (per `CGPreflightScreenCaptureAccess`).
    func preflight() -> Bool

    /// Fires the system permission prompt if not yet asked; returns true
    /// after the user grants.
    func request() -> Bool
}

public struct LiveCGScreenCapturePermissionAdapter: CGScreenCapturePermissionAdapter {
    public init() {}

    public func preflight() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    public func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
