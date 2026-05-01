// Tests/SnatchKitTests/GifskiEncoderTests.swift
import XCTest
@testable import SnatchKit

final class GifskiEncoderTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snatch-encoder-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_init_createsPartialFileNotFinalFile() throws {
        let outURL = tempDir.appendingPathComponent("out.gif")
        _ = try GifskiEncoder(outputURL: outURL, fps: 30, quality: 90)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path + ".partial"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outURL.path))
    }

    func test_cancel_unlinksPartial_finalNeverCreated() throws {
        let outURL = tempDir.appendingPathComponent("out.gif")
        let encoder = try GifskiEncoder(outputURL: outURL, fps: 30, quality: 90)

        encoder.cancel()

        XCTAssertFalse(FileManager.default.fileExists(atPath: outURL.path + ".partial"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outURL.path))
    }

    func test_singleFrameRoundTrip_producesValidGif() async throws {
        let outURL = tempDir.appendingPathComponent("single.gif")
        let red = try PNGLoader.fixture("frame-red")

        let encoder = try GifskiEncoder(outputURL: outURL, fps: 30, quality: 90)
        try encoder.addFrame(red, presentationTime: 0.0)
        try await encoder.finish()

        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path),
                      "Expected final .gif to exist after finish()")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outURL.path + ".partial"),
                       "Expected .partial to be renamed away by finish()")

        let decoded = try GifDecoder.decode(outURL)
        XCTAssertEqual(decoded.frameCount, 1)
        XCTAssertEqual(decoded.width, 256)
        XCTAssertEqual(decoded.height, 256)

        // Sentinel pixel: top-left should be roughly red after gifski's palette quantization.
        let (r, g, b) = decoded.pixelAt(0, 4, 4)!
        XCTAssertGreaterThan(Int(r), 200, "Expected red channel high; got \(r)")
        XCTAssertLessThan(Int(g), 60, "Expected green channel low; got \(g)")
        XCTAssertLessThan(Int(b), 60, "Expected blue channel low; got \(b)")
    }

    func test_threeFrameSequence_producesGifWithThreeFrames_correctColors() async throws {
        let outURL = tempDir.appendingPathComponent("rgb.gif")
        let red = try PNGLoader.fixture("frame-red")
        let green = try PNGLoader.fixture("frame-green")
        let blue = try PNGLoader.fixture("frame-blue")

        let encoder = try GifskiEncoder(outputURL: outURL, fps: 30, quality: 90)
        try encoder.addFrame(red, presentationTime: 0.0 / 30.0)
        try encoder.addFrame(green, presentationTime: 1.0 / 30.0)
        try encoder.addFrame(blue, presentationTime: 2.0 / 30.0)
        try await encoder.finish()

        let decoded = try GifDecoder.decode(outURL)
        XCTAssertEqual(decoded.frameCount, 3)
        XCTAssertEqual(decoded.width, 256)
        XCTAssertEqual(decoded.height, 256)

        // Frame 0 ≈ red
        let (r0, g0, b0) = decoded.pixelAt(0, 4, 4)!
        XCTAssertGreaterThan(Int(r0), 200); XCTAssertLessThan(Int(g0), 60); XCTAssertLessThan(Int(b0), 60)

        // Frame 1 ≈ green
        let (r1, g1, b1) = decoded.pixelAt(1, 4, 4)!
        XCTAssertLessThan(Int(r1), 60); XCTAssertGreaterThan(Int(g1), 200); XCTAssertLessThan(Int(b1), 60)

        // Frame 2 ≈ blue
        let (r2, g2, b2) = decoded.pixelAt(2, 4, 4)!
        XCTAssertLessThan(Int(r2), 60); XCTAssertLessThan(Int(g2), 60); XCTAssertGreaterThan(Int(b2), 200)
    }
}
