# Third-party components

MPlayerX itself is licensed under the GNU General Public License, version 2 or
later; see [COPYING](COPYING) and the header of any source file.

This document records every third-party component that is redistributed as part
of this repository or of a built `MPlayerX.app`, together with its license and
the exact upstream source it was produced from. It exists so that the binary
redistribution obligations of the GPL — in particular section 3 of GPLv2, which
requires that the corresponding source of any binary you ship is available —
can be met.

## Redistributed as prebuilt binaries inside the application bundle

This lives under `MPlayerX/binaries/arm64/` and is copied into
`MPlayerX.app/Contents/Resources/binaries/arm64/` at build time. It is not
committed to the repository — it is built locally, see below.

### MPlayer

| | |
|---|---|
| Location | `MPlayerX/binaries/arm64/mplayer` |
| License | GNU General Public License, version 2 |
| Upstream | <https://www.mplayerhq.hu/> |

MPlayerX is a graphical front end; it does not decode anything itself. All
playback is performed by an `mplayer` process that MPlayerX spawns and drives
over the MPlayer slave protocol.

**arm64 build.** Produced from the official MPlayer 1.5 release tarball,
<https://mplayerhq.hu/MPlayer/releases/MPlayer-1.5.tar.xz>, SHA-256
`650cd55bb3cb44c9b39ce36dac488428559799c5f18d16d98edb2b7256cbbf85`. That
tarball bundles the FFmpeg tree that MPlayer builds against, so it is the
complete corresponding source. The script that fetches, patches and configures
it is committed alongside this file as
[`tools/build-mplayer-arm64.sh`](tools/build-mplayer-arm64.sh); running it
reproduces the shipped binary.

**x86_64 and i386 builds — removed.** These were inherited from the original
MPlayerX repository, committed as prebuilt binaries in 2011 without a record
of which revision or configure line produced them. They self-reported as
`MPlayer UNKNOWN-4.2.1 (C) 2000-2011 MPlayer Team`, which indicates a
development snapshot rather than a release, so the exact corresponding source
could never be identified after the fact — a pre-existing compliance gap
carried over from upstream. This branch now builds arm64 only and no longer
ships either binary, which removes that gap along with the x86_64 app slice
that used to select between them. They remain available in the git history of
`MPlayerX/binaries/x86_64/` and `MPlayerX/binaries/m32/` for anyone building
an Intel version instead, with the same unresolved-provenance caveat as
before.

### Support libraries used by MPlayer

Shipped next to the `mplayer` executable in `binaries/arm64/lib/` and loaded
through `@executable_path/lib`.

| Library | License | Upstream |
|---|---|---|
| `libfreetype.6.dylib` | FreeType License (BSD-style) or GPLv2, at your option | <https://freetype.org/> |
| `libfontconfig.1.dylib` | MIT-style (fontconfig license) | <https://www.freedesktop.org/wiki/Software/fontconfig/> |
| `libfribidi.0.dylib` | GNU Lesser General Public License, version 2.1 or later | <https://github.com/fribidi/fribidi> |
| `libspeex.1.dylib` | BSD 3-Clause (Xiph.Org) | <https://www.speex.org/> |
| `libpng16.16.dylib` | PNG Reference Library License v2 (zlib-style) | <http://www.libpng.org/pub/png/libpng.html> |
| `libintl.8.dylib` | GNU Lesser General Public License, version 2.1 or later (GNU gettext runtime) | <https://www.gnu.org/software/gettext/> |

`libpng16` and `libintl` are transitive: they are pulled in by freetype and
fontconfig respectively rather than used by MPlayer directly.

The versions bundled for arm64 are recorded in
[`tools/build-mplayer-arm64.sh`](tools/build-mplayer-arm64.sh), which copies
them out of the build environment and rewrites their install names. The 2011
x86_64 and i386 library bundles predated these dependencies and have been
removed along with those `mplayer` binaries.

## Redistributed as a resource

### WenQuanYi Micro Hei

| | |
|---|---|
| Location | `MPlayerX/wqy-microhei.ttc` |
| License | Apache License, Version 2.0, as declared in the font's own name table |
| Copyright | 2008-2009 WenQuanYi Board of Trustees and Qianqian Fang |
| Version | 0.2.0-beta |
| Upstream | <http://wenq.org/> |

Used as the default subtitle font so that CJK subtitles render on a machine
with no suitable system font configured. It is bundled as a data resource and
is not linked into any executable.

## Compiled into the application, vendored directly into this repository

These used to be git submodules pointing at niltsh's own (long-dormant) forks;
their sources are now committed directly under the paths below and compiled
into `MPlayerX.app` the same as before.

| Component | Location | License | Upstream |
|---|---|---|---|
| BGHUDAppKit | `BGHUDAppKit/` | BSD 3-Clause, Copyright (c) 2008 Tim Davis (BinaryMethod.com) | <https://github.com/binarygod/BGHUDAppKit> |
| UniversalDetector | `UniversalDetector/` | MPL 1.1 / GPL 2.0 / LGPL 2.1 tri-license (Mozilla `universalchardet`) | <https://mozilla.org/MPL/> |
| Apple Remote Control | `Apple Remote Control/` | MIT-style, Copyright (c) 2006 martinkahr.com | <http://www.martinkahr.com/> |

`Sparkle` was also declared as a submodule in the original tree but was never
referenced by `MPlayerX.xcodeproj` or compiled into anything; it has been
dropped rather than vendored.

## Kept for provenance only, not used by the build

### mplayer-for-MPlayerX

| | |
|---|---|
| Location | `mplayer/` |
| License | GNU General Public License, version 2 |
| Upstream | <https://github.com/niltsh/mplayer-for-MPlayerX> |

niltsh's own patched MPlayer source tree — the historical origin of the
`MPX_*` slave-protocol hooks reconstructed in
[`tools/mpx-hooks.patch`](tools/mpx-hooks.patch) (see the MPlayer entry
above). The arm64 binary this repository ships is **not** built from this
tree; `tools/build-mplayer-arm64.sh` builds from the official upstream
MPlayer 1.5 tarball instead, since this tree's 2012-era `configure` script
predates Apple Silicon and has no AArch64 support. Kept vendored here purely
as the corresponding-source record for where the patch hunks came from.

## Vendored into the MPlayerX sources

| Component | Location | License | Upstream |
|---|---|---|---|
| SPMediaKeyTap | `MPlayerX/SPMediaKeyTap.{h,m}` | BSD 2-Clause-style (see `MPlayerX/SPMediaKeyTap-LICENSE.txt`), Copyright (c) 2010 Spotify AB / (c) 2011 Joachim Bengtsson | <https://github.com/nevyn/SPMediaKeyTap> |
| NSObject+SPInvocationGrabbing | `MPlayerX/NSObject+SPInvocationGrabbing.{h,m}` | Same license, same upstream repository | <https://gist.github.com/511181> (bundled in the SPMediaKeyTap repository above) |

**Resolved 2026-08-12** (previously a gap): neither file carried a license
grant in this repository, only a bare copyright comment. The upstream
repository's own convention is a single root `LICENSE` file covering every
source file in it (it does not use per-file header comments either) — a
BSD 2-Clause-style license, not MIT as originally guessed here before the
upstream text was actually fetched. `MPlayerX/SPMediaKeyTap-LICENSE.txt` now
carries that text verbatim, and all four source files (`SPMediaKeyTap.{h,m}`,
`NSObject+SPInvocationGrabbing.{h,m}`) point at it.

**Local modification (2026-08-20)**: `SPMediaKeyTap.h` declares its delegate
callback as a formal `@protocol SPMediaKeyTapDelegate` instead of the original
informal `@interface NSObject (SPMediaKeyTapDelegate)` category. Swift cannot
override a member declared in an Objective-C category on `NSObject`, so the
Swift `AppController` could not otherwise implement it. Four lines in the
header; `SPMediaKeyTap.m` still messages `id` and is unchanged.

## A note on distribution channels

MPlayerX links against and ships GPLv2 code, and the GPL's requirements
conflict with the Mac App Store distribution terms. Distribute builds directly
(for example as a disk image) rather than through the App Store.
