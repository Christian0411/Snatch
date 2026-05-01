import Foundation

/// Pure function over `Date` and the user's home directory. Produces
/// `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif`. Locale fixed to en_US_POSIX
/// to keep filenames consistent across user locale settings.
public struct PathProvider: Sendable {
    private let home: URL
    private let timeZone: TimeZone

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                timeZone: TimeZone = .current) {
        self.home = home
        self.timeZone = timeZone
    }

    public func nextOutputURL(now: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let stamp = formatter.string(from: now)
        return home
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("snatch-\(stamp).gif")
    }
}
