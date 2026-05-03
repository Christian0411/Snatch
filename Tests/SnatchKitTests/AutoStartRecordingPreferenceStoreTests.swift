import XCTest
@testable import SnatchKit

final class AutoStartRecordingPreferenceStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "co.snatch.tests.AutoStart.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_isEnabled_defaultsToFalse_whenUnset() {
        let store = AutoStartRecordingPreferenceStore(defaults: defaults)
        XCTAssertFalse(store.isEnabled)
    }

    func test_setEnabled_persistsValue() {
        let store = AutoStartRecordingPreferenceStore(defaults: defaults)
        store.setEnabled(true)
        XCTAssertTrue(store.isEnabled)
        store.setEnabled(false)
        XCTAssertFalse(store.isEnabled)
    }

    func test_persistedValue_survivesNewStoreInstance() {
        AutoStartRecordingPreferenceStore(defaults: defaults).setEnabled(true)
        XCTAssertTrue(AutoStartRecordingPreferenceStore(defaults: defaults).isEnabled)
    }

    func test_AutoStartRecordingPreferenceStore_isSendable() {
        let store = AutoStartRecordingPreferenceStore(defaults: defaults)
        Self._requireSendable(store)
    }

    private static func _requireSendable<T: Sendable>(_ value: T) {}
}
