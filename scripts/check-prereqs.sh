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
