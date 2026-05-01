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

let args = parseArgs()

let pipeline = ScreenRecordingPipeline()

do {
    try await pipeline.start(
        region: args.region,
        scale: args.scale,
        fps: args.fps,
        outputURL: args.output,
        excludingWindows: []
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

try? await Task.sleep(nanoseconds: UInt64(args.duration * 1_000_000_000))

let stopTriggerAt = CFAbsoluteTimeGetCurrent()

let outputURL: URL
do {
    outputURL = try await pipeline.stop()
} catch {
    FileHandle.standardError.write(Data("encoder.finish failed: \(error)\n".utf8))
    exit(1)
}

let stopLatencyMs = (CFAbsoluteTimeGetCurrent() - stopTriggerAt) * 1_000

print("✅ Wrote \(outputURL.path)")
print("   bridge drops: \(pipeline.droppedFrames)")
print("   stop → save latency: \(String(format: "%.1f", stopLatencyMs)) ms (target < 500 ms)")
