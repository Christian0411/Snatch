import Foundation
import CoreMedia
import CoreVideo
import Accelerate

/// Converts BGRA `CMSampleBuffer`s from ScreenCaptureKit into tightly-packed
/// RGBA `RGBAFrame`s. Strips row padding (`bytesPerRow > width * 4`) and
/// performs a byte-swap (BGRA → RGBA) via `vImagePermuteChannels_ARGB8888`.
///
/// Threading: not internally synchronized. Per spec §5, the conversion is
/// expected to run on `captureQueue`. Construct one per recording session.
///
/// Each returned `RGBAFrame.bytes` shares backing storage with the internal
/// buffer until the next `convert(_:)` call mutates it (Swift COW). Retain
/// the frame past the next call only after crossing a queue boundary via
/// `BridgeQueue`, which copies the value type and breaks the COW link.
public final class FrameConverter: @unchecked Sendable {
    // Per the threading doc above: not internally synchronized; must be owned
    // by `captureQueue`. The `@unchecked Sendable` conformance is honest given
    // that invariant and lets ScreenRecordingPipeline capture the converter
    // in its consumeTask closure.

    /// Single reusable destination buffer. Reallocated only if the next frame
    /// has different dimensions.
    private var buffer: Data = Data()
    private var bufferWidth: Int = 0
    private var bufferHeight: Int = 0

    public init() {}

    /// Convert one sample. Returns `nil` if the sample has no image buffer or
    /// the pixel format is unsupported (we only handle 32BGRA in M2).
    public func convert(_ sample: CMSampleBuffer) -> RGBAFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
            return nil
        }
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_32BGRA else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let srcStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dstRowBytes = width * 4
        let dstByteCount = dstRowBytes * height

        // Resize the reusable destination buffer if needed.
        if bufferWidth != width || bufferHeight != height || buffer.count != dstByteCount {
            buffer = Data(count: dstByteCount)
            bufferWidth = width
            bufferHeight = height
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        var srcVImage = vImage_Buffer(
            data: srcBase,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: srcStride
        )

        let success = buffer.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Bool in
            guard let dstBase = raw.baseAddress else { return false }
            var dstVImage = vImage_Buffer(
                data: dstBase,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: dstRowBytes
            )
            // BGRA bytes (B=0, G=1, R=2, A=3) → RGBA layout (R=0, G=1, B=2, A=3).
            // permuteMap[i] = source-channel-index for output channel i.
            var permuteMap: [UInt8] = [2, 1, 0, 3]
            let result = vImagePermuteChannels_ARGB8888(
                &srcVImage,
                &dstVImage,
                &permuteMap,
                vImage_Flags(kvImageNoFlags)
            )
            return result == kvImageNoError
        }

        guard success else { return nil }
        return RGBAFrame(bytes: buffer, width: width, height: height)
    }
}
