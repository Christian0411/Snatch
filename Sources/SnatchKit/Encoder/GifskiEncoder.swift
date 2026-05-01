// Sources/SnatchKit/Encoder/GifskiEncoder.swift
import Foundation
import CGifski

public enum GifskiEncoderError: Error, CustomStringConvertible {
    case gifskiNewFailed
    case setOutputFailed(code: Int32)
    case addFrameFailed(code: Int32, frameIndex: UInt32)
    case finishFailed(code: Int32)

    public var description: String {
        switch self {
        case .gifskiNewFailed: return "gifski_new returned NULL"
        case .setOutputFailed(let code): return "gifski_set_file_output failed (code \(code))"
        case .addFrameFailed(let code, let i): return "gifski_add_frame_rgba failed at frame \(i) (code \(code))"
        case .finishFailed(let code): return "gifski_finish failed (code \(code))"
        }
    }
}

extension GifskiEncoderError: LocalizedError {
    public var errorDescription: String? { description }
}

/// Streaming wrapper over gifski's C API. Output is written to <finalURL>.partial
/// during encoding and atomically renamed to <finalURL> on `finish()`. `cancel()`
/// unlinks the partial file.
///
/// NOTE: The vendored gifski version does not expose `gifski_drop`. The handle
/// is always freed via `gifski_finish`, which blocks until pending frames flush
/// then frees the encoder. For `cancel()` with no frames, this returns
/// immediately. For cancel after partial frame submission, a progress callback
/// returning 0 triggers abort before `gifski_finish` returns.
public final class GifskiEncoder {
    // MARK: - Threading
    //
    // GifskiEncoder is NOT internally synchronized. `addFrame`, `finish`, and
    // `cancel` all mutate `gifskiPtr` and the underlying gifski state, and
    // MUST be invoked from a single serial queue (the "encoder queue").
    //
    // Per spec §5, the canonical layout is:
    //   - `encoderQueue`: serial DispatchQueue, QoS .userInitiated, owned by
    //     the orchestrator (M2's snatch-record-cli, M4's RecordingSession).
    //   - `addFrame` is called synchronously from this queue.
    //   - `finish` is async-but-blocking (`gifski_finish` blocks until all
    //     queued frames drain). Schedule it via `Task.detached` or dispatch
    //     to `encoderQueue` — never call from the main actor.
    //   - `cancel` may briefly block while `gifski_finish` drains in-flight
    //     frames, so it too must run off the main thread.
    //
    // Violating this contract corrupts the encoder state and can crash inside
    // gifski's Rust side via aliased `&mut` pointers.

    public let outputURL: URL
    private let partialURL: URL
    private var gifskiPtr: OpaquePointer?
    private var nextFrameIndex: UInt32 = 0
    private var finished = false

    /// Initialise a new gifski writer pointed at `<outputURL>.partial`.
    ///
    /// - Parameters:
    ///   - outputURL: where the final GIF will land after `finish()`.
    ///   - quality: gifski quality knob, 1–100. Default 90.
    ///
    /// Frame rate is *not* an encoder concern — gifski derives playback timing
    /// from the per-frame `presentationTime` values supplied to `addFrame`.
    /// The capture layer (`SCStreamWrapper`) controls capture rate via
    /// `SCStreamConfiguration.minimumFrameInterval`.
    public init(outputURL: URL, quality: Int = 90) throws {
        self.outputURL = outputURL
        self.partialURL = URL(fileURLWithPath: outputURL.path + ".partial")

        var settings = GifskiSettings()
        settings.width = 0
        settings.height = 0
        settings.quality = UInt8(min(max(quality, 1), 100))
        settings.fast = false
        settings.repeat = 0  // 0 = infinite loop (Netscape Loop extension); >0 = N repetitions; <0 = no loop

        guard let g = gifski_new(&settings) else {
            throw GifskiEncoderError.gifskiNewFailed
        }
        self.gifskiPtr = g

        // Ensure the partial file exists before gifski writes to it.
        FileManager.default.createFile(atPath: partialURL.path, contents: nil)

        let setResult = partialURL.path.withCString { cPath in
            gifski_set_file_output(g, cPath)
        }
        if setResult.rawValue != 0 {
            // No gifski_drop in this version; gifski_finish frees the handle.
            // Call finish to release resources — it will return quickly with
            // GIFSKI_INVALID_STATE since no frames were added.
            _ = gifski_finish(g)
            self.gifskiPtr = nil
            try? FileManager.default.removeItem(at: partialURL)
            throw GifskiEncoderError.setOutputFailed(code: Int32(setResult.rawValue))
        }
    }

    /// BLOCKING — must be called from a serial encoder queue.
    public func addFrame(_ frame: RGBAFrame, presentationTime: TimeInterval) throws {
        guard let g = gifskiPtr else { return }
        let result = frame.bytes.withUnsafeBytes { buf -> GifskiError in
            gifski_add_frame_rgba(
                g,
                nextFrameIndex,
                UInt32(frame.width),
                UInt32(frame.height),
                buf.bindMemory(to: UInt8.self).baseAddress,
                presentationTime
            )
        }
        if result.rawValue != 0 {
            throw GifskiEncoderError.addFrameFailed(code: Int32(result.rawValue), frameIndex: nextFrameIndex)
        }
        nextFrameIndex += 1
    }

    /// Flush the encoder, finalize the GIF, and atomically rename .partial → final.
    public func finish() async throws {
        guard let g = gifskiPtr else { return }
        gifskiPtr = nil
        finished = true

        let result = gifski_finish(g)  // blocks until done, then frees `g`
        if result.rawValue != 0 {
            try? FileManager.default.removeItem(at: partialURL)
            throw GifskiEncoderError.finishFailed(code: Int32(result.rawValue))
        }

        // Atomic rename .partial → final.
        try FileManager.default.moveItem(at: partialURL, to: outputURL)
    }

    /// Discard the writer and unlink the partial file. Safe to call after `finish()` or twice.
    ///
    /// May briefly block while `gifski_finish` drains any frames already queued
    /// in gifski's internal channels. For the M1 CLI use case this is fine; for
    /// M4's `RecordingSession.cancel()` (called from a UI-adjacent path) the
    /// blocking will need to be confined to a background queue.
    ///
    /// Implementation note: gifski has no `gifski_drop` in this version.
    /// We call `gifski_finish` to release the handle; with no frames submitted
    /// it returns immediately (GIFSKI_OK or GIFSKI_INVALID_STATE, both safe to ignore).
    public func cancel() {
        if let g = gifskiPtr {
            gifskiPtr = nil
            // gifski_finish frees the handle. With no frames it returns quickly.
            _ = gifski_finish(g)
        }
        try? FileManager.default.removeItem(at: partialURL)
    }

    deinit {
        // Intentionally does not call cancel() or gifski_finish().
        //
        // Rationale: gifski_finish (the only way to free the handle in this
        // vendored version, which lacks gifski_drop) also deletes the output
        // file when called with no frames — which would remove the .partial
        // file unexpectedly. Callers MUST explicitly call cancel() or finish()
        // to clean up.
        //
        // CONSEQUENCE: dropping a GifskiEncoder without finish/cancel
        // orphans gifski's worker threads (crossbeam channels + rayon pool)
        // until process exit. Acceptable for the M1 CLI use-case (short-lived
        // process). Revisit in M4 (Coordinator) where multiple encode sessions
        // run sequentially in the same process.
    }
}
