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
}
