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

# Build for both Apple Silicon and Intel, then lipo the two static libs into
# a fat archive. M6 ships a universal binary (Snatch-Release.xcconfig sets
# ARCHS = $(ARCHS_STANDARD), ONLY_ACTIVE_ARCH = NO), so the static lib must
# also be universal.
cargo build --release --no-default-features --target=aarch64-apple-darwin
cargo build --release --no-default-features --target=x86_64-apple-darwin

mkdir -p "$VENDOR_DIR"
lipo -create \
  "$SRC_DIR/target/aarch64-apple-darwin/release/libgifski.a" \
  "$SRC_DIR/target/x86_64-apple-darwin/release/libgifski.a" \
  -output "$VENDOR_DIR/libgifski.a"
cp "$SRC_DIR/gifski.h" "$VENDOR_DIR/gifski.h"

echo "✅ Built libgifski.a (universal) → $VENDOR_DIR/libgifski.a"
lipo -info "$VENDOR_DIR/libgifski.a"
ls -lh "$VENDOR_DIR/libgifski.a"
