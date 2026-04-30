# Snatch M1 — Encoder Smoke Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the gifski Rust C-FFI bridge works from Swift by producing a valid GIF from N RGBA frames. No screen capture, no UI. The output of M1 is a working `GifskiEncoder` library + a `snatch-cli` binary that takes a directory of PNG frames and writes a GIF.

**Architecture:** Single Swift Package (`Package.swift`) with three targets: `CGifski` (system-library wrapper around vendored `libgifski.a`), `SnatchKit` (Swift library — encoder + shared types), `SnatchCLI` (executable). gifski is built once via `scripts/build-gifski.sh` and committed under `vendor/gifski/`. We migrate to `Snatch.xcodeproj` at M3 when AppKit/SwiftUI enter the picture; for M1 plain SPM keeps the build dead simple (`swift test`, `swift run snatch-cli`).

**Tech Stack:** Swift 5.10, Swift Package Manager, gifski (Rust, statically linked), Apple ImageIO (for PNG decoding in tests + CLI), XCTest.

---

## Prerequisites (one-time, on the dev machine)

The dev needs:
- macOS 14+ (Sonoma or later)
- Xcode 15+ command-line tools (`xcode-select --install`)
- Rust toolchain (rustup) — required to build gifski once. Once `vendor/gifski/libgifski.a` is committed, future contributors don't need Rust unless they bump the gifski version.

The plan's first task verifies these.

## Spec references

This plan implements the parts of `docs/superpowers/specs/2026-04-30-snatch-design.md` covering:
- §3 Stack (gifski integration, build setup)
- §6 Shared types (`RGBAFrame`, `ScalePreset`)
- §6 Encoder layer (`GifskiEncoder`)
- §8 Crash safety / partial files (atomic rename on `finish()`, unlink on `cancel()`)
- §9 Testing strategy (unit tests for `GifskiEncoder` with fixture frames)

Out of scope for M1 (covered in later milestones):
- ScreenCaptureKit, `SCStreamWrapper`, `FrameConverter` (M2)
- Cropper UI, menubar, hotkey (M3–M5)
- `RecordingSession` state machine (M4)

## File Structure

After M1 completes, the repo looks like:

```
/Users/starship/src/snatch/
├── .gitignore                            (modified)
├── CLAUDE.md
├── README.md
├── Package.swift                         (new, root SPM manifest)
├── Sources/
│   ├── SnatchKit/
│   │   ├── Shared/
│   │   │   ├── RGBAFrame.swift           (new)
│   │   │   └── ScalePreset.swift         (new)
│   │   └── Encoder/
│   │       └── GifskiEncoder.swift       (new)
│   └── SnatchCLI/
│       └── main.swift                    (new)
├── Tests/
│   └── SnatchKitTests/
│       ├── Fixtures/
│       │   ├── frame-red.png             (new — solid red 256×256)
│       │   ├── frame-green.png           (new — solid green 256×256)
│       │   └── frame-blue.png            (new — solid blue 256×256)
│       ├── PNGLoader.swift               (new — test helper, decodes PNG → RGBAFrame)
│       ├── GifDecoder.swift              (new — test helper, decodes GIF for assertion)
│       ├── RGBAFrameTests.swift          (new)
│       ├── ScalePresetTests.swift        (new)
│       └── GifskiEncoderTests.swift      (new)
├── vendor/
│   └── gifski/
│       ├── libgifski.a                   (new, built — large binary, committed)
│       ├── gifski.h                      (new)
│       └── module.modulemap              (new)
├── scripts/
│   ├── check-prereqs.sh                  (new)
│   └── build-gifski.sh                   (new)
└── docs/
    ├── superpowers/
    │   ├── plans/
    │   │   └── 2026-04-30-m1-encoder-smoke-test.md
    │   └── specs/
    │       └── 2026-04-30-snatch-design.md
```

**File responsibilities:**
- `Package.swift` — Swift Package manifest declaring `CGifski`, `SnatchKit`, `SnatchCLI` targets and the test target.
- `Sources/SnatchKit/Shared/RGBAFrame.swift` — value type holding one RGBA-encoded frame for the encoder.
- `Sources/SnatchKit/Shared/ScalePreset.swift` — enum (`.retina`, `.standard`, `.compact`) defined in M1 even though only consumed in M2+.
- `Sources/SnatchKit/Encoder/GifskiEncoder.swift` — Swift wrapper over gifski's C API.
- `Sources/SnatchCLI/main.swift` — reads a directory of PNGs and encodes them to a GIF; provides the manual smoke-test binary.
- `Tests/SnatchKitTests/PNGLoader.swift` — XCTest helper that decodes a PNG into `RGBAFrame` via Apple's ImageIO. Used by both tests and (re-imported by) the CLI.
- `Tests/SnatchKitTests/GifDecoder.swift` — XCTest helper that reads back an encoded GIF (frame count, dimensions, sentinel pixel colors) for assertions.
- `vendor/gifski/{libgifski.a, gifski.h, module.modulemap}` — vendored Rust artifact + C header + module map for the `CGifski` SPM systemLibrary target.
- `scripts/check-prereqs.sh` — refuses to continue if Xcode CLI tools or rustup are missing.
- `scripts/build-gifski.sh` — clones gifski at a pinned version, builds the static lib + C API header, copies into `vendor/gifski/`.

---

### Task 1: Verify dev-tooling prerequisites and update `.gitignore`

**Files:**
- Create: `scripts/check-prereqs.sh`
- Modify: `.gitignore`

- [ ] **Step 1.1: Write `scripts/check-prereqs.sh`**

```bash
#!/usr/bin/env bash
# scripts/check-prereqs.sh
# Verifies the dev machine has the tools needed to build Snatch from source.
set -euo pipefail

ok=true

if ! xcode-select -p >/dev/null 2>&1; then
  echo "❌ Xcode command-line tools not installed. Run: xcode-select --install"
  ok=false
else
  echo "✅ Xcode CLI tools: $(xcode-select -p)"
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "❌ swift not on PATH"
  ok=false
else
  echo "✅ swift: $(swift --version | head -n1)"
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "❌ Rust toolchain (cargo) not installed. Run: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  ok=false
else
  echo "✅ cargo: $(cargo --version)"
fi

# macOS version
mac_version=$(sw_vers -productVersion)
mac_major=${mac_version%%.*}
if (( mac_major < 14 )); then
  echo "⚠️  macOS $mac_version detected; Snatch targets macOS 14+. Build will succeed but the resulting binary won't run here."
fi

$ok || exit 1
echo "All prerequisites satisfied."
```

- [ ] **Step 1.2: Make script executable and run it**

```bash
chmod +x scripts/check-prereqs.sh
./scripts/check-prereqs.sh
```

Expected: All three checks print `✅`. If any print `❌`, install the missing tool before continuing.

- [ ] **Step 1.3: Add `vendor/gifski-src/` to `.gitignore`**

The initial scaffold already gitignores `.build/`, `.swiftpm/`, `Package.resolved`, and `target/`. The only missing entry is the gifski source-clone directory, which `scripts/build-gifski.sh` (Task 2) creates. Append to `.gitignore`:

```gitignore

# gifski source clone (we keep only the built artifact under vendor/gifski/)
vendor/gifski-src/
```

Verify:
```bash
grep -E "^\.build/|^\.swiftpm/|^vendor/gifski-src/" .gitignore
```

Expected: at least three matching lines.

- [ ] **Step 1.4: Commit**

```bash
git add scripts/check-prereqs.sh .gitignore
git commit -m "M1: add prereqs check script and SPM gitignore entries"
```

---

### Task 2: Vendor gifski (build static lib once, commit binary)

**Files:**
- Create: `scripts/build-gifski.sh`
- Create: `vendor/gifski/libgifski.a` (binary artifact, ~5–15 MB)
- Create: `vendor/gifski/gifski.h`
- Create: `vendor/gifski/module.modulemap`

- [ ] **Step 2.1: Write `scripts/build-gifski.sh`**

```bash
#!/usr/bin/env bash
# scripts/build-gifski.sh
# Builds gifski's C API as a static library and copies it into vendor/gifski/.
# Pinned to a specific gifski version for reproducibility.
set -euo pipefail

GIFSKI_VERSION="1.32.0"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$REPO_ROOT/vendor/gifski"
SRC_DIR="$REPO_ROOT/vendor/gifski-src"

echo "Building gifski $GIFSKI_VERSION from source…"

if [ ! -d "$SRC_DIR" ]; then
  git clone --depth 1 --branch "$GIFSKI_VERSION" https://github.com/ImageOptim/gifski "$SRC_DIR"
fi

cd "$SRC_DIR"

# gifski's C API ships under the `gifski-api/` workspace member.
# `cargo build --release` in that directory produces target/release/libgifski.a + gifski.h
cd gifski-api
cargo build --release

mkdir -p "$VENDOR_DIR"
cp "$SRC_DIR/target/release/libgifski.a" "$VENDOR_DIR/libgifski.a"
cp "$SRC_DIR/gifski-api/gifski.h" "$VENDOR_DIR/gifski.h"

echo "✅ Built libgifski.a → $VENDOR_DIR/libgifski.a"
ls -lh "$VENDOR_DIR/libgifski.a"
```

> **Note:** the exact path to `libgifski.a` and `gifski.h` inside the gifski repo can shift between releases. If the build fails at the `cp` step, run `find "$SRC_DIR" -name 'libgifski.a'` and `find "$SRC_DIR" -name 'gifski.h'` to find the actual paths and update the script.

- [ ] **Step 2.2: Run the build script**

```bash
chmod +x scripts/build-gifski.sh
./scripts/build-gifski.sh
```

Expected output:
- A `cargo build` line completes successfully (may take 60-180 seconds the first time).
- Final line `✅ Built libgifski.a → /Users/starship/src/snatch/vendor/gifski/libgifski.a`.
- `ls -lh` output shows the static library, typically 5-15 MB.

- [ ] **Step 2.3: Verify `gifski.h` exposes the expected C API**

```bash
grep -E "^\s*GIFSKI_API|gifski_new|gifski_add_frame_rgba|gifski_set_file_output|gifski_finish" vendor/gifski/gifski.h
```

Expected: at least 4 matching lines. The functions `gifski_new`, `gifski_add_frame_rgba`, `gifski_set_file_output`, and `gifski_finish` (or close variants) must be present; these are what `GifskiEncoder.swift` will call.

If any function name is missing, read the full header and update the Swift wrapper in Task 7+ to use the actual names.

- [ ] **Step 2.4: Write `vendor/gifski/module.modulemap`**

```
module CGifski {
    header "gifski.h"
    link "gifski"
    export *
}
```

- [ ] **Step 2.5: Commit**

```bash
git add scripts/build-gifski.sh vendor/gifski/libgifski.a vendor/gifski/gifski.h vendor/gifski/module.modulemap
git commit -m "M1: vendor gifski 1.32.0 static lib + C header + modulemap"
```

---

### Task 3: Create the Swift Package manifest

**Files:**
- Create: `Package.swift`
- Create: `Sources/SnatchKit/.gitkeep` (placeholder so SPM resolves)
- Create: `Sources/SnatchCLI/main.swift` (minimal placeholder so SPM resolves)
- Create: `Tests/SnatchKitTests/.gitkeep`

- [ ] **Step 3.1: Write `Package.swift`**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Snatch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SnatchKit", targets: ["SnatchKit"]),
        .executable(name: "snatch-cli", targets: ["SnatchCLI"]),
    ],
    targets: [
        .systemLibrary(
            name: "CGifski",
            path: "vendor/gifski"
        ),
        .target(
            name: "SnatchKit",
            dependencies: ["CGifski"],
            path: "Sources/SnatchKit",
            linkerSettings: [
                // Bundle -L and -lgifski together so the linker sees them in order.
                // SPM's `linkedLibrary` is a separate phase and can be too late.
                .unsafeFlags(["-L", "vendor/gifski", "-lgifski"]),
            ]
        ),
        .testTarget(
            name: "SnatchKitTests",
            dependencies: ["SnatchKit"],
            path: "Tests/SnatchKitTests",
            resources: [.copy("Fixtures")]
        ),
        .executableTarget(
            name: "SnatchCLI",
            dependencies: ["SnatchKit"],
            path: "Sources/SnatchCLI"
        ),
    ]
)
```

- [ ] **Step 3.2: Create placeholder source files so SPM doesn't error on empty targets**

```bash
mkdir -p Sources/SnatchKit Sources/SnatchCLI Tests/SnatchKitTests
touch Sources/SnatchKit/.gitkeep
touch Tests/SnatchKitTests/.gitkeep
```

```swift
// Sources/SnatchCLI/main.swift
print("snatch-cli placeholder — wired up in Task 11")
```

- [ ] **Step 3.3: Verify SPM can resolve and build (will fail to link without Swift sources, but should at least compile the placeholder)**

```bash
swift build -v 2>&1 | tail -n 20
```

Expected: `swift build` either succeeds (linking the empty SnatchKit and the placeholder CLI), or fails at link time with a clear message about an empty SnatchKit target. Both are acceptable — the next task adds real Swift sources.

If it fails with "no such module CGifski" or similar, double-check `vendor/gifski/module.modulemap` exists from Task 2.

- [ ] **Step 3.4: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "M1: SPM manifest with CGifski / SnatchKit / SnatchCLI / SnatchKitTests targets"
```

---

### Task 4: Implement `RGBAFrame` (TDD)

`RGBAFrame` is a value type holding one tightly packed RGBA8 frame. No behavior beyond storage.

**Files:**
- Create: `Sources/SnatchKit/Shared/RGBAFrame.swift`
- Create: `Tests/SnatchKitTests/RGBAFrameTests.swift`

- [ ] **Step 4.1: Write the failing test**

```swift
// Tests/SnatchKitTests/RGBAFrameTests.swift
import XCTest
@testable import SnatchKit

final class RGBAFrameTests: XCTestCase {
    func test_init_storesAllFields() {
        let bytes = Data(repeating: 0xFF, count: 4 * 8 * 8)  // 8x8 RGBA, all white
        let frame = RGBAFrame(bytes: bytes, width: 8, height: 8)

        XCTAssertEqual(frame.bytes.count, 256)
        XCTAssertEqual(frame.width, 8)
        XCTAssertEqual(frame.height, 8)
    }

    func test_byteCount_matchesWidthTimesHeightTimesFour() {
        let frame = RGBAFrame(bytes: Data(repeating: 0, count: 4 * 16 * 9), width: 16, height: 9)
        XCTAssertEqual(frame.bytes.count, frame.width * frame.height * 4)
    }
}
```

- [ ] **Step 4.2: Run the test, verify it fails**

```bash
swift test --filter RGBAFrameTests 2>&1 | tail -n 10
```

Expected: compilation error, `cannot find 'RGBAFrame' in scope` or similar.

- [ ] **Step 4.3: Write the minimal implementation**

```swift
// Sources/SnatchKit/Shared/RGBAFrame.swift
import Foundation

/// One tightly packed RGBA8 frame. No row padding.
public struct RGBAFrame {
    public let bytes: Data
    public let width: Int
    public let height: Int

    public init(bytes: Data, width: Int, height: Int) {
        self.bytes = bytes
        self.width = width
        self.height = height
    }
}
```

- [ ] **Step 4.4: Run the test, verify it passes**

```bash
swift test --filter RGBAFrameTests 2>&1 | tail -n 5
```

Expected: `Test Suite 'RGBAFrameTests' passed`.

- [ ] **Step 4.5: Commit**

```bash
git add Sources/SnatchKit/Shared/RGBAFrame.swift Tests/SnatchKitTests/RGBAFrameTests.swift
git commit -m "M1: RGBAFrame value type with TDD coverage"
```

---

### Task 5: Implement `ScalePreset` (TDD)

`ScalePreset` is the user-selectable scale enum from §6 Shared Types. Defined in M1 even though it's only operationally consumed in M2+; this gets the type right early so it doesn't churn later.

**Files:**
- Create: `Sources/SnatchKit/Shared/ScalePreset.swift`
- Create: `Tests/SnatchKitTests/ScalePresetTests.swift`

- [ ] **Step 5.1: Write the failing test**

```swift
// Tests/SnatchKitTests/ScalePresetTests.swift
import XCTest
@testable import SnatchKit

final class ScalePresetTests: XCTestCase {
    func test_rawValues_areStableForUserDefaultsPersistence() {
        XCTAssertEqual(ScalePreset.retina.rawValue, "retina")
        XCTAssertEqual(ScalePreset.standard.rawValue, "standard")
        XCTAssertEqual(ScalePreset.compact.rawValue, "compact")
    }

    func test_initFromRawValue_roundTrips() {
        for preset in [ScalePreset.retina, .standard, .compact] {
            XCTAssertEqual(ScalePreset(rawValue: preset.rawValue), preset)
        }
    }

    func test_default_isStandard() {
        XCTAssertEqual(ScalePreset.default, .standard)
    }
}
```

- [ ] **Step 5.2: Run the test, verify it fails**

```bash
swift test --filter ScalePresetTests 2>&1 | tail -n 10
```

Expected: `cannot find 'ScalePreset' in scope`.

- [ ] **Step 5.3: Write the implementation**

```swift
// Sources/SnatchKit/Shared/ScalePreset.swift
import Foundation

/// User-selectable output scale, applied at capture time via SCStreamConfiguration.
/// Persisted as a raw string in UserDefaults — keep these values stable.
public enum ScalePreset: String, Codable, CaseIterable {
    case retina    // 2× physical pixels (full Retina resolution)
    case standard  // 1× logical pixels (default)
    case compact   // 0.5× logical pixels

    public static let `default`: ScalePreset = .standard
}
```

- [ ] **Step 5.4: Run the test, verify it passes**

```bash
swift test --filter ScalePresetTests 2>&1 | tail -n 5
```

Expected: all three tests pass.

- [ ] **Step 5.5: Commit**

```bash
git add Sources/SnatchKit/Shared/ScalePreset.swift Tests/SnatchKitTests/ScalePresetTests.swift
git commit -m "M1: ScalePreset enum with raw values for persistence"
```

---

### Task 6: Test fixtures + PNG / GIF helpers

We need three solid-color PNG frames and helpers that decode PNG → `RGBAFrame` and decode the resulting GIF for assertions.

**Files:**
- Create: `Tests/SnatchKitTests/Fixtures/frame-red.png`
- Create: `Tests/SnatchKitTests/Fixtures/frame-green.png`
- Create: `Tests/SnatchKitTests/Fixtures/frame-blue.png`
- Create: `Tests/SnatchKitTests/PNGLoader.swift`
- Create: `Tests/SnatchKitTests/GifDecoder.swift`

- [ ] **Step 6.1: Generate the fixture PNGs**

Use macOS's built-in `sips` to create three solid-color 256×256 PNGs. Run from repo root:

```bash
mkdir -p Tests/SnatchKitTests/Fixtures
cd Tests/SnatchKitTests/Fixtures

# Create a 1×1 base PNG, then resize and recolor
# Quickest: use Python's Pillow if available, else swift one-liner.
# Pillow path:
python3 - <<'PY'
from PIL import Image
for name, color in [("frame-red", (255, 0, 0, 255)),
                    ("frame-green", (0, 255, 0, 255)),
                    ("frame-blue", (0, 0, 255, 255))]:
    Image.new("RGBA", (256, 256), color).save(f"{name}.png")
print("OK")
PY

cd ../../..
ls -l Tests/SnatchKitTests/Fixtures
```

If `python3 -c "import PIL"` fails, fall back to a small Swift one-shot:

```bash
swift - <<'SWIFT'
import AppKit
import UniformTypeIdentifiers

let colors: [(String, NSColor)] = [
    ("frame-red", .red),
    ("frame-green", .green),
    ("frame-blue", .blue),
]

for (name, nsColor) in colors {
    let img = NSImage(size: NSSize(width: 256, height: 256))
    img.lockFocus()
    nsColor.setFill()
    NSRect(x: 0, y: 0, width: 256, height: 256).fill()
    img.unlockFocus()

    let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: "Tests/SnatchKitTests/Fixtures/\(name).png"))
    print("Wrote \(name).png")
}
SWIFT
```

Expected: three PNG files exist, each ~1-3 KB, identifiable by `file Tests/SnatchKitTests/Fixtures/frame-red.png` reporting "PNG image data, 256 x 256, 8-bit/color RGBA".

- [ ] **Step 6.2: Write `PNGLoader` (no test for the helper itself; it's used by tests below)**

```swift
// Tests/SnatchKitTests/PNGLoader.swift
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import SnatchKit

enum PNGLoaderError: Error {
    case sourceCreationFailed
    case imageCreationFailed
    case bitmapContextCreationFailed
}

enum PNGLoader {
    /// Decode a PNG file at `url` into a tightly packed RGBA8 `RGBAFrame`.
    static func load(_ url: URL) throws -> RGBAFrame {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PNGLoaderError.sourceCreationFailed
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PNGLoaderError.imageCreationFailed
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var bytes = Data(count: bytesPerRow * height)

        let result = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard result else { throw PNGLoaderError.bitmapContextCreationFailed }

        return RGBAFrame(bytes: bytes, width: width, height: height)
    }

    /// Resolve a fixture by basename (e.g., "frame-red") under Tests/SnatchKitTests/Fixtures.
    static func fixture(_ basename: String) throws -> RGBAFrame {
        let url = Bundle.module.url(forResource: basename, withExtension: "png", subdirectory: "Fixtures")!
        return try load(url)
    }
}
```

- [ ] **Step 6.3: Write `GifDecoder` test helper**

```swift
// Tests/SnatchKitTests/GifDecoder.swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct DecodedGif {
    let frameCount: Int
    let width: Int
    let height: Int
    /// (R, G, B) of pixel (x, y) in the given frame, after dequantization.
    let pixelAt: (_ frame: Int, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)?
}

enum GifDecoderError: Error {
    case sourceCreationFailed
    case typeMismatch
    case frameOutOfRange
}

enum GifDecoder {
    static func decode(_ url: URL) throws -> DecodedGif {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw GifDecoderError.sourceCreationFailed
        }
        let type = CGImageSourceGetType(source) as String?
        guard type == (UTType.gif.identifier as String) else {
            throw GifDecoderError.typeMismatch
        }

        let frameCount = CGImageSourceGetCount(source)
        precondition(frameCount > 0)

        let firstImage = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let width = firstImage.width
        let height = firstImage.height

        // Pre-decode every frame's pixel data into a flat array of (R, G, B) tuples
        // so the caller can index by (frame, x, y).
        var rasters: [Data] = []
        rasters.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                throw GifDecoderError.frameOutOfRange
            }
            let bytesPerRow = width * 4
            var bytes = Data(count: bytesPerRow * height)
            bytes.withUnsafeMutableBytes { buf in
                let ctx = CGContext(
                    data: buf.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )!
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            rasters.append(bytes)
        }

        return DecodedGif(
            frameCount: frameCount,
            width: width,
            height: height,
            pixelAt: { frame, x, y in
                guard frame >= 0, frame < rasters.count,
                      x >= 0, x < width, y >= 0, y < height else { return nil }
                let base = (y * width + x) * 4
                let raster = rasters[frame]
                return (raster[base], raster[base + 1], raster[base + 2])
            }
        )
    }
}
```

- [ ] **Step 6.4: Add a smoke test for the helpers**

```swift
// Append to Tests/SnatchKitTests/RGBAFrameTests.swift (or create FixtureTests.swift if you prefer)
final class FixtureTests: XCTestCase {
    func test_redFixture_loadsAs256x256_topLeftIsRed() throws {
        let frame = try PNGLoader.fixture("frame-red")
        XCTAssertEqual(frame.width, 256)
        XCTAssertEqual(frame.height, 256)
        // First pixel: R, G, B, A
        XCTAssertEqual(frame.bytes[0], 255)  // R
        XCTAssertEqual(frame.bytes[1], 0)    // G
        XCTAssertEqual(frame.bytes[2], 0)    // B
    }
}
```

- [ ] **Step 6.5: Run the helper tests**

```bash
swift test --filter FixtureTests 2>&1 | tail -n 10
```

Expected: pass. If fails with "Fixtures resource not found", confirm `Package.swift` has `resources: [.copy("Fixtures")]` on `SnatchKitTests`.

- [ ] **Step 6.6: Commit**

```bash
git add Tests/SnatchKitTests/Fixtures Tests/SnatchKitTests/PNGLoader.swift Tests/SnatchKitTests/GifDecoder.swift Tests/SnatchKitTests/RGBAFrameTests.swift
git commit -m "M1: PNG fixtures + PNGLoader + GifDecoder helpers"
```

---

### Task 7: `GifskiEncoder` skeleton — init / cancel (TDD)

This task implements the constructor (which initializes a gifski writer and points it at `<finalURL>.partial`) and `cancel()` (which closes the writer and unlinks the partial file). No frames yet.

**Files:**
- Create: `Sources/SnatchKit/Encoder/GifskiEncoder.swift`
- Create: `Tests/SnatchKitTests/GifskiEncoderTests.swift`

- [ ] **Step 7.1: Write the failing tests**

```swift
// Tests/SnatchKitTests/GifskiEncoderTests.swift
import XCTest
@testable import SnatchKit

final class GifskiEncoderTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snatch-encoder-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_init_createsPartialFileNotFinalFile() throws {
        let outURL = tempDir.appendingPathComponent("out.gif")
        _ = try GifskiEncoder(outputURL: outURL, fps: 30, quality: 90)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path + ".partial"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outURL.path))
    }

    func test_cancel_unlinksPartial_finalNeverCreated() throws {
        let outURL = tempDir.appendingPathComponent("out.gif")
        let encoder = try GifskiEncoder(outputURL: outURL, fps: 30, quality: 90)

        encoder.cancel()

        XCTAssertFalse(FileManager.default.fileExists(atPath: outURL.path + ".partial"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outURL.path))
    }
}
```

- [ ] **Step 7.2: Run, verify failure**

```bash
swift test --filter GifskiEncoderTests 2>&1 | tail -n 10
```

Expected: `cannot find 'GifskiEncoder' in scope`.

- [ ] **Step 7.3: Write the minimal implementation**

> **Reading the gifski header first.** Open `vendor/gifski/gifski.h` and identify the exact symbol names and signatures. The skeleton below uses what's stable in gifski 1.x, but if the names differ in the version you vendored, adapt. The function families are:
> - `gifski_new(GifskiSettings) -> gifski*` — create a writer with settings (quality, fast-mode, etc.)
> - `gifski_set_file_output(gifski*, const char* path) -> GifskiError` — set the output file (replaces older `gifski_write` callback API)
> - `gifski_finish(gifski*) -> GifskiError` — flush and close (frees the gifski struct)
> - `gifski_add_frame_rgba(gifski*, frame_index, width, height, const uint8_t* pixels, double presentation_timestamp) -> GifskiError` — add a frame
>
> Modern gifski additionally exposes `gifski_drop` (to free without finishing); if your vendored version has that, use it in `cancel()`.

```swift
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

/// Streaming wrapper over gifski's C API. Output is written to <finalURL>.partial
/// during encoding and atomically renamed to <finalURL> on `finish()`. `cancel()`
/// unlinks the partial file.
public final class GifskiEncoder {
    public let outputURL: URL
    private let partialURL: URL
    private var gifskiPtr: OpaquePointer?
    private var nextFrameIndex: UInt32 = 0
    private var finished = false

    public init(outputURL: URL, fps: Int = 30, quality: Int = 90) throws {
        self.outputURL = outputURL
        self.partialURL = outputURL.appendingPathExtension("partial")

        var settings = GifskiSettings()
        settings.quality = UInt8(min(max(quality, 1), 100))
        settings.fast = false
        settings.repeat = -1  // -1 = infinite loop (the GIF "Netscape Loop" extension)

        guard let g = gifski_new(&settings) else {
            throw GifskiEncoderError.gifskiNewFailed
        }
        self.gifskiPtr = g

        // Ensure the partial file exists / is truncated before gifski writes.
        FileManager.default.createFile(atPath: partialURL.path, contents: nil)

        let setResult = partialURL.path.withCString { cPath in
            gifski_set_file_output(g, cPath)
        }
        if setResult.rawValue != 0 {
            // gifski_drop frees the writer without flushing.
            gifski_drop(g)
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

        let result = gifski_finish(g)  // frees `g`
        if result.rawValue != 0 {
            try? FileManager.default.removeItem(at: partialURL)
            throw GifskiEncoderError.finishFailed(code: Int32(result.rawValue))
        }

        // Atomic rename .partial → final.
        try FileManager.default.moveItem(at: partialURL, to: outputURL)
    }

    /// Discard the writer and unlink the partial file. Safe to call after finish() or twice.
    public func cancel() {
        if let g = gifskiPtr {
            gifski_drop(g)
            gifskiPtr = nil
        }
        try? FileManager.default.removeItem(at: partialURL)
    }

    deinit {
        if !finished { cancel() }
    }
}
```

> **Note on `gifski_set_file_output`:** in some gifski versions, you must call this *after* spawning a writer thread — gifski's documentation specifies the order. If `swift test` produces a hang or a "writer not started" error, check the gifski C header comments and adjust by spawning a `Task` that calls a `gifski_write` (legacy) or by following the order documented in `gifski.h`.

- [ ] **Step 7.4: Run, verify it builds and tests pass**

```bash
swift test --filter GifskiEncoderTests 2>&1 | tail -n 15
```

Expected: both `test_init_createsPartialFileNotFinalFile` and `test_cancel_unlinksPartial_finalNeverCreated` pass.

If you see linker errors mentioning `_gifski_new` or similar, re-check `Package.swift`'s `linkerSettings.unsafeFlags(["-L", "vendor/gifski"])` and the `module.modulemap` from Task 2.

- [ ] **Step 7.5: Commit**

```bash
git add Sources/SnatchKit/Encoder/GifskiEncoder.swift Tests/SnatchKitTests/GifskiEncoderTests.swift
git commit -m "M1: GifskiEncoder skeleton (init + cancel) with partial-file lifecycle"
```

---

### Task 8: `GifskiEncoder.addFrame` — single frame (TDD)

Verify a single fixture frame produces a valid GIF.

**Files:**
- Modify: `Tests/SnatchKitTests/GifskiEncoderTests.swift`

- [ ] **Step 8.1: Add the failing test**

Append to `GifskiEncoderTests`:

```swift
func test_singleFrameRoundTrip_producesValidGif() async throws {
    let outURL = tempDir.appendingPathComponent("single.gif")
    let red = try PNGLoader.fixture("frame-red")

    let encoder = try GifskiEncoder(outputURL: outURL, fps: 30, quality: 90)
    try encoder.addFrame(red, presentationTime: 0.0)
    try await encoder.finish()

    XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path),
                  "Expected final .gif to exist after finish()")
    XCTAssertFalse(FileManager.default.fileExists(atPath: outURL.path + ".partial"),
                   "Expected .partial to be renamed away by finish()")

    let decoded = try GifDecoder.decode(outURL)
    XCTAssertEqual(decoded.frameCount, 1)
    XCTAssertEqual(decoded.width, 256)
    XCTAssertEqual(decoded.height, 256)

    // Sentinel pixel: top-left should be roughly red after gifski's palette quantization.
    let (r, g, b) = decoded.pixelAt(0, 4, 4)!
    XCTAssertGreaterThan(Int(r), 200, "Expected red channel high; got \(r)")
    XCTAssertLessThan(Int(g), 60, "Expected green channel low; got \(g)")
    XCTAssertLessThan(Int(b), 60, "Expected blue channel low; got \(b)")
}
```

- [ ] **Step 8.2: Run, verify it passes (the implementation from Task 7 already supports addFrame)**

```bash
swift test --filter GifskiEncoderTests/test_singleFrameRoundTrip 2>&1 | tail -n 15
```

Expected: pass.

If it fails with a gifski runtime error, the most likely cause is a misordering of `gifski_new` / `gifski_set_file_output` / `gifski_add_frame_rgba`. Check the `gifski.h` comments — some versions require a separate writer thread. If needed, add a `Task.detached` / `pthread_create` writer in the encoder; document the change in the next commit.

- [ ] **Step 8.3: Commit**

```bash
git add Tests/SnatchKitTests/GifskiEncoderTests.swift
git commit -m "M1: single-frame encode round-trip test"
```

---

### Task 9: `GifskiEncoder.addFrame` — multiple frames (TDD)

Verify three sequential fixture frames produce a 3-frame GIF.

**Files:**
- Modify: `Tests/SnatchKitTests/GifskiEncoderTests.swift`

- [ ] **Step 9.1: Add the failing test**

```swift
func test_threeFrameSequence_producesGifWithThreeFrames_correctColors() async throws {
    let outURL = tempDir.appendingPathComponent("rgb.gif")
    let red = try PNGLoader.fixture("frame-red")
    let green = try PNGLoader.fixture("frame-green")
    let blue = try PNGLoader.fixture("frame-blue")

    let encoder = try GifskiEncoder(outputURL: outURL, fps: 30, quality: 90)
    try encoder.addFrame(red, presentationTime: 0.0 / 30.0)
    try encoder.addFrame(green, presentationTime: 1.0 / 30.0)
    try encoder.addFrame(blue, presentationTime: 2.0 / 30.0)
    try await encoder.finish()

    let decoded = try GifDecoder.decode(outURL)
    XCTAssertEqual(decoded.frameCount, 3)
    XCTAssertEqual(decoded.width, 256)
    XCTAssertEqual(decoded.height, 256)

    // Frame 0 ≈ red
    let (r0, g0, b0) = decoded.pixelAt(0, 4, 4)!
    XCTAssertGreaterThan(Int(r0), 200); XCTAssertLessThan(Int(g0), 60); XCTAssertLessThan(Int(b0), 60)

    // Frame 1 ≈ green
    let (r1, g1, b1) = decoded.pixelAt(1, 4, 4)!
    XCTAssertLessThan(Int(r1), 60); XCTAssertGreaterThan(Int(g1), 200); XCTAssertLessThan(Int(b1), 60)

    // Frame 2 ≈ blue
    let (r2, g2, b2) = decoded.pixelAt(2, 4, 4)!
    XCTAssertLessThan(Int(r2), 60); XCTAssertLessThan(Int(g2), 60); XCTAssertGreaterThan(Int(b2), 200)
}
```

- [ ] **Step 9.2: Run, verify it passes**

```bash
swift test --filter GifskiEncoderTests/test_threeFrameSequence 2>&1 | tail -n 15
```

Expected: pass — three distinct frames, each pixel sentinel matches its expected color.

- [ ] **Step 9.3: Commit**

```bash
git add Tests/SnatchKitTests/GifskiEncoderTests.swift
git commit -m "M1: three-frame encode round-trip with per-frame color assertions"
```

---

### Task 10: `GifskiEncoder.cancel` after frames (TDD)

Verify that cancelling mid-encode deletes the partial file and never produces a final.

**Files:**
- Modify: `Tests/SnatchKitTests/GifskiEncoderTests.swift`

- [ ] **Step 10.1: Add the failing test**

```swift
func test_cancelMidEncode_deletesPartial_noFinalFile() throws {
    let outURL = tempDir.appendingPathComponent("cancelled.gif")
    let red = try PNGLoader.fixture("frame-red")

    let encoder = try GifskiEncoder(outputURL: outURL, fps: 30, quality: 90)
    try encoder.addFrame(red, presentationTime: 0.0)
    try encoder.addFrame(red, presentationTime: 1.0 / 30.0)
    encoder.cancel()

    XCTAssertFalse(FileManager.default.fileExists(atPath: outURL.path + ".partial"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: outURL.path))
}
```

- [ ] **Step 10.2: Run, verify it passes**

```bash
swift test --filter GifskiEncoderTests/test_cancelMidEncode 2>&1 | tail -n 10
```

Expected: pass.

- [ ] **Step 10.3: Commit**

```bash
git add Tests/SnatchKitTests/GifskiEncoderTests.swift
git commit -m "M1: cancel-after-frames test (partial file is unlinked)"
```

---

### Task 11: `snatch-cli` smoke executable

A command-line tool that takes a directory of PNG frames and produces a GIF. The point is *human* validation — open the resulting GIF in Preview/Finder and confirm it looks right.

**Files:**
- Modify: `Sources/SnatchCLI/main.swift`

- [ ] **Step 11.1: Write the CLI**

```swift
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
    let encoder = try GifskiEncoder(outputURL: outURL, fps: fps, quality: 90)
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
```

- [ ] **Step 11.2: Build and smoke-test the CLI**

```bash
swift build --product snatch-cli 2>&1 | tail -n 5
swift run snatch-cli Tests/SnatchKitTests/Fixtures /tmp/snatch-m1-smoke.gif 30
```

Expected output:
```
Encoding 3 frames @ 30 fps → /tmp/snatch-m1-smoke.gif
  frame 1/3: frame-blue.png (256×256)
  frame 2/3: frame-green.png (256×256)
  frame 3/3: frame-red.png (256×256)
✅ Wrote /tmp/snatch-m1-smoke.gif
```

- [ ] **Step 11.3: Visually confirm the GIF**

```bash
open /tmp/snatch-m1-smoke.gif
```

This opens the GIF in Preview (or your default viewer). Expected: a 256×256 GIF that cycles through three solid-color frames (blue → green → red, in alphabetical filename order).

If the GIF doesn't animate or shows a single frame, the encoder is producing a bad GIF — investigate before proceeding.

- [ ] **Step 11.4: Commit**

```bash
git add Sources/SnatchCLI/main.swift
git commit -m "M1: snatch-cli executable for human GIF smoke verification"
```

---

### Task 12: M1 sign-off — full test suite + fresh build

This is the milestone gate. All M1 unit tests pass, the CLI produces a working GIF, the build is clean.

**Files:** none (verification only).

- [ ] **Step 12.1: Run the full test suite**

```bash
swift test 2>&1 | tail -n 15
```

Expected: every test in `SnatchKitTests` passes. Specifically:
- `RGBAFrameTests` (2 tests)
- `ScalePresetTests` (3 tests)
- `FixtureTests` (1 test)
- `GifskiEncoderTests` (5 tests: init creates partial, cancel unlinks partial, single-frame, three-frame, cancel-mid-encode)

11 tests pass total.

- [ ] **Step 12.2: Clean build verification**

```bash
swift package clean
swift build 2>&1 | tail -n 5
```

Expected: `Build complete!` with zero warnings (treat warnings as alerts, not blockers — but if there's a warning about unused gifski symbols or similar, look into it).

- [ ] **Step 12.3: CLI smoke run on fixtures**

```bash
rm -f /tmp/snatch-m1-final.gif
swift run snatch-cli Tests/SnatchKitTests/Fixtures /tmp/snatch-m1-final.gif 10
file /tmp/snatch-m1-final.gif
```

Expected: `file` reports something like `GIF image data, version 89a, 256 x 256` and the file size is non-trivial (a few KB).

- [ ] **Step 12.4: Tag the M1 milestone**

```bash
git tag m1-encoder-smoke-test
git log --oneline -10
```

Expected: a clean linear history of M1 commits ending in this milestone tag.

---

## Acceptance criteria for M1

- [ ] `swift test` passes 11 tests with no failures
- [ ] `swift build` succeeds with no errors
- [ ] `swift run snatch-cli Tests/SnatchKitTests/Fixtures /tmp/snatch-m1-smoke.gif 10` produces a valid 3-frame GIF
- [ ] The resulting GIF opens in Preview and animates correctly (blue → green → red, ~3 fps for visibility)
- [ ] `vendor/gifski/libgifski.a` is committed (no Rust toolchain needed for downstream contributors unless bumping the gifski version)
- [ ] The `m1-encoder-smoke-test` git tag is in place
- [ ] No third-party Swift Package dependencies (verify: `cat Package.resolved` should not exist or be empty)

## What's deferred to later milestones

- ScreenCaptureKit, frame conversion, capture-to-encode pipeline (M2)
- Cropper UI, `NSWindow`, drag/handles (M3)
- `RecordingSession` state machine (M4)
- Menubar, hotkey, system polish, pre-warm strategy (M5)
- Smoke pass + signed `.app` ship (M6)

After M1 lands and is validated, re-invoke `/superpowers:writing-plans` against the same spec to generate the M2 plan.
