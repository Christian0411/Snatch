import XCTest
import CoreGraphics
@testable import SnatchKit

final class RegionStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "co.snatch.tests.RegionStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_lastRegion_isNil_whenNothingPersisted() {
        let store = RegionStore(defaults: defaults)
        XCTAssertNil(store.lastRegion)
    }

    func test_persist_thenLastRegion_returnsTheSameRect() {
        let store = RegionStore(defaults: defaults)
        let r = CGRect(x: 120.5, y: 240, width: 800, height: 600)
        store.persist(r)
        XCTAssertEqual(store.lastRegion, r)
    }

    func test_persist_overwritesPreviousValue() {
        let store = RegionStore(defaults: defaults)
        store.persist(CGRect(x: 0, y: 0, width: 100, height: 100))
        store.persist(CGRect(x: 50, y: 50, width: 200, height: 150))
        XCTAssertEqual(store.lastRegion, CGRect(x: 50, y: 50, width: 200, height: 150))
    }

    func test_persistedValue_survivesNewStoreInstanceOnSameDefaults() {
        // Simulates "next launch": new RegionStore over the same UserDefaults.
        RegionStore(defaults: defaults).persist(CGRect(x: 10, y: 20, width: 30, height: 40))
        let next = RegionStore(defaults: defaults)
        XCTAssertEqual(next.lastRegion, CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    func test_lastRegion_returnsNil_whenStoredValueIsMalformed() {
        // Corrupt the defaults under the hood — a 3-element array isn't a
        // valid CGRect encoding. RegionStore should return nil rather than
        // crash or trust the bogus data.
        defaults.set([10.0, 20.0, 30.0], forKey: "lastRegion")
        let store = RegionStore(defaults: defaults)
        XCTAssertNil(store.lastRegion)
    }

    func test_clear_removesPersistedValue() {
        let store = RegionStore(defaults: defaults)
        store.persist(CGRect(x: 1, y: 2, width: 3, height: 4))
        store.clear()
        XCTAssertNil(store.lastRegion)
    }
}
