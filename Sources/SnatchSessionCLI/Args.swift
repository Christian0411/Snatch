// Sources/SnatchSessionCLI/Args.swift
import Foundation
import SnatchKit

struct Args {
    var output: URL = PathProvider().nextOutputURL()
    var scale: ScalePreset = .standard
    var fps: Int = 30
}

func parseSessionArgs() -> Args {
    var args = Args()
    var i = 1
    let argv = CommandLine.arguments
    while i < argv.count {
        let arg = argv[i]
        switch arg {
        case "--output":
            i += 1
            guard i < argv.count else { sessionUsage() }
            args.output = URL(fileURLWithPath: argv[i])
        case "--scale":
            i += 1
            guard i < argv.count, let s = ScalePreset(rawValue: argv[i]) else { sessionUsage() }
            args.scale = s
        case "--fps":
            i += 1
            guard i < argv.count, let n = Int(argv[i]) else { sessionUsage() }
            args.fps = n
        case "-h", "--help":
            sessionUsage()
        default:
            FileHandle.standardError.write(Data("Unknown argument: \(arg)\n".utf8))
            sessionUsage()
        }
        i += 1
    }
    return args
}

func sessionUsage() -> Never {
    FileHandle.standardError.write(Data("""
    snatch-session-cli — interactive cropper + GIF recorder.

    Usage:
      snatch-session-cli [options]

    Options:
      --output PATH                       Output .gif path. Default /tmp/snatch-session.gif.
      --scale {retina|standard|compact}   Capture scale preset. Default standard.
      --fps N                             Capture frame rate. Default 30.

    Region is selected interactively via the cropper overlay.

    """.utf8))
    exit(2)
}
