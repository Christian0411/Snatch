import XCTest
@testable import SnatchKit

final class CropperHandleTests: XCTestCase {

    func test_resizeCases_containsAllEightCornersAndEdges_inExpectedOrder() {
        XCTAssertEqual(
            CropperHandle.resizeCases,
            [.topLeft, .top, .topRight, .left, .right, .bottomLeft, .bottom, .bottomRight]
        )
    }

    func test_resizeCases_doesNotIncludeBody() {
        XCTAssertFalse(CropperHandle.resizeCases.contains(.body))
    }

    func test_caseIterable_includesAllNineCases() {
        XCTAssertEqual(CropperHandle.allCases.count, 9)
    }
}
