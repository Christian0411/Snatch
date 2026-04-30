import Foundation

/// User-selectable output scale, applied at capture time via SCStreamConfiguration.
/// Persisted as a raw string in UserDefaults — keep these values stable.
public enum ScalePreset: String, Codable, CaseIterable {
    case retina    // 2× physical pixels (full Retina resolution)
    case standard  // 1× logical pixels (default)
    case compact   // 0.5× logical pixels

    public static let `default`: ScalePreset = .standard
}
