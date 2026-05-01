import Foundation
import CoreGraphics

/// UserDefaults-backed persistence for the last-recorded region. Stores the
/// rect as `[Double]` of length 4 (x, y, w, h) under a single key. Reading a
/// malformed value returns nil — the stored format is private to this file
/// and any divergence is treated as "no persisted region", not a crash.
public final class RegionStore: @unchecked Sendable {
    // UserDefaults is documented thread-safe by Apple. All mutations go through
    // `defaults.set/removeObject`, never through the array-of-doubles cache directly.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "lastRegion") {
        self.defaults = defaults
        self.key = key
    }

    public var lastRegion: CGRect? {
        guard let raw = defaults.array(forKey: key) as? [Double], raw.count == 4 else {
            return nil
        }
        return CGRect(x: raw[0], y: raw[1], width: raw[2], height: raw[3])
    }

    public func persist(_ region: CGRect) {
        let encoded: [Double] = [
            Double(region.origin.x),
            Double(region.origin.y),
            Double(region.size.width),
            Double(region.size.height),
        ]
        defaults.set(encoded, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
