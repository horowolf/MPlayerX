#!/bin/bash
#
# Build the arm64 mplayer that MPlayerX bundles, and stage it under
# MPlayerX/binaries/arm64/.
#
# MPlayerX is only a front end: it spawns an mplayer process and drives it over
# the slave protocol. The binary that ends up in the application bundle is
# therefore a redistributed GPL work in its own right, and this script is the
# record of exactly how it was produced. Running it should reproduce the
# committed binary.
#
# Build-time requirements (none of these are needed to *run* MPlayerX -- the
# libraries below are copied into the bundle and their install names rewritten
# to @executable_path/lib):
#
#   brew install pkgconf freetype fontconfig fribidi speex
#
# Copyright (C) 2026 the MPlayerX contributors
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.

set -euo pipefail

MPLAYER_VERSION="1.5"
MPLAYER_TARBALL="MPlayer-${MPLAYER_VERSION}.tar.xz"
MPLAYER_URL="https://mplayerhq.hu/MPlayer/releases/${MPLAYER_TARBALL}"
MPLAYER_SHA256="650cd55bb3cb44c9b39ce36dac488428559799c5f18d16d98edb2b7256cbbf85"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${REPO_ROOT}/MPlayerX/binaries/arm64"
WORK="${MPX_BUILD_DIR:-${REPO_ROOT}/build-mplayer}"

BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"

if [ "$(uname -m)" != "arm64" ]; then
    echo "error: this script must run on an arm64 Mac (found $(uname -m))." >&2
    exit 1
fi

mkdir -p "${WORK}"
cd "${WORK}"

# ---------------------------------------------------------------- fetch source
if [ ! -f "${MPLAYER_TARBALL}" ]; then
    echo "==> downloading ${MPLAYER_URL}"
    curl -fsSL -o "${MPLAYER_TARBALL}" "${MPLAYER_URL}"
fi

echo "==> verifying checksum"
echo "${MPLAYER_SHA256}  ${MPLAYER_TARBALL}" | shasum -a 256 --check --status || {
    echo "error: ${MPLAYER_TARBALL} does not match the expected SHA-256." >&2
    echo "       expected ${MPLAYER_SHA256}" >&2
    echo "       got      $(shasum -a 256 "${MPLAYER_TARBALL}" | cut -d' ' -f1)" >&2
    exit 1
}

# The release tarball bundles the FFmpeg tree that MPlayer builds against, so
# this is the complete corresponding source; nothing is pulled from git.
if [ ! -d "MPlayer-${MPLAYER_VERSION}" ]; then
    echo "==> extracting"
    tar xf "${MPLAYER_TARBALL}"
fi

cd "MPlayer-${MPLAYER_VERSION}"

# ---------------------------------------------------------------------- patch
# MPlayer 1.5 tests for a macro named `x86_64`, which no compiler defines; the
# spelling is `__x86_64__`. Harmless on arm64, where the neighbouring
# __aarch64__ test already matches, but wrong as written.
# See https://trac.mplayerhq.hu/ticket/2383
if grep -q ' defined(x86_64)' libvo/osx_objc_common.m; then
    echo "==> patching libvo/osx_objc_common.m"
    sed -i '' 's/ defined(x86_64)/ defined(__x86_64__)/' libvo/osx_objc_common.m
fi

# ------------------------------------------------------------------ configure
export PATH="${BREW_PREFIX}/bin:${PATH}"
export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

if [ ! -f config.mak ]; then
    echo "==> configuring"
    # corevideo, freetype, fontconfig and fribidi are all deliberately left to
    # autodetection rather than forced on with --enable-*. In MPlayer's
    # configure, --enable-foo means "assume yes and skip the check", which also
    # skips collecting that dependency's compiler and linker flags -- the build
    # then fails at link time with undefined _Fc* and _fribidi_* symbols. The
    # autodetected path finds them through pkg-config and records the flags.
    #
    # corevideo matters most of the four: MPlayerX renders through
    # "-vo corevideo:shared_buffer", so a build without it cannot display video
    # in the MPlayerX window at all. It is verified after configure below.
    #
    # Newer clang rejects two constructs that MPlayer 1.5 still contains, hence
    # the two -Wno- flags.
    ./configure \
        --cc=clang \
        --host-cc=clang \
        --prefix="${WORK}/prefix" \
        --disable-x11 \
        --disable-caca \
        --disable-cdparanoia \
        --disable-libbs2b \
        --extra-cflags="-Wno-int-conversion -Wno-incompatible-function-pointer-types -I${BREW_PREFIX}/include" \
        --extra-ldflags="-L${BREW_PREFIX}/lib"

    for feature in corevideo freetype fontconfig fribidi; do
        if ! grep -qE "^#define CONFIG_$(echo "${feature}" | tr '[:lower:]' '[:upper:]') 1" config.h; then
            echo "error: ${feature} was not detected; check config.log." >&2
            echo "       'brew install pkgconf freetype fontconfig fribidi speex' first." >&2
            exit 1
        fi
    done
fi

echo "==> building (this takes a while; ffmpeg is built from source)"
make -j"$(sysctl -n hw.ncpu)"

# --------------------------------------------------------------------- bundle
echo "==> staging into ${DEST}"
rm -rf "${DEST}"
mkdir -p "${DEST}/lib"
cp mplayer "${DEST}/mplayer"
chmod +x "${DEST}/mplayer"

# Copy every non-system dylib the binary pulls in, transitively, and rewrite the
# references so the bundle is self-contained and needs nothing from Homebrew.
collect_deps() {
    local target="$1"
    local dep

    otool -L "${target}" | tail -n +2 | awk '{print $1}' | while read -r dep; do
        case "${dep}" in
            /usr/lib/*|/System/*|@executable_path/*|@rpath/*|@loader_path/*)
                continue
                ;;
        esac

        local base
        base="$(basename "${dep}")"

        if [ ! -f "${DEST}/lib/${base}" ]; then
            echo "    + ${base}"
            cp "${dep}" "${DEST}/lib/${base}"
            chmod u+w "${DEST}/lib/${base}"
            install_name_tool -id "@executable_path/lib/${base}" "${DEST}/lib/${base}"
            collect_deps "${DEST}/lib/${base}"
        fi

        install_name_tool -change "${dep}" "@executable_path/lib/${base}" "${target}"
    done
}

collect_deps "${DEST}/mplayer"

# Ad-hoc sign everything we rewrote: install_name_tool invalidates the signature
# that Homebrew's dylibs and our freshly linked binary carry, and macOS on
# Apple Silicon refuses to load an arm64 image with a broken signature.
echo "==> signing"
find "${DEST}/lib" -name '*.dylib' -exec codesign --force --sign - {} \;
codesign --force --sign - "${DEST}/mplayer"

# ---------------------------------------------------------------------- verify
echo "==> verifying"
file "${DEST}/mplayer"

if otool -L "${DEST}/mplayer" | tail -n +2 | grep -vE '^\s+(/usr/lib|/System|@executable_path)'; then
    echo "error: ${DEST}/mplayer still references a path outside the bundle." >&2
    exit 1
fi

# The binary must at least start and report itself, and it must list the
# corevideo video output that MPlayerX drives.
"${DEST}/mplayer" -v 2>&1 | head -1

# Captured first rather than piped: mplayer exits non-zero after printing the
# driver list, which under `set -o pipefail` would fail the whole pipeline.
vo_list="$("${DEST}/mplayer" -vo help 2>/dev/null || true)"

if ! printf '%s\n' "${vo_list}" | grep -q '[[:space:]]corevideo[[:space:]]'; then
    echo "error: the built mplayer has no corevideo video output." >&2
    exit 1
fi

echo
echo "done. staged in ${DEST}"
echo "build tree left in ${WORK} (safe to delete)"
