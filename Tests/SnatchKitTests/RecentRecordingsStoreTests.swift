import XCTest
@testable import SnatchKit

final class RecentRecordingsStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        suiteName = "co.snatch.tests.RecentRecordings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snatch-recents-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
        defaults = nil
        suiteName = nil
        tempDir = nil
        super.tearDown()
    }

    private func writeFile(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    func test_recents_isEmpty_byDefault() {
        let store = RecentRecordingsStore(defaults: defaults)
        XCTAssertEqual(store.recents(), [])
    }

    func test_add_prependsNewURL() {
        let store = RecentRecordingsStore(defaults: defaults)
        let a = writeFile("a.gif")
        let b = writeFile("b.gif")
        store.add(a)
        store.add(b)
        XCTAssertEqual(store.recents(), [b, a])
    }

    func test_add_capsAtFive_evictingOldest() {
        let store = RecentRecordingsStore(defaults: defaults)
        let urls = (1...6).map { writeFile("r\($0).gif") }
        for u in urls { store.add(u) }
        let recents = store.recents()
        XCTAssertEqual(recents.count, 5)
        XCTAssertEqual(recents.first, urls[5])  // most recent
        XCTAssertFalse(recents.contains(urls[0]))  // oldest evicted
    }

    func test_recents_filtersOutMissingFiles() {
        let store = RecentRecordingsStore(defaults: defaults)
        let kept = writeFile("keep.gif")
        let gone = writeFile("gone.gif")
        store.add(gone)
        store.add(kept)
        try? FileManager.default.removeItem(at: gone)

        XCTAssertEqual(store.recents(), [kept])
    }

    func test_persistedRecents_surviveNewStoreInstance() {
        let url = writeFile("persisted.gif")
        RecentRecordingsStore(defaults: defaults).add(url)
        XCTAssertEqual(RecentRecordingsStore(defaults: defaults).recents(), [url])
    }

    func test_RecentRecordingsStore_isSendable() {
        let store = RecentRecordingsStore(defaults: defaults)
        Self._requireSendable(store)
    }

    private static func _requireSendable<T: Sendable>(_ value: T) {}
}
