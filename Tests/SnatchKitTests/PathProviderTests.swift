import XCTest
@testable import SnatchKit

final class PathProviderTests: XCTestCase {

    func test_nextOutputURL_producesDesktopPathWithTimestampedFilename() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let provider = PathProvider(home: home, timeZone: TimeZone(identifier: "UTC")!)
        // 2026-05-01 14:30:22 UTC
        let date = Date(timeIntervalSince1970: 1_777_645_822)

        let url = provider.nextOutputURL(now: date)

        XCTAssertEqual(url.path, "/Users/test/Desktop/snatch-2026-05-01-14-30-22.gif")
    }

    func test_nextOutputURL_isLocaleStable() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let provider = PathProvider(home: home, timeZone: TimeZone(identifier: "UTC")!)
        let date = Date(timeIntervalSince1970: 0)  // 1970-01-01 00:00:00 UTC

        let url = provider.nextOutputURL(now: date)

        XCTAssertTrue(url.lastPathComponent.hasPrefix("snatch-1970-01-01-00-00-00"))
    }

    func test_nextOutputURL_defaultsToHomeDirectoryWhenInitWithoutArgs() {
        let provider = PathProvider()
        let url = provider.nextOutputURL()

        // Path always starts with the user's home, ends with .gif under Desktop.
        XCTAssertTrue(url.path.contains("/Desktop/snatch-"))
        XCTAssertEqual(url.pathExtension, "gif")
    }
}
