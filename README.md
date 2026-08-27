# MPlayerX

A movie player for macOS, built as a graphical front end to
[MPlayer](https://www.mplayerhq.hu/). MPlayerX does not decode anything itself:
it spawns an `mplayer` process and drives it over the MPlayer slave protocol.

This is an unofficial fork, maintained by horowolf. It is not affiliated with
or endorsed by Zongyao QU, who wrote MPlayerX and stopped work on it in 2011;
please report problems with this fork here rather than to him.

This branch revives the project on Apple Silicon and builds arm64 only. It
targets Apple Silicon Macs exclusively; Intel Mac users should keep using the
original 2011-2012 release. Upstream development stopped in November 2011,
and the tree as it stood could not be built by any current version of Xcode.

## Status

| | |
|---|---|
| Builds | Xcode 26 on macOS 26, arm64 only |
| Minimum macOS | 11.0 |
| Source language | Swift, apart from four Objective-C files (see below) |
| Playback backend | MPlayer 1.5, built natively for arm64 |

Video and audio playback, subtitle rendering and charset detection work.
Preferences have been rebuilt in SwiftUI. `Base.lproj/MainMenu.xib` is the one
XIB left, and the player window and control bar it carries were laid out in
2011 against AppKit metrics that have since changed, so some spacing there is
still off. It does not affect playback.

## Building

```
git clone https://github.com/horowolf/MPlayerX.git
cd MPlayerX
open MPlayerX/MPlayerX.xcodeproj
```

Then press Build. There is no bootstrap step and no submodules to
initialize — every dependency this app actually compiles against
(BGHUDAppKit, UniversalDetector, Apple Remote Control) is committed
directly into this repository.

The repository does not ship a prebuilt `mplayer` binary; `MPlayerX/binaries/arm64/`
must be built locally before the app has anything to spawn:

```
brew install pkgconf freetype fontconfig fribidi speex
./tools/build-mplayer-arm64.sh
```

That script downloads the official MPlayer 1.5 release tarball, verifies its
SHA-256, builds it, and stages the result together with its support libraries
into `MPlayerX/binaries/arm64/`, rewriting install names so the bundle depends
on nothing from Homebrew at runtime. Homebrew is a build-time requirement only.

## What changed

- **Builds for arm64.** `VALID_ARCHS` was pinned to `i386 x86_64`, so Xcode
  skipped every compile and link step while still reporting `BUILD SUCCEEDED`,
  producing an `.app` with no executable inside. The project first built
  `$(ARCHS_STANDARD)` (universal, arm64 + x86_64) to get something running on
  both architectures, then was pinned to `ARCHS = arm64` once the native
  arm64 mplayer was verified working end to end — this branch targets Apple
  Silicon Macs only. The 2011 x86_64 and 32-bit i386 `mplayer` binaries were
  dropped along with the x86_64 app slice; see
  [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) for why that also closes
  a GPL compliance gap, not just a scope cut.
- **Architecture selection.** The app used to choose between the bundled
  mplayer binaries by reading the `hw.optional.x86_64` sysctl. That sysctl
  does not exist in a native arm64 process, so a natively built app fell
  through to the 32-bit i386 binary, which macOS has refused to run since
  10.15. Selection is now by explicit architecture instead of a sysctl probe.
- **Native arm64 mplayer.** Added, so playback no longer depends on Rosetta.
- **Startup crash.** `SPMediaKeyTap` asserted that `CGEventTapCreate` succeeded.
  Since macOS 10.14 that call requires Accessibility access, which a freshly
  built copy has not been granted, so the app aborted on launch. The media key
  feature has since been removed outright — on current macOS the system Now
  Playing controls claim F7/F8/F9 before an event tap sees them, so it could
  not work however the crash was handled.
- **UniversalDetector.** Was linked as a prebuilt framework from a path that
  does not exist in a fresh clone. Its sources are now compiled into the app,
  matching how BGHUDAppKit and Apple Remote Control were already handled.
- **Assorted defects** surfaced by 15 years of new compiler warnings, including
  a malformed format string in the donation URL, a `[super release]` in a
  `dealloc`, and `fabsf()` applied to `CGFloat`.
- **Rewritten in Swift.** The app was 2009-2011 Objective-C throughout,
  including manual retain/release. It is Swift now, ported in stages — model
  classes, custom views, dialog controllers (those use SwiftUI, hosted in the
  existing window structure), the mplayer IPC layer, the main window, and
  finally the leftovers. The main window stays AppKit, written in Swift rather
  than converted to SwiftUI: it is tied closely to CALayer, the mmap'd frame
  buffer and custom slider drawing, where a rewrite would be high risk for
  little gain. `MainMenu.xib` is unchanged. Four Objective-C files remain on
  purpose — `coredef.m` (the Distributed Objects protocols, which pass
  `char**`) and three small trampolines for things Swift cannot express
  (`NSConnection`/`shm_open`, `@try`/`@catch` around `NSException`).
- **Submodules vendored.** BGHUDAppKit, UniversalDetector, Apple Remote
  Control and the localization strings used to be git submodules pointing at
  niltsh's own forks, dormant since 2011-2015 with no way to push further
  changes. Their sources are now committed directly into this repository;
  see [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) for what moved
  where. Sparkle, which was declared as a submodule but never actually
  compiled into the app, was dropped instead of vendored.

## Releases and verifying a download

Builds are published as a `MPlayerX-<version>.dmg` on this repository's
releases page, and every release note lists the disk image's SHA-256. Check it
before opening the image:

```
shasum -a 256 MPlayerX-2.1.0.dmg
```

Compare the output against the hash in the release notes, not against a
checksum file downloaded alongside the image.

**Why this matters.** A GitHub URL that contains this repository's name does
not mean the file came from this repository. Anyone can attach a file to an
issue or a comment on any public repository; GitHub stores it under that
repository's URL and keeps serving it even if the comment is deleted or never
submitted. The technique has been used to pass malware off as downloads from
well-known projects. A file is a release of this fork only if its SHA-256
matches a hash printed in a release note here.

The only builds distributed by this fork come from
[tools/mplayerx-package.sh](tools/mplayerx-package.sh), which prints the
SHA-256 of the image it produces.

## License

MPlayerX is free software under the GNU General Public License, version 2 or
later. See [COPYING](COPYING) for the full text.

Every third-party component that this repository or a built `MPlayerX.app`
redistributes — the MPlayer binary, its support libraries, the bundled font,
and the vendored dependencies — is listed in
[THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md), along with its license and
the upstream source it came from. That file also records a compliance gap
inherited from the original repository that is worth knowing about before
redistributing.

Because MPlayerX ships GPLv2 code, distribute builds directly rather than
through the Mac App Store, whose terms conflict with the GPL.

## Credits

MPlayerX was written by Zongyao QU, copyright 2009-2011.

This fork -- the Apple Silicon port, the Swift rewrite and the macOS 11+
revival -- is maintained by horowolf, copyright 2026, and was carried out
with Claude Opus 5 (Anthropic). It keeps the MPlayerX name to credit where it
came from; it is not an official continuation, and the original author has no
involvement in it.
