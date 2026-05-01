import XCTest
import CoreMedia
@testable import SnatchKit

final class FrameConverterTests: XCTestCase {

    func test_convert_swapsBgraToRgba() throws {
        // Source pixel: B=0x10, G=0x20, R=0x30, A=0xFF
        // Expected output pixel: R=0x30, G=0x20, B=0x10, A=0xFF
        let sample = try SampleBufferFactory.makeBGRA(
            width: 2, height: 2,
            bgra: (0x10, 0x20, 0x30, 0xFF)
        )
        let converter = FrameConverter()

        let frame = try XCTUnwrap(converter.convert(sample))

        XCTAssertEqual(frame.width, 2)
        XCTAssertEqual(frame.height, 2)
        XCTAssertEqual(frame.bytes.count, 2 * 2 * 4)

        for pixelStart in stride(from: 0, to: frame.bytes.count, by: 4) {
            XCTAssertEqual(frame.bytes[pixelStart + 0], 0x30, "R at \(pixelStart)")
            XCTAssertEqual(frame.bytes[pixelStart + 1], 0x20, "G at \(pixelStart)")
            XCTAssertEqual(frame.bytes[pixelStart + 2], 0x10, "B at \(pixelStart)")
            XCTAssertEqual(frame.bytes[pixelStart + 3], 0xFF, "A at \(pixelStart)")
        }
    }

    func test_convert_stripsRowPadding() throws {
        // Use a width that CoreVideo is very likely to pad: width 17 forces
        // row alignment >= 68 bytes, but 16-byte alignment usually pushes
        // bytesPerRow to 80.
        let width = 17
        let height = 3
        let sample = try SampleBufferFactory.makeBGRA(
            width: width, height: height,
            bgra: (0xAA, 0xBB, 0xCC, 0xFF)
        )
        let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        let actualStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        XCTAssertGreaterThanOrEqual(actualStride, width * 4)
        // We don't *require* CoreVideo to pad — but we want the test to be
        // meaningful. If the platform happens to pack tightly, this still
        // exercises the equal-stride path which is also valid.

        let converter = FrameConverter()
        let frame = try XCTUnwrap(converter.convert(sample))

        XCTAssertEqual(frame.width, width)
        XCTAssertEqual(frame.height, height)
        XCTAssertEqual(frame.bytes.count, width * height * 4,
                       "Output must be tightly packed (no padding)")

        // Spot-check the last pixel of the last row to ensure stride strip
        // didn't leave junk at the row tail.
        let lastPixel = (height - 1) * width * 4 + (width - 1) * 4
        XCTAssertEqual(frame.bytes[lastPixel + 0], 0xCC, "R")
        XCTAssertEqual(frame.bytes[lastPixel + 1], 0xBB, "G")
        XCTAssertEqual(frame.bytes[lastPixel + 2], 0xAA, "B")
        XCTAssertEqual(frame.bytes[lastPixel + 3], 0xFF, "A")
    }

    func test_convert_repeatedCalls_reuseBuffer() throws {
        let converter = FrameConverter()
        let sample = try SampleBufferFactory.makeBGRA(
            width: 8, height: 8,
            bgra: (1, 2, 3, 0xFF)
        )

        // Two convert calls of the same dimensions; both must succeed.
        // (We can't observe pool re-use directly, but we can verify
        // correctness across calls — a reset bug would surface as garbled
        // output on the second call.)
        let f1 = try XCTUnwrap(converter.convert(sample))
        let f2 = try XCTUnwrap(converter.convert(sample))

        XCTAssertEqual(f1.bytes, f2.bytes)
    }

    func test_convert_handlesDifferentDimensionsAcrossCalls() throws {
        let converter = FrameConverter()
        let small = try SampleBufferFactory.makeBGRA(width: 4, height: 4, bgra: (1, 2, 3, 0xFF))
        let large = try SampleBufferFactory.makeBGRA(width: 32, height: 32, bgra: (1, 2, 3, 0xFF))

        let smallFrame = try XCTUnwrap(converter.convert(small))
        let largeFrame = try XCTUnwrap(converter.convert(large))

        XCTAssertEqual(smallFrame.bytes.count, 4 * 4 * 4)
        XCTAssertEqual(largeFrame.bytes.count, 32 * 32 * 4)
    }
}
