import XCTest
@testable import SnatchKit

final class RecordingSessionErrorTests: XCTestCase {

    private struct StubError: Error, CustomStringConvertible {
        var description: String { "stub error reason" }
    }

    func test_pipelineStartFailed_describesStartTransitionAndUnderlying() {
        let err = RecordingSessionError.pipelineStartFailed(underlying: StubError())
        XCTAssertNotNil(err.errorDescription)
        XCTAssertTrue(err.errorDescription!.contains("start"),
                      "expected 'start' in description: \(err.errorDescription!)")
        XCTAssertTrue(err.errorDescription!.contains("stub error reason"),
                      "expected underlying description in: \(err.errorDescription!)")
    }

    func test_pipelineStopFailed_describesStopTransitionAndUnderlying() {
        let err = RecordingSessionError.pipelineStopFailed(underlying: StubError())
        XCTAssertNotNil(err.errorDescription)
        XCTAssertTrue(err.errorDescription!.contains("stop"),
                      "expected 'stop' in description: \(err.errorDescription!)")
        XCTAssertTrue(err.errorDescription!.contains("stub error reason"),
                      "expected underlying description in: \(err.errorDescription!)")
    }
}
