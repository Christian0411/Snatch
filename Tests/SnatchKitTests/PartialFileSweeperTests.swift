import XCTest
@testable import SnatchKit

final class PartialFileSweeperTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snatch-sweeper-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    private func write(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(name).path)
    }

    func test_sweep_deletesMatchingPartialFiles() {
        _ = write("snatch-2026-05-01-14-30-22.gif.partial")
        _ = write("snatch-2025-01-01-00-00-00.gif.partial")

        let result = PartialFileSweeper.sweep(directory: tempDir)

        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(exists("snatch-2026-05-01-14-30-22.gif.partial"))
        XCTAssertFalse(exists("snatch-2025-01-01-00-00-00.gif.partial"))
    }

    func test_sweep_leavesNonMatchingFilesAlone() {
        _ = write("snatch-2026-05-01-14-30-22.gif.partial")
        _ = write("important.gif")
        _ = write("snatch-bad-name.partial")  // not the timestamped pattern
        _ = write("snatch-2026-05-01-14-30-22.gif")  // not .partial

        _ = PartialFileSweeper.sweep(directory: tempDir)

        XCTAssertFalse(exists("snatch-2026-05-01-14-30-22.gif.partial"))
        XCTAssertTrue(exists("important.gif"))
        XCTAssertTrue(exists("snatch-bad-name.partial"))
        XCTAssertTrue(exists("snatch-2026-05-01-14-30-22.gif"))
    }

    func test_sweep_emptyDirectory_returnsEmpty() {
        let result = PartialFileSweeper.sweep(directory: tempDir)
        XCTAssertEqual(result, [])
    }

    func test_sweep_nonexistentDirectory_returnsEmpty() {
        let bogus = tempDir.appendingPathComponent("does-not-exist", isDirectory: true)
        let result = PartialFileSweeper.sweep(directory: bogus)
        XCTAssertEqual(result, [])
    }
}
