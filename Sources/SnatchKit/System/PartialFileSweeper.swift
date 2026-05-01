import Foundation

/// Synchronously deletes orphaned `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif.partial`
/// files left behind by previous crashes. Pattern is private to Snatch:
/// only `snatch-<10 hyphen-separated digits>.gif.partial` is deleted.
public enum PartialFileSweeper {
    /// Regex source: `^snatch-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}\.gif\.partial$`
    private static let pattern = #"^snatch-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}\.gif\.partial$"#

    /// Returns the list of URLs deleted. Best-effort: errors per-file are
    /// logged and skipped, not surfaced.
    @discardableResult
    public static func sweep(directory: URL,
                             fileManager: FileManager = .default) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]) else {
            return []
        }
        let regex = try? NSRegularExpression(pattern: pattern)
        var deleted: [URL] = []
        for url in entries {
            let name = url.lastPathComponent
            guard let regex,
                  regex.numberOfMatches(in: name, range: NSRange(name.startIndex..., in: name)) == 1 else {
                continue
            }
            do {
                try fileManager.removeItem(at: url)
                deleted.append(url)
                Log.system.info("swept partial: \(name, privacy: .public)")
            } catch {
                Log.system.error("sweep failed for \(name, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        return deleted
    }
}
