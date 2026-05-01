import Foundation

/// UserDefaults-backed list of the most recent saved recordings, capped at
/// 5. `recents()` filters out URLs whose file no longer exists at read
/// time — the menubar's Recent Recordings ▸ submenu rebuilds on every
/// `menuWillOpen`, so the filter cost is paid only when the user looks.
public final class RecentRecordingsStore: @unchecked Sendable {
    public static let cap = 5

    private let defaults: UserDefaults
    private let key: String
    private let fileManager: FileManager

    public init(defaults: UserDefaults = .standard,
                key: String = "recentRecordings",
                fileManager: FileManager = .default) {
        self.defaults = defaults
        self.key = key
        self.fileManager = fileManager
    }

    /// Returns last-saved-first. Filters out missing files at read time.
    public func recents() -> [URL] {
        guard let raw = defaults.array(forKey: key) as? [String] else { return [] }
        return raw.compactMap { URL(fileURLWithPath: $0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// Prepends `url`. Trims to `cap`. Duplicate URLs are de-duplicated
    /// (the new entry wins).
    public func add(_ url: URL) {
        var existing = (defaults.array(forKey: key) as? [String]) ?? []
        existing.removeAll { $0 == url.path }
        existing.insert(url.path, at: 0)
        if existing.count > Self.cap {
            existing = Array(existing.prefix(Self.cap))
        }
        defaults.set(existing, forKey: key)
    }
}
