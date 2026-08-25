#!/bin/bash
#
# Build MPlayerX and wrap it in a distributable disk image.
#
# Lives at tools/mplayerx-package.sh and locates the repo relative to
# itself; run it from anywhere, or point MPX_REPO elsewhere if needed.
#
#   ./tools/mplayerx-package.sh              build + sign ad-hoc + make a DMG
#   ./tools/mplayerx-package.sh --no-dmg     build only, leave the .app in place
#
# Signing:
#   By default the app is signed ad-hoc ("-"), which is enough to run it on
#   your own Mac. Anyone else who downloads it will get a Gatekeeper warning
#   and has to right-click > Open the first time. To sign properly, set
#   MPX_SIGN_IDENTITY to your Developer ID and notarize the resulting DMG:
#
#     MPX_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#         ./mplayerx-package.sh
#     xcrun notarytool submit MPlayerX-<ver>.dmg --keychain-profile <profile> --wait
#     xcrun stapler staple MPlayerX-<ver>.dmg
#
#   Notarization needs a paid Apple Developer account. For personal use, skip it.

set -euo pipefail

REPO="${MPX_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || true)}"
if [ -z "${REPO}" ] || [ ! -d "${REPO}/MPlayerX/MPlayerX.xcodeproj" ]; then
    echo "error: could not find the MPlayerX repository." >&2
    echo "       set MPX_REPO=/path/to/MPlayerX and re-run." >&2
    exit 1
fi

PROJECT_DIR="${REPO}/MPlayerX"
CONFIGURATION="${MPX_CONFIGURATION:-Release}"
SIGN_IDENTITY="${MPX_SIGN_IDENTITY:--}"
OUT_DIR="${MPX_OUT_DIR:-${HOME}/Desktop}"
MAKE_DMG=1

[ "${1:-}" = "--no-dmg" ] && MAKE_DMG=0

echo "==> repository    ${REPO}"
echo "==> configuration ${CONFIGURATION}"
echo "==> signing as    ${SIGN_IDENTITY}"

# Submodules hold BGHUDAppKit, UniversalDetector, Apple Remote Control and the
# localizations; a Release build copies the localizations into the bundle.
if [ ! -f "${REPO}/BGHUDAppKit/Framework/BGThemeManager.m" ]; then
    echo "==> fetching submodules"
    git -C "${REPO}" submodule update --init
fi

echo "==> building"
xcodebuild \
    -project "${PROJECT_DIR}/MPlayerX.xcodeproj" \
    -target MPlayerX \
    -configuration "${CONFIGURATION}" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    build

APP="${PROJECT_DIR}/build/${CONFIGURATION}/MPlayerX.app"

if [ ! -d "${APP}" ]; then
    echo "error: expected an app at ${APP} but there is none." >&2
    exit 1
fi

VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "${APP}/Contents/Info.plist")"

echo "==> built MPlayerX ${VERSION}"
echo "    architectures: $(lipo -archs "${APP}/Contents/MacOS/MPlayerX")"
echo "    mplayer archs: $(find "${APP}/Contents/Resources/binaries" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | tr '\n' ' ')"

MPLAYER_ARM64="${APP}/Contents/Resources/binaries/arm64/mplayer"
if [ ! -x "${MPLAYER_ARM64}" ]; then
    echo "error: no native arm64 mplayer at ${MPLAYER_ARM64}." >&2
    echo "       this DMG would silently ship Rosetta-only on Apple Silicon." >&2
    echo "       run ./tools/build-mplayer-arm64.sh in the repo first." >&2
    exit 1
fi
if ! lipo -archs "${MPLAYER_ARM64}" | grep -qw arm64; then
    echo "error: ${MPLAYER_ARM64} exists but is not built for arm64 ($(lipo -archs "${MPLAYER_ARM64}"))." >&2
    exit 1
fi

# The bundled mplayer binaries and their dylibs are nested executables. Xcode
# does not sign what it merely copies into Resources, so sign them explicitly,
# innermost first, then re-seal the bundle around them.
echo "==> signing nested binaries"
find "${APP}/Contents/Resources/binaries" -type f \
    \( -name '*.dylib' -o -name 'mplayer' \) -print0 2>/dev/null |
    while IFS= read -r -d '' bin; do
        codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none "${bin}" 2>/dev/null || true
    done

codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP}"
codesign --verify --verbose=1 "${APP}" || {
    echo "warning: the signature did not verify; the app may still run locally." >&2
}

if [ "${MAKE_DMG}" -eq 0 ]; then
    echo
    echo "done. ${APP}"
    exit 0
fi

# ------------------------------------------------------------------------ dmg
DMG="${OUT_DIR}/MPlayerX-${VERSION}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

echo "==> staging disk image"
cp -R "${APP}" "${STAGE}/MPlayerX.app"
ln -s /Applications "${STAGE}/Applications"

rm -f "${DMG}"
hdiutil create \
    -volname "MPlayerX ${VERSION}" \
    -srcfolder "${STAGE}" \
    -ov -format UDZO \
    "${DMG}" >/dev/null

SHA256="$(shasum -a 256 "${DMG}" | awk '{print $1}')"

echo
echo "done. ${DMG}"
echo
echo "SHA-256: ${SHA256}"
echo
echo "Publish that hash in the release notes themselves. A checksum uploaded"
echo "as a separate file proves nothing: anyone can attach files to a public"
echo "repository's URLs, so the hash has to live somewhere only you can write."
echo
echo "Drag MPlayerX to Applications to install."
if [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "This build is ad-hoc signed. On another Mac, right-click the app and"
    echo "choose Open the first time, or Gatekeeper will refuse to launch it."
fi
