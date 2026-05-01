import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics
import AppKit

public enum SCStreamWrapperError: Error, CustomStringConvertible {
    case permissionDenied
    case noDisplaysAvailable
    case displayNotFound(region: CGRect)
    case startFailed(underlying: Error)

    public var description: String {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is not granted. Open System Settings → Privacy & Security → Screen Recording."
        case .noDisplaysAvailable:
            return "No displays returned by SCShareableContent.current"
        case .displayNotFound(let r):
            return "No display contains region \(r)"
        case .startFailed(let e):
            return "SCStream.startCapture failed: \(e)"
        }
    }
}

/// Thin wrapper over `SCStream` lifecycle. Returns frames as
/// `AsyncStream<CMSampleBuffer>`. The caller is responsible for running
/// `FrameConverter.convert` on the queue passed to `start(...)` (spec §5).
///
/// Threading: methods are safe to call from any queue, but you should not
/// call `start` and `stop` concurrently from different tasks.
public final class SCStreamWrapper {

    private var stream: SCStream?
    private var output: StreamOutput?
    private var continuation: AsyncStream<CMSampleBuffer>.Continuation?

    public init() {}

    /// Start capture. Returns an `AsyncStream` that yields each successful
    /// `CMSampleBuffer` (status `.complete`) on the supplied `queue`. Idle /
    /// dropped status frames are silently filtered. The stream finishes when
    /// `stop()` is called or the wrapper is deinitialised.
    ///
    /// - Parameters:
    ///   - region: rectangle to capture, in points, in the global CG coord
    ///     space (origin top-left). For M2 the caller picks coordinates by
    ///     hand; M3's cropper will produce them.
    ///   - scale: applies `SCStreamConfiguration.width/height` per spec §6.
    ///   - fps: target capture rate; mapped to `minimumFrameInterval`.
    ///   - queue: the `sampleHandlerQueue` for SCStream's delegate. Conversion
    ///     is expected to run on this queue per spec §5.
    public func start(
        region: CGRect,
        scale: ScalePreset,
        fps: Int,
        queue: DispatchQueue
    ) async throws -> AsyncStream<CMSampleBuffer> {

        guard CGPreflightScreenCaptureAccess() else {
            throw SCStreamWrapperError.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
        } catch {
            throw SCStreamWrapperError.startFailed(underlying: error)
        }

        guard !content.displays.isEmpty else {
            throw SCStreamWrapperError.noDisplaysAvailable
        }

        let display: SCDisplay
        if let containing = content.displays.first(where: { $0.frame.contains(region) }) {
            display = containing
        } else if let intersecting = content.displays.first(where: { $0.frame.intersects(region) }) {
            display = intersecting
        } else {
            throw SCStreamWrapperError.displayNotFound(region: region)
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let outputSize = Self.outputSize(for: region, scale: scale, displayScale: Self.backingScaleFactor(for: display))
        let config = SCStreamConfiguration()
        config.width = outputSize.width
        config.height = outputSize.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(max(fps, 1)))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 8
        config.showsCursor = true
        config.sourceRect = Self.sourceRect(region: region, in: display)

        let (asyncStream, asyncContinuation) = AsyncStream<CMSampleBuffer>.makeStream(
            bufferingPolicy: .unbounded
        )

        let outputDelegate = StreamOutput(continuation: asyncContinuation)
        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        do {
            try scStream.addStreamOutput(outputDelegate, type: .screen, sampleHandlerQueue: queue)
            try await scStream.startCapture()
        } catch {
            asyncContinuation.finish()
            throw SCStreamWrapperError.startFailed(underlying: error)
        }

        self.stream = scStream
        self.output = outputDelegate
        self.continuation = asyncContinuation

        Log.capture.info("SCStream started: region=\(NSStringFromRect(NSRectFromCGRect(region))) scale=\(scale.rawValue, privacy: .public) fps=\(fps) outputSize=\(outputSize.width)x\(outputSize.height)")
        return asyncStream
    }

    /// Stop capture. Idempotent.
    public func stop() async {
        guard let scStream = stream else { return }
        do {
            try await scStream.stopCapture()
        } catch {
            Log.capture.error("SCStream.stopCapture failed: \(String(describing: error), privacy: .public)")
        }
        continuation?.finish()
        stream = nil
        output = nil
        continuation = nil
        Log.capture.info("SCStream stopped")
    }

    deinit {
        continuation?.finish()
    }

    // MARK: - Helpers (internal, exposed for tests)

    /// Derive the backing scale factor (e.g. 2.0 for Retina) for an SCDisplay
    /// using CGDisplayCopyDisplayMode. Falls back to 1.0 if the mode is
    /// unavailable or has zero logical width.
    static func backingScaleFactor(for display: SCDisplay) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(display.displayID) else { return 1.0 }
        let logicalWidth = mode.width
        guard logicalWidth > 0 else { return 1.0 }
        return CGFloat(mode.pixelWidth) / CGFloat(logicalWidth)
    }

    /// Map (region, scale, displayBackingScale) → SCStreamConfiguration width/height.
    /// Spec §6:
    ///   .retina   → physical pixels (region * displayBackingScaleFactor)
    ///   .standard → logical pixels  (region * 1)
    ///   .compact  → 0.5× logical    (region * 0.5)
    static func outputSize(
        for region: CGRect,
        scale: ScalePreset,
        displayScale: CGFloat
    ) -> (width: Int, height: Int) {
        let multiplier: CGFloat
        switch scale {
        case .retina:   multiplier = displayScale
        case .standard: multiplier = 1
        case .compact:  multiplier = 0.5
        }
        let w = max(1, Int((region.width * multiplier).rounded()))
        let h = max(1, Int((region.height * multiplier).rounded()))
        return (w, h)
    }

    /// Convert a global CG region to a display-local sourceRect.
    /// SCStreamConfiguration.sourceRect is in points relative to the display's
    /// own origin (top-left).
    static func sourceRect(region: CGRect, in display: SCDisplay) -> CGRect {
        let displayOrigin = display.frame.origin
        return CGRect(
            x: region.origin.x - displayOrigin.x,
            y: region.origin.y - displayOrigin.y,
            width: region.size.width,
            height: region.size.height
        )
    }
}

private final class StreamOutput: NSObject, SCStreamOutput {
    let continuation: AsyncStream<CMSampleBuffer>.Continuation

    init(continuation: AsyncStream<CMSampleBuffer>.Continuation) {
        self.continuation = continuation
        super.init()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }

        // Filter idle/blank frames. ScreenCaptureKit emits frames with
        // SCFrameStatus != .complete when nothing changed on screen; we don't
        // want those.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let info = attachments.first,
           let rawStatus = info[.status] as? Int,
           let status = SCFrameStatus(rawValue: rawStatus),
           status != .complete {
            return
        }

        continuation.yield(sampleBuffer)
    }
}
