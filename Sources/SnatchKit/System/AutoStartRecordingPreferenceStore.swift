import Foundation

/// UserDefaults-backed bool: should the cropper auto-fire `onRecord` the
/// instant a fresh selection commits (i.e., on `mouseUp` from `.dragging`)?
/// Default `false` (preserves M5/pre-M6 behavior — user must click Record,
/// or press Space/Return).
///
/// Pattern parallels `RememberRegionPreferenceStore`. The runtime gate also
/// requires `RememberRegionPreferenceStore.isEnabled == false` — see
/// `MenubarCoordinator.showCropper()`.
public final class AutoStartRecordingPreferenceStore: @unchecked Sendable {
    // UserDefaults is documented thread-safe by Apple. All access goes
    // through `defaults.object(forKey:)` / `defaults.set(_:forKey:)`.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "autoStartOnSelection") {
        self.defaults = defaults
        self.key = key
    }

    public var isEnabled: Bool {
        // `object(forKey:) as? Bool` returns nil when the key is unset, so
        // the `?? false` fallback gives us "default OFF on first launch."
        defaults.object(forKey: key) as? Bool ?? false
    }

    public func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: key)
    }
}
