import XCTest
@testable import SnatchKit

final class RememberRegionPreferenceStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "co.snatch.tests.RememberRegion.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_isEnabled_defaultsToTrue_whenUnset() {
        let store = RememberRegionPreferenceStore(defaults: defaults)
        XCTAssertTrue(store.isEnabled)
    }

    func test_setEnabled_persistsValue() {
        let store = RememberRegionPreferenceStore(defaults: defaults)
        store.setEnabled(false)
        XCTAssertFalse(store.isEnabled)
        store.setEnabled(true)
        XCTAssertTrue(store.isEnabled)
    }

    func test_persistedValue_survivesNewStoreInstance() {
        RememberRegionPreferenceStore(defaults: defaults).setEnabled(false)
        XCTAssertFalse(RememberRegionPreferenceStore(defaults: defaults).isEnabled)
    }

    func test_RememberRegionPreferenceStore_isSendable() {
        let store = RememberRegionPreferenceStore(defaults: defaults)
        Self._requireSendable(store)
    }

    private static func _requireSendable<T: Sendable>(_ value: T) {}
}
