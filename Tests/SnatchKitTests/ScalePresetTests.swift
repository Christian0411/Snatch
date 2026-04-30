import XCTest
@testable import SnatchKit

final class ScalePresetTests: XCTestCase {
    func test_rawValues_areStableForUserDefaultsPersistence() {
        XCTAssertEqual(ScalePreset.retina.rawValue, "retina")
        XCTAssertEqual(ScalePreset.standard.rawValue, "standard")
        XCTAssertEqual(ScalePreset.compact.rawValue, "compact")
    }

    func test_initFromRawValue_roundTrips() {
        for preset in [ScalePreset.retina, .standard, .compact] {
            XCTAssertEqual(ScalePreset(rawValue: preset.rawValue), preset)
        }
    }

    func test_default_isStandard() {
        XCTAssertEqual(ScalePreset.default, .standard)
    }
}
