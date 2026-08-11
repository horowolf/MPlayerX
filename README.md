# MPlayerX

A movie player for macOS, built as a graphical front end to
[MPlayer](https://www.mplayerhq.hu/). MPlayerX does not decode anything itself:
it spawns an `mplayer` process and drives it over the MPlayer slave protocol.

This branch revives the project on Apple Silicon. Upstream development stopped
in November 2011, and the tree as it stood could not be built by any current
version of Xcode.

## Status

| | |
|---|---|
| Builds | Xcode 26 on macOS 26, as a universal binary (arm64 + x86_64) |
| Minimum macOS | 10.13 |
| Playback backend | MPlayer 1.5, built natively for arm64 |

Video and audio playback, subtitle rendering and charset detection work. Some
interface layout is visibly off on current macOS; the XIBs date from 2011 and
were laid out against AppKit metrics that have since changed. That is being
addressed separately and does not affect playback.

## Building

```
git clone https://github.com/niltsh/MPlayerX.git
cd MPlayerX
git submodule update --init
open MPlayerX/MPlayerX.xcodeproj
```

Then press Build. There is no separate bootstrap step: the submodule sources
are compiled directly into the application, so nothing has to be built by hand
first.

The repository ships a prebuilt `mplayer` for each architecture under
`MPlayerX/binaries/`, which is what a normal build copies into the bundle. To
rebuild the arm64 one from source instead:

```
brew install pkgconf freetype fontconfig fribidi speex
./tools/build-mplayer-arm64.sh
```

That script downloads the official MPlayer 1.5 release tarball, verifies its
SHA-256, builds it, and stages the result together with its support libraries
into `MPlayerX/binaries/arm64/`, rewriting install names so the bundle depends
on nothing from Homebrew at runtime. Homebrew is a build-time requirement only.

## What changed

- **Universal binary.** `VALID_ARCHS` was pinned to `i386 x86_64`, so Xcode
  skipped every compile and link step while still reporting `BUILD SUCCEEDED`,
  producing an `.app` with no executable inside. The project now builds
  `$(ARCHS_STANDARD)`.
- **Architecture selection.** The app chose between the bundled mplayer
  binaries by reading the `hw.optional.x86_64` sysctl. That sysctl does not
  exist in a native arm64 process, so a natively built app fell through to the
  32-bit i386 binary, which macOS has refused to run since 10.15. Selection is
  now by explicit architecture, native first, with the x86_64 build as a
  Rosetta fallback when no arm64 binary is present.
- **Native arm64 mplayer.** Added, so playback no longer depends on Rosetta.
- **Startup crash.** `SPMediaKeyTap` asserted that `CGEventTapCreate` succeeded.
  Since macOS 10.14 that call requires Accessibility access, which a freshly
  built copy has not been granted, so the app aborted on launch. Media key
  support now degrades instead of aborting.
- **UniversalDetector.** Was linked as a prebuilt framework from a path that
  does not exist in a fresh clone. Its sources are now compiled into the app,
  matching how BGHUDAppKit and Apple Remote Control were already handled.
- **Assorted defects** surfaced by 15 years of new compiler warnings, including
  a malformed format string in the donation URL, a `[super release]` in a
  `dealloc`, and `fabsf()` applied to `CGFloat`.

## Support the original author

The **MPlayerX ▸ Donate...** menu item opens a PayPal donation page for
Zongyao QU, who wrote MPlayerX. It has been left exactly as it was, and it
still points at the original author rather than at anyone maintaining this
branch. The link dates from 2011 and has not been verified as still working.

## License

MPlayerX is free software under the GNU General Public License, version 2 or
later. See [COPYING](COPYING) for the full text.

Every third-party component that this repository or a built `MPlayerX.app`
redistributes — the MPlayer binaries, their support libraries, the bundled
font, and the submodules — is listed in
[THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md), along with its license and
the upstream source it came from. That file also records two compliance gaps
inherited from the original repository that are worth knowing about before
redistributing.

Because MPlayerX ships GPLv2 code, distribute builds directly rather than
through the Mac App Store, whose terms conflict with the GPL.

## Credits

MPlayerX was written by Zongyao QU, copyright 2009-2011.

The Apple Silicon port in this branch was carried out by Claude Opus 5
(Anthropic).
