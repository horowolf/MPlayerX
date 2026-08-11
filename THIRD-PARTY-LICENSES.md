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

These live under `MPlayerX/binaries/<arch>/` and are copied into
`MPlayerX.app/Contents/Resources/binaries/<arch>/` at build time.

### MPlayer

| | |
|---|---|
| Location | `MPlayerX/binaries/<arch>/mplayer` |
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

**x86_64 and i386 builds.** Inherited from the original MPlayerX repository,
where they were committed as prebuilt binaries in 2011 without a record of
which revision or configure line produced them. They self-report as
`MPlayer UNKNOWN-4.2.1 (C) 2000-2011 MPlayer Team`, which indicates a
development snapshot rather than a release, so the exact corresponding source
cannot be identified after the fact. This is a pre-existing compliance gap
carried over from upstream, not something introduced here. Anyone
redistributing those two binaries should either rebuild them from an
identified MPlayer revision or drop them; the arm64 binary above is not
affected.

### Support libraries used by MPlayer

Shipped next to the `mplayer` executable in `binaries/<arch>/lib/` and loaded
through `@executable_path/lib`.

| Library | License | Upstream |
|---|---|---|
| `libfreetype.6.dylib` | FreeType License (BSD-style) or GPLv2, at your option | <https://freetype.org/> |
| `libfontconfig.1.dylib` | MIT-style (fontconfig license) | <https://www.freedesktop.org/wiki/Software/fontconfig/> |
| `libfribidi.0.dylib` | GNU Lesser General Public License, version 2.1 or later | <https://github.com/fribidi/fribidi> |
| `libspeex.1.dylib` | BSD 3-Clause (Xiph.Org) | <https://www.speex.org/> |

The versions bundled for arm64 are recorded in
[`tools/build-mplayer-arm64.sh`](tools/build-mplayer-arm64.sh), which copies
them out of the build environment and rewrites their install names. As with the
`mplayer` executable itself, the provenance of the x86_64 and i386 copies was
never recorded upstream.

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

## Compiled into the application from submodules

These are checked out as git submodules and their sources are compiled directly
into `MPlayerX.app`; see `.gitmodules`.

| Component | License | Upstream |
|---|---|---|
| BGHUDAppKit | BSD 3-Clause, Copyright (c) 2008 Tim Davis (BinaryMethod.com) | <https://github.com/binarygod/BGHUDAppKit> |
| UniversalDetector | MPL 1.1 / GPL 2.0 / LGPL 2.1 tri-license (Mozilla `universalchardet`) | <https://mozilla.org/MPL/> |
| Apple Remote Control | MIT-style, Copyright (c) 2006 martinkahr.com | <http://www.martinkahr.com/> |

The `Sparkle` submodule is also declared in `.gitmodules` but is not referenced
by `MPlayerX.xcodeproj` and is not compiled or shipped.

## Vendored into the MPlayerX sources

Two files were copied into the MPlayerX sources rather than tracked as
submodules, and **neither carries a license grant in this repository**:

| Component | What the file actually says | Notes |
|---|---|---|
| `SPMediaKeyTap.m` / `.h` | A single line, `// Copyright (c) 2010 Spotify AB`, and a link to <http://overooped.com/post/2593597587/mediakeys>. No license text. | Media key interception |
| `NSObject+SPInvocationGrabbing.m` / `.h` | No copyright line and no license text. A comment in `SPMediaKeyTap.m` points at <https://gist.github.com/511181>. | Deferred invocation helper |

Upstream, both are distributed by their authors under an MIT license, so there
is every reason to believe redistribution is permitted. But a copyright notice
without the accompanying permission notice does not satisfy the MIT license's
own condition that the notice be included. This is a pre-existing gap inherited
from the original repository. The fix is to paste the upstream MIT text into
the headers of these four files, which should be done with the upstream
authors' text rather than a reconstruction.

## A note on distribution channels

MPlayerX links against and ships GPLv2 code, and the GPL's requirements
conflict with the Mac App Store distribution terms. Distribute builds directly
(for example as a disk image) rather than through the App Store.
