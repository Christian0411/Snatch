import Foundation
import AppKit
import ScreenCaptureKit

/// Caches `SCShareableContent.current` results so the hotkey path can
/// query exclusion windows without paying the 50–200 ms per-call cost.
/// Refreshes are triggered explicitly by the menubar app on launch and
/// in response to `didChangeScreenParametersNotification` /
/// `didActivateApplicationNotification`.
@MainActor
public final class ShareableContentCache {

    /// `SCWindow`s for our own overlay NSWindows that should be excluded
    /// from capture. Indexed by `NSWindow.windowNumber` (the Int we get
    /// from AppKit) so we can re-resolve after refreshes.
    public private(set) var ourWindowNumbers: Set<Int> = []
    public private(set) var lastRefreshError: Error?

    private var cachedContent: SCShareableContent?

    public init() {}

    /// Returns the cached `[SCWindow]` filtered to our registered
    /// overlay windowNumbers. May return empty if the cache hasn't been
    /// populated yet — callers must tolerate that and accept that
    /// overlays may appear in 1-2 frames before the pre-flight refresh.
    public func excludingWindows() -> [SCWindow] {
        guard let cachedContent else { return [] }
        return cachedContent.windows.filter {
            ourWindowNumbers.contains(Int($0.windowID))
        }
    }

    /// Register an NSWindow as an overlay to exclude from capture. Must
    /// be called AFTER the NSWindow has been ordered onscreen at least
    /// once so its windowNumber is valid.
    public func addOurWindow(_ window: NSWindow) {
        let n = window.windowNumber
        guard n > 0 else {
            Log.system.error("addOurWindow with invalid windowNumber \(n, privacy: .public)")
            return
        }
        ourWindowNumbers.insert(n)
    }

    public func contains(_ window: NSWindow) -> Bool {
        ourWindowNumbers.contains(window.windowNumber)
    }

    /// Register overlay window numbers that don't correspond to a single
    /// NSWindow reference (e.g., `RecordingOverlayWindow` coordinator wrapping
    /// multiple private NSWindows). Must be called after the windows are on-
    /// screen so their windowNumbers are valid (> 0).
    public func addWindowNumbers(_ numbers: [Int]) {
        for n in numbers where n > 0 {
            ourWindowNumbers.insert(n)
        }
    }

    /// Returns true when all `numbers` are already registered for exclusion.
    public func containsWindowNumbers(_ numbers: [Int]) -> Bool {
        numbers.allSatisfy { ourWindowNumbers.contains($0) }
    }

    /// Async refresh from `SCShareableContent.current`. Errors are
    /// captured on `lastRefreshError`; the cache retains its previous
    /// value on failure (stale-but-usable).
    public func refresh() async {
        do {
            let content = try await SCShareableContent.current
            cachedContent = content
            lastRefreshError = nil
        } catch {
            lastRefreshError = error
            Log.system.error("ShareableContentCache.refresh failed: \(String(describing: error), privacy: .public)")
        }
    }
}
