import Foundation

/// UserDefaults-backed persistence for the user-selected `ScalePreset`.
/// Returns `.standard` for malformed or missing values — same forgiving
/// shape as `RegionStore`.
public final class ScalePresetStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "scalePreset") {
        self.defaults = defaults
        self.key = key
    }

    public var current: ScalePreset {
        guard let raw = defaults.string(forKey: key),
              let preset = ScalePreset(rawValue: raw) else {
            return .standard
        }
        return preset
    }

    public func persist(_ preset: ScalePreset) {
        defaults.set(preset.rawValue, forKey: key)
    }
}
