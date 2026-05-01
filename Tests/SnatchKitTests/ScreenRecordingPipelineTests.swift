import XCTest
@testable import SnatchKit

final class ScreenRecordingPipelineTests: XCTestCase {

    func test_initialDroppedFrames_isZero() {
        let pipeline = ScreenRecordingPipeline()
        XCTAssertEqual(pipeline.droppedFrames, 0)
    }

    func test_pipelineConformsToRecordingPipelineProtocol() {
        // Compile-time check.
        let pipeline: any RecordingPipeline = ScreenRecordingPipeline()
        _ = pipeline
    }
}
