# MPlayerX Apple Silicon port — handoff

Read this first when picking the project back up. Full debugging history
from getting here lives in [`HANDOFF-ARCHIVE-2026-08-12.md`](HANDOFF-ARCHIVE-2026-08-12.md)
(same directory) — only pull it up if you need the reasoning behind
something below; day to day, this file should be enough.

## Current state (2026-08-12)

- `origin` (`horowolf/MPlayerX`) `master` is the working branch. Native
  arm64 build, verified end to end: seeking, pause/resume, fullscreen,
  window zoom, full playback, volume/time slider rendering.
- PR open: [niltsh/MPlayerX#29](https://github.com/niltsh/MPlayerX/pull/29) —
  symbolic/respect gesture per [[mplayerx-revival-goal]], not expected to
  be merged. Its head branch `arm64-support` is **frozen** at commit
  `99a1acf` on purpose — don't push further commits there, keep working
  on `master`.
- Repo has **zero submodules**. Everything (`BGHUDAppKit`,
  `UniversalDetector`, `Apple Remote Control`, `mplayer`, `localization`)
  is vendored directly; `Sparkle` was dropped (unused). Fresh clone needs
  no bootstrap step beyond `./tools/build-mplayer-arm64.sh` for the
  mplayer binary itself.
- `~/Desktop/MPlayerX-2.0.0.dmg` is a current, verified build (rebuild
  any time with `./tools/mplayerx-package.sh`).

## Remaining work

1. **UI layout skew re-check.** Original report was "slightly skewed"
   control bar. Several fixes have landed since (zero-`maxValue` guard,
   time/volume slider track-alignment, BGHUDAppKit knob-travel inset) —
   worth a fresh look to see if this is actually resolved now rather than
   assumed fixed.
2. **Warning cleanup.** `GCC_TREAT_WARNINGS_AS_ERRORS` is `NO`; ~30
   warnings remain, mostly renamed AppKit constants
   (`NSCommandKeyMask` → `NSEventModifierFlagCommand` and similar).
   Mechanical, but a large diff — its own commit.
3. **Breadth testing not yet done:** subtitles, DVD chapter listing, a
   wider codec spread (HEVC etc.), longer/multi-file sessions.
4. **Localization decision.** `niltsh/MPlayerX-Localization` has
   translation work up to version `1.1.4`; this repo's vendored
   `localization/2.0.0/` is just `1.0.10`'s strings renamed. Whether to
   pull the newer translations in is a product call, not made yet.
5. **License gap:** `SPMediaKeyTap.m`/`.h` and
   `NSObject+SPInvocationGrabbing.m`/`.h` carry no license grant text in
   this repo (see `THIRD-PARTY-LICENSES.md`). Fix is pasting in the
   upstream MIT license text from the original authors, not a
   reconstruction.
6. **`/Applications/MPlayerX.app` swap — deliberately deferred**, needs
   the user's own admin auth, not something to script. Do this last, per
   [[mplayerx-revival-goal]].
7. **Fork cleanup, blocked on the PR.** `horowolf/BGHUDAppKit` and
   `horowolf/mplayer-for-MPlayerX` on GitHub only exist because PR #29's
   frozen `arm64-support` branch still references them via `.gitmodules`
   at that commit. Once the PR is closed (merged, or abandoned), both
   forks can be deleted — not before.

## Known gotchas worth not re-discovering

- **Two apps share one bundle ID.** `org.niltsh.MPlayerX` is the bundle
  ID for both the installed `/Applications/MPlayerX.app` (2012 release)
  and this branch's dev build, until item 6 above happens. `open -a`
  can launch the wrong one. Confirm with
  `pgrep -fl "MPlayerX.app/Contents/MacOS/MPlayerX"` before trusting any
  live behavior.
- **`open -a APP FILE` is unreliable** in this environment (silently
  produces a window-less menu-bar-only app, no crash, no log). Reliable
  path: launch the app alone, confirm frontmost, then Cmd+O and
  type-ahead the filename.
- **Editing `MainMenu.xib`**: adding a menu item/outlet in the raw XML
  is not enough for the connection to actually compile — `ibtool` will
  silently drop it. Needs entries in both of the owning class's
  `IBPartialClassDescription` outlet caches (`outlets` and
  `toOneOutletInfosByName`, index-aligned with their `sortedKeys`
  arrays) *and* an `IBObjectRecord` under `objectRecords` referenced
  from the parent's `children` array. Also: opening the xib in modern
  Interface Builder can silently upgrade its whole file format (a
  ~9000-line diff for a one-line change) — check `git diff` after any
  xib edit before committing.
- **Version bumps**: the Xcode Localizations build phase requires a
  `localization/<CFBundleShortVersionString>/` directory to exist
  exactly matching the marketing version. It's vendored now, so this
  won't silently break, but a future version bump still needs a new
  directory added.
