import Foundation

/// UserDefaults-backed bool: should the cropper pre-fill with the last
/// recorded region? Defaults to `true` (preserves M5 behavior on first launch).
///
/// Pattern parallels `ScalePresetStore`. `RegionStore` continues to read and
/// write the region unconditionally; this preference only gates the consumer
/// in `MenubarCoordinator.showCropper()`.
public final class RememberRegionPreferenceStore: @unchecked Sendable {
    // UserDefaults is documented thread-safe by Apple. All access goes
    // through `defaults.object(forKey:)` / `defaults.set(_:forKey:)`.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "rememberRegion") {
        self.defaults = defaults
        self.key = key
    }

    public var isEnabled: Bool {
        // `object(forKey:) as? Bool` returns nil when the key is unset, so
        // the `?? true` fallback gives us "default ON on first launch."
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: key)
    }
}
