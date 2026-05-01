import XCTest
import CoreMedia
@testable import SnatchKit

final class PipelineIntegrationTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snatch-pipeline-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_threeSyntheticFrames_throughPipeline_produceValidGif() async throws {
        let outURL = tempDir.appendingPathComponent("pipeline.gif")

        // BGRA bytes for primary colors
        let red   = try SampleBufferFactory.makeBGRA(width: 64, height: 64, bgra: (0, 0, 255, 0xFF))
        let green = try SampleBufferFactory.makeBGRA(width: 64, height: 64, bgra: (0, 255, 0, 0xFF))
        let blue  = try SampleBufferFactory.makeBGRA(width: 64, height: 64, bgra: (255, 0, 0, 0xFF))

        let converter = FrameConverter()
        let bridge = BridgeQueue<(RGBAFrame, TimeInterval)>(capacity: 60)
        let encoder = try GifskiEncoder(outputURL: outURL, quality: 90)

        // Producer side (mimics what would run on captureQueue).
        for (i, sample) in [red, green, blue].enumerated() {
            let frame = try XCTUnwrap(converter.convert(sample))
            bridge.enqueue((frame, Double(i) / 30.0))
        }

        // Consumer side (mimics encoderQueue).
        while let item = bridge.dequeue() {
            try encoder.addFrame(item.0, presentationTime: item.1)
        }
        try await encoder.finish()

        // Assert the GIF is valid and frame colors round-trip approximately.
        let decoded = try GifDecoder.decode(outURL)
        XCTAssertEqual(decoded.frameCount, 3)
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 64)
        XCTAssertEqual(bridge.droppedCount, 0)

        let (r0, g0, b0) = decoded.pixelAt(0, 4, 4)!
        XCTAssertGreaterThan(Int(r0), 200); XCTAssertLessThan(Int(g0), 60); XCTAssertLessThan(Int(b0), 60)
        let (r1, g1, b1) = decoded.pixelAt(1, 4, 4)!
        XCTAssertLessThan(Int(r1), 60); XCTAssertGreaterThan(Int(g1), 200); XCTAssertLessThan(Int(b1), 60)
        let (r2, g2, b2) = decoded.pixelAt(2, 4, 4)!
        XCTAssertLessThan(Int(r2), 60); XCTAssertLessThan(Int(g2), 60); XCTAssertGreaterThan(Int(b2), 200)
    }

    func test_overflow_isCapped_andDropCountReported() async throws {
        // Overflow the bridge: enqueue 70 frames into a capacity-60 queue.
        // Verify the encoder still produces a 60-frame GIF (the most recent
        // 60), and droppedCount == 10.
        //
        // gifski deduplicates consecutive frames with identical pixel content
        // into a single output frame, so a naive loop of 70 identical gray
        // frames would produce a 1-frame GIF and make the
        // `frameCount == 60` assertion meaningless. Cycling through 7
        // distinct colors guarantees no two adjacent frames are identical
        // (cycle length 7 is coprime to 60), preserving a 1:1
        // correspondence between encoded and output frames.
        let outURL = tempDir.appendingPathComponent("overflow.gif")
        let converter = FrameConverter()
        let bridge = BridgeQueue<(RGBAFrame, TimeInterval)>(capacity: 60)
        let encoder = try GifskiEncoder(outputURL: outURL, quality: 90)

        // Tuples are stored in BGRA byte order (B, G, R, A) — the format
        // ScreenCaptureKit emits and `FrameConverter` consumes. The label on
        // each line names the *output* RGB color a reader would see in the
        // produced GIF (i.e., after FrameConverter's BGRA→RGBA byte swap).
        let bgraColors: [(UInt8, UInt8, UInt8, UInt8)] = [
            (0,   0,   255, 0xFF),  // red    (R=255)
            (0,   255, 0,   0xFF),  // green  (G=255)
            (255, 0,   0,   0xFF),  // blue   (B=255)
            (0,   255, 255, 0xFF),  // yellow (R=255, G=255)
            (255, 0,   255, 0xFF),  // magenta
            (255, 255, 0,   0xFF),  // cyan   (G=255, B=255)
            (128, 128, 128, 0xFF),  // gray
        ]

        for i in 0..<70 {
            let bgra = bgraColors[i % bgraColors.count]
            let sample = try SampleBufferFactory.makeBGRA(width: 32, height: 32, bgra: bgra)
            let frame = try XCTUnwrap(converter.convert(sample))
            bridge.enqueue((frame, Double(i) / 30.0))
        }
        XCTAssertEqual(bridge.droppedCount, 10)

        while let item = bridge.dequeue() {
            try encoder.addFrame(item.0, presentationTime: item.1)
        }
        try await encoder.finish()

        let decoded = try GifDecoder.decode(outURL)
        XCTAssertEqual(decoded.frameCount, 60)
    }
}
