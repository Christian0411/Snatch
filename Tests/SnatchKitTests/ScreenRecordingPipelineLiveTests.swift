import XCTest
import CoreGraphics
@testable import SnatchKit

/// End-to-end pipeline smoke test against real ScreenCaptureKit.
/// Skipped without Screen Recording permission for the host process.
final class ScreenRecordingPipelineLiveTests: XCTestCase {

    func test_oneSecondCapture_producesValidGifUnder500msStopLatency() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Screen Recording permission not granted to test runner")
        }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snatch-pipeline-live-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let pipeline = ScreenRecordingPipeline()
        try await pipeline.start(
            region: CGRect(x: 0, y: 0, width: 320, height: 240),
            scale: .standard,
            fps: 30,
            outputURL: outputURL,
            excludingWindows: []
        )

        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1.0 s

        let stopT0 = CFAbsoluteTimeGetCurrent()
        let returned = try await pipeline.stop()
        let stopLatencyMs = (CFAbsoluteTimeGetCurrent() - stopT0) * 1_000

        XCTAssertEqual(returned, outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
                      "GIF file must exist at \(outputURL.path)")
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attributes[.size] as! Int
        XCTAssertGreaterThan(size, 100,
                             "GIF file size suspiciously small: \(size) bytes")

        // Decode + sanity-check frame count. Note: SCStreamConfiguration.minimumFrameInterval
        // is a *minimum* — SCKit only emits frames when content changes, so a static-screen
        // capture (no cursor movement, no animations) can produce as few as 1 frame even at
        // 30fps. The test asserts >= 1 to verify the pipeline produced *some* valid output;
        // tighter frame-rate checks would be flaky in headless / non-interactive runs.
        let decodedGif = try GifDecoder.decode(outputURL)
        XCTAssertGreaterThanOrEqual(decodedGif.frameCount, 1,
                                     "expected at least 1 frame in capture, got \(decodedGif.frameCount)")

        XCTAssertLessThan(stopLatencyMs, 500.0,
                          "stop → file-closed latency \(stopLatencyMs) ms exceeds 500 ms target")
    }
}
