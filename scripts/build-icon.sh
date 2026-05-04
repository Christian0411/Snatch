#!/usr/bin/env bash
# Regenerates the AppIcon PNGs from the camera.viewfinder SF Symbol on a
# rounded-rect background. Run only when icon design changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="${ROOT}/build/Snatch.iconset"
ASSETS="${ROOT}/App/Assets.xcassets/AppIcon.appiconset"
MASTER="${ROOT}/build/icon-1024.png"

mkdir -p "${ICONSET}"
mkdir -p "$(dirname "${MASTER}")"

# Render 1024x1024 master PNG via inline Swift.
xcrun swift - "${MASTER}" <<'SWIFT'
import AppKit
import Foundation

let outPath = CommandLine.arguments[1]

let dim: CGFloat = 1024
let cornerRadius = dim * 0.22
let bg = NSColor(srgbRed: 28.0/255, green: 28.0/255, blue: 30.0/255, alpha: 1.0)

let symbolConfig = NSImage.SymbolConfiguration(pointSize: dim * 0.62, weight: .heavy)
guard let baseSymbol = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil),
      let symbol = baseSymbol.withSymbolConfiguration(symbolConfig) else {
    fputs("symbol load failed\n", stderr)
    exit(1)
}

let img = NSImage(size: NSSize(width: dim, height: dim), flipped: false) { rect in
    NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
    bg.setFill()
    rect.fill()

    let symbolSize = symbol.size
    let symbolRect = NSRect(
        x: (rect.width - symbolSize.width) / 2,
        y: (rect.height - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )
    NSGraphicsContext.current?.saveGraphicsState()
    symbol.draw(in: symbolRect)
    NSColor.white.setFill()
    symbolRect.fill(using: .sourceAtop)
    NSGraphicsContext.current?.restoreGraphicsState()
    return true
}

guard let tiff = img.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("png encode failed\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
SWIFT

# Generate the 10 sizes.
for sz in 16 32 128 256 512; do
    /usr/bin/sips -z $sz $sz       "${MASTER}" --out "${ICONSET}/icon_${sz}x${sz}.png"     >/dev/null
    /usr/bin/sips -z $((sz*2)) $((sz*2)) "${MASTER}" --out "${ICONSET}/icon_${sz}x${sz}@2x.png" >/dev/null
done

# Move into the asset catalog (clear old icon_*.png first).
rm -f "${ASSETS}"/icon_*.png
mv "${ICONSET}"/icon_*.png "${ASSETS}/"
rmdir "${ICONSET}"

# Write Contents.json.
cat > "${ASSETS}/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16"   },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16"   },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32"   },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32"   },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "AppIcon regenerated: 10 PNGs in ${ASSETS}"
