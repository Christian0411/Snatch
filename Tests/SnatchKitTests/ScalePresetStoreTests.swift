import XCTest
@testable import SnatchKit

final class ScalePresetStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "co.snatch.tests.ScalePresetStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_current_isStandard_byDefault() {
        let store = ScalePresetStore(defaults: defaults)
        XCTAssertEqual(store.current, .standard)
    }

    func test_current_returnsPersistedValue() {
        let store = ScalePresetStore(defaults: defaults)
        store.persist(.retina)
        XCTAssertEqual(store.current, .retina)
    }

    func test_persistedValue_survivesNewStoreInstance() {
        ScalePresetStore(defaults: defaults).persist(.compact)
        XCTAssertEqual(ScalePresetStore(defaults: defaults).current, .compact)
    }

    func test_current_returnsStandard_whenStoredValueIsMalformed() {
        defaults.set("not-a-preset", forKey: "scalePreset")
        XCTAssertEqual(ScalePresetStore(defaults: defaults).current, .standard)
    }

    func test_ScalePresetStore_isSendable() {
        let store = ScalePresetStore(defaults: defaults)
        Self._requireSendable(store)
    }

    private static func _requireSendable<T: Sendable>(_ value: T) {}
}
