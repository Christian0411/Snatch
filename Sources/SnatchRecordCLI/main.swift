// Sources/SnatchRecordCLI/main.swift
//
// snatch-record-cli — record a fixed screen region for a fixed duration
// and write a GIF using the full M2 pipeline.
//
// Example:
//   swift run snatch-record-cli \
//     --region 0,0,640,400 --duration 2 --scale standard --fps 30 \
//     --output /tmp/snatch-smoke.gif

import Foundation
import CoreMedia
import SnatchKit

struct Args {
    var region: CGRect = CGRect(x: 0, y: 0, width: 640, height: 400)
    var duration: TimeInterval = 2.0
    var scale: ScalePreset = .standard
    var fps: Int = 30
    var output: URL = URL(fileURLWithPath: "/tmp/snatch-smoke.gif")
}

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    snatch-record-cli — record a screen region into a GIF.

    Usage:
      snatch-record-cli [options]

    Options:
      --region X,Y,W,H        Region in CG points (origin top-left). Default 0,0,640,400.
      --duration SECONDS      Recording length in seconds. Default 2.
      --scale {retina|standard|compact}   Capture scale preset. Default standard.
      --fps N                 Capture frame rate. Default 30.
      --output PATH           Output .gif path. Default /tmp/snatch-smoke.gif.

    """.utf8))
    exit(2)
}

func parseRegion(_ s: String) -> CGRect? {
    let parts = s.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 4, parts.allSatisfy({ $0 != nil }) else { return nil }
    return CGRect(x: parts[0]!, y: parts[1]!, width: parts[2]!, height: parts[3]!)
}

func parseArgs() -> Args {
    var args = Args()
    var i = 1
    let argv = CommandLine.arguments
    while i < argv.count {
        let arg = argv[i]
        switch arg {
        case "--region":
            i += 1
            guard i < argv.count, let r = parseRegion(argv[i]) else { usage() }
            args.region = r
        case "--duration":
            i += 1
            guard i < argv.count, let d = Double(argv[i]) else { usage() }
            args.duration = d
        case "--scale":
            i += 1
            guard i < argv.count, let s = ScalePreset(rawValue: argv[i]) else { usage() }
            args.scale = s
        case "--fps":
            i += 1
            guard i < argv.count, let n = Int(argv[i]) else { usage() }
            args.fps = n
        case "--output":
            i += 1
            guard i < argv.count else { usage() }
            args.output = URL(fileURLWithPath: argv[i])
        case "-h", "--help":
            usage()
        default:
            FileHandle.standardError.write(Data("Unknown argument: \(arg)\n".utf8))
            usage()
        }
        i += 1
    }
    return args
}

/// Mutex-protected `TimeInterval?` for the first-frame PTS we observe.
/// Capture queue is serial, but multiple captureQueue closures may
/// observe firstPTS — we still want explicit synchronization.
final class PTSAnchor: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval?
    func anchor(_ pts: TimeInterval) -> TimeInterval {
        lock.withLock {
            if value == nil { value = pts }
            return value!
        }
    }
}

let args = parseArgs()

let captureQueue = DispatchQueue(label: "co.snatch.capture", qos: .userInteractive)
let encoderQueue = DispatchQueue(label: "co.snatch.encoder", qos: .userInitiated)

let converter = FrameConverter()
let bridge = BridgeQueue<(RGBAFrame, TimeInterval)>(capacity: 60)
let ptsAnchor = PTSAnchor()

let encoder: GifskiEncoder
do {
    encoder = try GifskiEncoder(outputURL: args.output, quality: 90)
} catch {
    FileHandle.standardError.write(Data("Failed to create encoder: \(error)\n".utf8))
    exit(1)
}

let wrapper = SCStreamWrapper()
let stream: AsyncStream<CMSampleBuffer>
do {
    stream = try await wrapper.start(
        region: args.region,
        scale: args.scale,
        fps: args.fps,
        queue: captureQueue
    )
} catch SCStreamWrapperError.permissionDenied {
    FileHandle.standardError.write(Data("""
    Snatch needs Screen Recording permission.
    Open System Settings → Privacy & Security → Screen Recording, enable
    this binary (or the parent terminal app), then re-run.

    """.utf8))
    exit(3)
} catch {
    FileHandle.standardError.write(Data("Capture start failed: \(error)\n".utf8))
    exit(1)
}

// Pump samples until stop. Each sample is dispatched to captureQueue for
// conversion (per spec §5) and one matching encoderQueue.async pulls one
// frame from the bridge.
//
// Known M2 limitation (logged here for M4): this 1:1 dispatch couples the
// encoder-side dequeue rate to the capture-side enqueue rate. Under
// sustained back-pressure (bridge frequently full → drop-oldest), the
// encoderQueue.async count diverges from the bridge fill level, and some
// dequeues will pull `nil`. Functionally correct (gifski tolerates the
// gaps and bridge.droppedCount stays accurate) but not the cleanest
// shape. M4's RecordingSession should refactor to a producer/consumer
// pair where the encoder side runs an independent drain loop (or uses
// bridge.drain() on a tick) decoupled from the per-frame captureQueue
// closure.
let consumeTask = Task {
    for await sample in stream {
        captureQueue.async {
            guard let frame = converter.convert(sample) else { return }
            let pts = sample.presentationTimeStamp.seconds
            let base = ptsAnchor.anchor(pts)
            let relativePTS = pts - base

            let dropped = bridge.enqueue((frame, relativePTS))
            if dropped > 0 && dropped % 10 == 0 {
                Log.capture.debug("bridge drops at \(dropped, privacy: .public)")
            }

            encoderQueue.async {
                if let item = bridge.dequeue() {
                    do {
                        try encoder.addFrame(item.0, presentationTime: item.1)
                    } catch {
                        Log.encoder.error("addFrame failed: \(String(describing: error), privacy: .public)")
                    }
                }
            }
        }
    }
}

try? await Task.sleep(nanoseconds: UInt64(args.duration * 1_000_000_000))

let stopTriggerAt = CFAbsoluteTimeGetCurrent()

await wrapper.stop()
consumeTask.cancel()

// Fence: wait for any in-flight captureQueue.async closures (the last few
// frames before stop) to complete. Each such closure may dispatch one more
// encoderQueue.async; we need them all submitted to encoderQueue before the
// drain below, otherwise the drain races with late enqueues and the
// finish-task fires while frames are still trickling in.
captureQueue.sync {}

// Drain the bridge into the encoder queue so no in-flight frames are lost.
// Errors here are logged rather than swallowed — addFrame failures during
// drain still produce a useful diagnostic and let finish() report a clean
// failure if the encoder is poisoned.
encoderQueue.sync {
    while let item = bridge.dequeue() {
        do {
            try encoder.addFrame(item.0, presentationTime: item.1)
        } catch {
            Log.encoder.error("drain addFrame failed: \(String(describing: error), privacy: .public)")
        }
    }
}

// Finish the encoder OFF the calling thread per spec §5 / M2 carry-over.
// gifski_finish blocks until queued frames flush.
let finishTask = Task.detached(priority: .userInitiated) {
    try await encoder.finish()
}
do {
    try await finishTask.value
} catch {
    FileHandle.standardError.write(Data("encoder.finish failed: \(error)\n".utf8))
    exit(1)
}

let stopLatencyMs = (CFAbsoluteTimeGetCurrent() - stopTriggerAt) * 1_000

print("✅ Wrote \(args.output.path)")
print("   bridge drops: \(bridge.droppedCount)")
print("   stop → save latency: \(String(format: "%.1f", stopLatencyMs)) ms (target < 500 ms)")
