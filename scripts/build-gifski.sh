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

# In gifski 1.32.0 the C API (staticlib/cdylib) lives directly in the root
# crate (not a gifski-api/ subdirectory as in older layouts).
# gifski.h is at the repo root; target/release/libgifski.a is produced here.
cargo build --release --no-default-features

mkdir -p "$VENDOR_DIR"
cp "$SRC_DIR/target/release/libgifski.a" "$VENDOR_DIR/libgifski.a"
cp "$SRC_DIR/gifski.h" "$VENDOR_DIR/gifski.h"

echo "✅ Built libgifski.a → $VENDOR_DIR/libgifski.a"
ls -lh "$VENDOR_DIR/libgifski.a"
