// Tests/SnatchKitTests/GifDecoderTests.swift
import XCTest
@testable import SnatchKit

final class GifDecoderTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snatch-gifdecoder-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_decode_throwsTypeMismatch_onNonGifFile() throws {
        let url = tempDir.appendingPathComponent("not-a-gif.txt")
        try Data("hello".utf8).write(to: url)

        XCTAssertThrowsError(try GifDecoder.decode(url)) { error in
            guard case GifDecoderError.typeMismatch = error else {
                XCTFail("Expected .typeMismatch, got \(error)")
                return
            }
        }
    }

    // NOTE: emptyFrameCount path is not exercised here because synthesising a
    // zero-frame GIF that ImageIO both recognises as type "gif" AND reports
    // CGImageSourceGetCount == 0 is impractical. Approaches (a) and (b) from
    // the M2 review both caused ImageIO to throw typeMismatch instead.
    // The path is reachable in principle (a corrupt/truncated GIF with a valid
    // header but no Image Descriptor blocks) and remains guarded in production
    // code. Re-evaluate if a future macOS ImageIO version changes parsing behaviour.
}
