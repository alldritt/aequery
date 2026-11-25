#!/bin/sh
#
# Build universal (arm64 + x86_64) release tarballs for aequery and aelint, in
# the <product>-<version>.tar.gz layout the Homebrew formulas expect: a single
# binary at the root of the archive.
#
# Usage: Scripts/build-release.sh [aequery|aelint]    (default: both)
#
# Tarballs are written to $OUT_DIR (default: /tmp). The version comes from each
# product's CommandConfiguration, so bump it there before running this.
#
# A multi-arch build writes to .build/apple/Products/Release, NOT .build/release,
# which keeps whatever native build last ran there. Packaging from the old path
# silently ships a stale arm64 binary (issue #9), so the path comes from
# --show-bin-path, and each tarball's contents are checked before it's reported.

set -e
cd "$(dirname "$0")/.."

OUT_DIR=${OUT_DIR:-/tmp}
ARCH_FLAGS="--arch arm64 --arch x86_64"
EXPECTED_ARCHS="arm64 x86_64"

fail() {
    echo "error: $1" >&2
    exit 1
}

source_file() {
    case "$1" in
        aequery) echo Sources/aequery/AEQueryCommand.swift ;;
        aelint) echo Sources/aelint/AELintCommand.swift ;;
    esac
}

case "${1:-all}" in
    all) PRODUCTS="aequery aelint" ;;
    aequery | aelint) PRODUCTS=$1 ;;
    *)
        echo "usage: $0 [aequery|aelint]" >&2
        exit 2
        ;;
esac

[ -d "$OUT_DIR" ] || fail "output directory not found: $OUT_DIR"

# Resolve every version before the slow build, so a bad source file fails fast.
for product in $PRODUCTS; do
    version=$(sed -n 's/^ *version: "\([^"]*\)".*/\1/p' "$(source_file "$product")")
    [ -n "$version" ] || fail "no version found in $(source_file "$product")"
done

# shellcheck disable=SC2086 # ARCH_FLAGS is deliberately split into arguments
swift build -c release $ARCH_FLAGS
# shellcheck disable=SC2086
BIN_DIR=$(swift build -c release $ARCH_FLAGS --show-bin-path)

VERIFY_DIR=$(mktemp -d)
trap 'rm -rf "$VERIFY_DIR"' EXIT

for product in $PRODUCTS; do
    version=$(sed -n 's/^ *version: "\([^"]*\)".*/\1/p' "$(source_file "$product")")
    tarball=$OUT_DIR/$product-$version.tar.gz

    [ -x "$BIN_DIR/$product" ] || fail "$BIN_DIR/$product was not built"
    tar czf "$tarball" -C "$BIN_DIR" "$product"

    # Check what will actually ship: the archive, not the build output.
    rm -rf "${VERIFY_DIR:?}"/*
    tar xzf "$tarball" -C "$VERIFY_DIR"
    contents=$(ls "$VERIFY_DIR")
    [ "$contents" = "$product" ] || fail "$tarball contains: $contents"

    archs=$(lipo -archs "$VERIFY_DIR/$product" | tr ' ' '\n' | sort | xargs)
    if [ "$archs" != "$EXPECTED_ARCHS" ]; then
        rm -f "$tarball"
        fail "$product has architectures [$archs], expected [$EXPECTED_ARCHS]"
    fi

    built_version=$("$VERIFY_DIR/$product" --version)
    if [ "$built_version" != "$version" ]; then
        rm -f "$tarball"
        fail "$product reports version $built_version, expected $version"
    fi

    echo "$tarball ($archs) sha256 $(shasum -a 256 "$tarball" | cut -d' ' -f1)"
done
