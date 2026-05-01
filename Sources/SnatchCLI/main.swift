// Sources/SnatchCLI/main.swift
import Foundation
import ImageIO
import SnatchKit

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    snatch-cli — encode a directory of PNG frames into a single GIF.

    Usage:
      snatch-cli <fixtures-dir> <output.gif> [fps]

    Example:
      swift run snatch-cli Tests/SnatchKitTests/Fixtures /tmp/snatch-smoke.gif 30

    """.utf8))
    exit(2)
}

guard CommandLine.arguments.count >= 3 else { usage() }
let fixturesDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])
let fps = (CommandLine.arguments.count >= 4 ? Int(CommandLine.arguments[3]) : nil) ?? 30

// Find PNGs in directory, sorted by filename.
let pngURLs: [URL]
do {
    pngURLs = try FileManager.default
        .contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
} catch {
    FileHandle.standardError.write(Data("Failed to list \(fixturesDir.path): \(error)\n".utf8))
    exit(1)
}

guard !pngURLs.isEmpty else {
    FileHandle.standardError.write(Data("No PNG files found in \(fixturesDir.path)\n".utf8))
    exit(1)
}

print("Encoding \(pngURLs.count) frames @ \(fps) fps → \(outURL.path)")

// Decode each PNG inline (the CLI re-implements PNGLoader since SnatchKit doesn't ship one;
// production code receives RGBA from the capture pipeline, not from disk).
func loadPNG(_ url: URL) throws -> RGBAFrame {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw NSError(domain: "snatch-cli", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not decode \(url.lastPathComponent)"])
    }
    let w = cgImage.width, h = cgImage.height
    var bytes = Data(count: w * h * 4)
    bytes.withUnsafeMutableBytes { buf in
        let ctx = CGContext(
            data: buf.baseAddress,
            width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return RGBAFrame(bytes: bytes, width: w, height: h)
}

do {
    let encoder = try GifskiEncoder(outputURL: outURL, quality: 90)
    for (i, url) in pngURLs.enumerated() {
        let frame = try loadPNG(url)
        try encoder.addFrame(frame, presentationTime: Double(i) / Double(fps))
        print("  frame \(i + 1)/\(pngURLs.count): \(url.lastPathComponent) (\(frame.width)×\(frame.height))")
    }

    // `finish()` is async; bridge with a dispatch group for the CLI's synchronous main.
    let group = DispatchGroup()
    group.enter()
    Task {
        do {
            try await encoder.finish()
        } catch {
            FileHandle.standardError.write(Data("finish() failed: \(error)\n".utf8))
            exit(1)
        }
        group.leave()
    }
    group.wait()

    print("✅ Wrote \(outURL.path)")
} catch {
    FileHandle.standardError.write(Data("Encode failed: \(error)\n".utf8))
    exit(1)
}
