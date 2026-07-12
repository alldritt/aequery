#!/usr/bin/env bash
#
# build-release.sh — build universal (arm64 + x86_64) release binaries and
# package them the way the GitHub releases expect: <product>-<version>.tar.gz
# containing the binary at the archive root.
#
# Producing universal binaries lets a single release run on both Apple Silicon
# and Intel Macs. (The prior 0.4.0 binaries were arm64-only, so they failed with
# "bad CPU type in executable" on Intel Macs.)
#
# Usage:
#   Scripts/build-release.sh [VERSION] [OUTPUT_DIR]
#
#   VERSION     defaults to `git describe --tags --abbrev=0` with any product
#               prefix and leading "v" stripped (e.g. aelint-v0.4.0 -> 0.4.0).
#   OUTPUT_DIR  defaults to ./release
#
set -euo pipefail

cd "$(dirname "$0")/.."

PRODUCTS=(aequery aelint)

raw_tag="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"
default_version="${raw_tag##*-}"      # strip "aelint-" style prefix
default_version="${default_version#v}" # strip leading "v"
VERSION="${1:-${default_version:-0.0.0}}"
OUTPUT_DIR="${2:-release}"

echo "Building universal binaries for version ${VERSION}"
mkdir -p "$OUTPUT_DIR"

for product in "${PRODUCTS[@]}"; do
  echo "==> swift build --arch arm64 --arch x86_64 -c release --product ${product}"
  swift build -c release --arch arm64 --arch x86_64 --product "$product"

  # Universal artifacts land under .build/apple/Products/Release
  bin=".build/apple/Products/Release/${product}"
  if [[ ! -x "$bin" ]]; then
    echo "error: expected universal binary not found at ${bin}" >&2
    exit 1
  fi

  archs="$(lipo -archs "$bin")"
  echo "    ${product}: ${archs}"
  if [[ "$archs" != *"arm64"* || "$archs" != *"x86_64"* ]]; then
    echo "error: ${product} is not universal (got: ${archs})" >&2
    exit 1
  fi

  staging="$(mktemp -d)"
  cp "$bin" "$staging/${product}"
  chmod 755 "$staging/${product}"
  tarball="${OUTPUT_DIR}/${product}-${VERSION}.tar.gz"
  tar czf "$tarball" -C "$staging" "$product"
  rm -rf "$staging"

  echo "    wrote ${tarball} (sha256: $(shasum -a 256 "$tarball" | cut -d' ' -f1))"
done

echo "Done. Upload the tarballs in ${OUTPUT_DIR}/ as release assets."
