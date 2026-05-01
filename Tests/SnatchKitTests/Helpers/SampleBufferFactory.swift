import Foundation
import CoreMedia
import CoreVideo

enum SampleBufferFactoryError: Error {
    case pixelBufferCreationFailed(CVReturn)
    case formatDescriptionFailed(OSStatus)
    case sampleBufferCreationFailed(OSStatus)
}

enum SampleBufferFactory {

    /// Create a CMSampleBuffer wrapping a CVPixelBuffer of the given size,
    /// filled uniformly with the given BGRA pixel value.
    ///
    /// CoreVideo chooses the actual row stride for the underlying pixel
    /// buffer; it is typically `>= width * 4` with extra alignment padding,
    /// just like ScreenCaptureKit's IOSurface frames. The factory writes
    /// pixels into whatever stride CoreVideo picked and leaves any padding
    /// bytes uninitialised — `FrameConverter` is expected to skip them.
    ///
    /// - Parameters:
    ///   - width: pixel width
    ///   - height: pixel height
    ///   - bgra: 4 bytes — Blue, Green, Red, Alpha — written into every pixel
    ///   - presentationTime: PTS in seconds (mapped onto a CMTime with timescale 1_000_000)
    static func makeBGRA(
        width: Int,
        height: Int,
        bgra: (UInt8, UInt8, UInt8, UInt8),
        presentationTime: TimeInterval = 0
    ) throws -> CMSampleBuffer {
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        var pb: CVPixelBuffer?
        let cvResult = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        guard cvResult == kCVReturnSuccess, let pixelBuffer = pb else {
            throw SampleBufferFactoryError.pixelBufferCreationFailed(cvResult)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let actualStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw SampleBufferFactoryError.pixelBufferCreationFailed(-1)
        }

        for y in 0..<height {
            let row = base.advanced(by: y * actualStride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let p = row + x * 4
                p[0] = bgra.0
                p[1] = bgra.1
                p[2] = bgra.2
                p[3] = bgra.3
            }
            // Padding bytes (if any) are left uninitialised — FrameConverter
            // must skip them, never read them.
        }

        var formatDesc: CMFormatDescription?
        let fdStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard fdStatus == noErr, let fd = formatDesc else {
            throw SampleBufferFactoryError.formatDescriptionFailed(fdStatus)
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(seconds: presentationTime, preferredTimescale: 1_000_000),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let sbStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fd,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sbStatus == noErr, let sb = sampleBuffer else {
            throw SampleBufferFactoryError.sampleBufferCreationFailed(sbStatus)
        }
        return sb
    }
}
