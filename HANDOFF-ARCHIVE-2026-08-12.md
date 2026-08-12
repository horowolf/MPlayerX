# MPlayerX Apple Silicon port — handoff

## Update 2026-08-12: seek bug root-caused and fixed, plus two smaller fixes

Picking up from the "three new bugs" list at the bottom of the 2026-08-11
entries below. This session fixed Bug A for real (the previous session's
two leads were both wrong), fixed a real vertical-alignment bug in the time
slider found live by the user watching this session, and restored Bug C
(the Cmd+` shortcut). Bug B (volume slider skew) was diagnosed but not
fixed — see its own section below. `~/Desktop/MPlayerX-2.0.0.dmg` was
rebuilt from the latest commit and is ready for the user to install and try.

**Committed this session**, on top of `fc62cf7`:
```
62c0763  Restore Cmd+` half window size shortcut
f90ebc2  Restore MPX_PBST so mplayer.state actually reaches kMPCPlayingState
920474b  Fix time slider progress fill misaligned from its track
```
`MPlayerX/binaries/arm64/` is now **committed** (was previously untracked,
pending breadth-testing — that testing happened this session, see below).

### Bug A root cause (not what the 08-11 handoff guessed)

Both leads listed in the 08-11 entry below were checked live and were
**wrong**: `[[timeSlider cell] class]` is genuinely `TimeSliderCell` at
runtime (confirmed via temporary `NSLog` in `awakeFromNib`), so the xib's
apparent plain-`NSSliderCell` archiving was a red herring — old-format
keyed-archive xibs apparently resolve the real class some other way IB's
own tooling understands, not visible from grepping the XML. Lead 2's gate
(`PlayerCouldAcceptCommand`) was on the right track but the actual gap was
one level up, in what sets the state bit that gate reads.

**Real root cause:** `CoreController.m`'s `pollingTimer` only sends
`get_property time_pos` (line 508, `getCurrentTime:`) when
`state == kMPCPlayingState`, and `PlayerController.m`'s
`PlayerCouldAcceptCommand` macro (used to gate seeking and nearly every
other outgoing command) checks the same `0x0100` bit. That bit is set by
parsing mplayer's `MPX_PBST` line (`kMPCPlayBackStartedID = @"PBST"` in
`coredef_private.m:69`, routed through `kMITypeStateChanged` in
`CoreController.m:818-830`). **`MPX_PBST` was the one hook the 08-11
session deliberately left out**, reasoning it was tied to the unimplemented
`-stpause` (start-at-pause) feature and unrelated to the two bugs that
prompted that session's work. That reasoning was wrong: without it,
`state` never leaves `kMPCOpenedState` after a file opens, so:
- `gotCurentTime:` fires exactly once, with `time=0`, right at open, and
  never again — confirmed by temporary `NSLog` instrumentation showing a
  single `gotCurentTime time=0.000000` call per launch, vs. continuous
  calls with increasing `time=` values once fixed.
- The seek bar *looked* right (duration/`MPX_LENGTH` came through fine,
  independent of this) but every seek attempt silently no-op'd through
  `PlayerCouldAcceptCommand`.

**Fix:** added the `MPX_PBST` print back to `tools/mpx-hooks.patch`, at
the same spot upstream had it (right before mplayer's main playback loop
starts, in `mplayer.c`). Since this fork doesn't implement `-stpause`,
it always prints the "playing" value (`0x0100`) rather than branching on
`mpx_startatpause`. Verified end to end: `gotCurentTime` now fires
continuously with increasing `time=` values (checked via `log show`, not
just visually), and both click-to-seek and drag-to-seek work correctly —
tested on two different files/codecs.

**Regenerated `tools/mpx-hooks.patch` from scratch** (diffed the full
patched tree against a fresh pristine extraction of the same tarball)
rather than hand-appending a hunk, to make sure the new hunk's context
lines were exactly right. Verified the regenerated patch applies cleanly
with `patch -p1` to a fresh `MPlayer-1.5` extraction and produces a tree
byte-identical to the hand-edited build tree it was diffed from.

### A debugging trap worth knowing about: two apps share one bundle ID

`org.niltsh.MPlayerX` is the bundle identifier for **both** the installed
`/Applications/MPlayerX.app` (the 2012 x86_64/i386 release) and this
branch's dev build. Early in this session, `open -a <dev build path> file`
intermittently launched the **old** `/Applications` copy instead of the
dev build — same bundle ID, so Launch Services' arbitration isn't
guaranteed to pick the exact path given. This produced a very confusing
false positive: the old app's seek bar and time display genuinely work
(it has the real private mplayer patch baked in), so a session watching it
by mistake would wrongly conclude the dev build's seek bug was already
fixed. **Always confirm with `pgrep -fl "MPlayerX.app/Contents/MacOS/MPlayerX"`
that the running process's path is the dev build**, not `/Applications`,
before trusting any live behavior — and consider `pkill`-ing the
`/Applications` copy first if it's not needed, as this session ended up
doing.

Also: launching via `open -a APP FILE` in this environment was **very**
unreliable this session (silently produced a menu-bar-only app with no
window, no crash, no log entries — happened repeatedly, root cause not
found, may be specific to the computer-use/automation environment rather
than the app itself). The reliable path was always: launch the app alone
first (`open -a APP` with no file argument), confirm it's frontmost, then
use the app's own File > Open (Cmd+O) and type the filename to
type-ahead-select it in the panel, then click Open. Worth knowing if a
future session hits the same "app launches, no window, no crash" symptom.

### Bug B (volume slider skew) — diagnosed, not fixed

`volumeSlider`'s cell is genuinely `BGHUDSliderCell` (confirmed live) with
`controlSize` = **`NSMiniControlSize`** (confirmed live via temporary
`NSLog`, value `2`). `BGHUDSliderCell.m`'s draw methods handle all three
control sizes and pull colors from `[[BGThemeManager keyedManager]
themeForKey:self.themeKey]` (default key `"gradientTheme"`, resolving to
`BGGradientTheme`, whose `sliderTrackColor`/knob colors are dark grays —
*not* white, contrary to how the rendered slider looks). No app code
anywhere registers a custom theme; MPlayerX has always relied on
BGHUDAppKit's own built-in default theme for this control. Given the
theme's own source colors are dark, the visually-white/thin-Aqua-looking
slider the user reported is likely a **rendering pipeline** issue (e.g.
modern AppKit not routing through the legacy cell-drawing methods for
this specific configuration) rather than a missing/wrong theme — this
wasn't confirmed further; time was spent on Bug A and the live-reported
track-alignment bug instead, since those were higher-value. A fresh
`NSLog` of `[[volumeSlider cell] class]` / `controlSize` / theme lookup
result (the debug harness used for Bugs A/C this session, since removed)
would be the fastest way to pick this back up — see the git history of
`ControlUIView.m` around `awakeFromNib` this session for the pattern.

### Cmd+` (half window size) — restored, xib gotcha worth documenting

Hand-ported niltsh/MPlayerX's `sparkle` branch commit `d1d153e` ("add half
size") — `KeyCode.h/.m` (new `` ` `` key equivalent), `ControlUIView.h/.m`
(new outlet, `zoomToSize:` now divides by 4 so 0.5x/1x/2x can all be
integer `NSTag`s), and a **minimal** `MainMenu.xib` edit (one new
`NSMenuItem` plus its connections) rather than accepting upstream's full
1396-line IB-resave diff, since the xib is otherwise unrelated to this
port.

**Non-obvious gotcha, cost real time this session:** adding a new
`NSMenuItem` to the archived object graph and its `IBOutletConnection`/
`IBActionConnection` records is *not* enough for the connection to
actually compile into the nib. Two more things are required, or ibtool
silently drops the connection with only a vague warning
(`"The object->connection map had entries that were no longer present in
the nib... Your nib is probably ok"` — it is not obviously ok) and no
build error:
1. An entry for the new outlet in **both** of `ControlUIView`'s
   `IBPartialClassDescription` outlet caches (`outlets` dict and
   `toOneOutletInfosByName` dict) — each has a `dict.sortedKeys` array
   (alphabetically sorted) and a parallel `dict.values` array that must
   stay index-aligned with it.
2. An `IBObjectRecord` entry for the new object under the `objectRecords`
   tree (separate from the `NSMenuItems` array), *and* a reference to it
   added to its parent menu's own `IBObjectRecord.children` array.
Confirmed via `strings compiled.nib | grep menuZoomToHalfSize` (absent
until both fixes were in) and a clean `ibtool --errors --warnings` run (no
warnings at all once both fixes were in, vs. the vague warning before).
Verified live: the menu item, its `⌘\`` key equivalent, and the actual
half/original/double-size zoom all work correctly.

### Breadth-testing done this session (before committing the binary)

All on the arm64 native path, via computer-use driving the real app:
- Click-to-seek and drag-to-seek (the actual point of this session's fix)
- Pause/resume (space bar, confirmed via button icon state)
- Fullscreen enter/exit (`f` key), including the control bar and seek bar
  rendering correctly inside it
- Two different files/codecs: `IMG_8984.mov` (H.264, prior sessions' test
  file) and `VID_20231002_091946378~2.mp4` (a different H.264 MP4)
- All three window zoom levels (half/original/double size)
- Full playback start-to-finish with no crash

**Not tested** (ran out of time this session, not because of any known
problem): subtitles (no test file with subs on hand), DVD chapter
listing, a wider codec spread (HEVC, older codecs), and the app in
practice over a longer/multi-file session.

### Other repos checked this session

Per the user's request to also finish `mplayer` and related-repo work:
- **`mplayer` submodule** (`horowolf/mplayer-for-MPlayerX`,
  `arm64-support` branch): already up to date with its `origin`, working
  tree clean, nothing to do — it only serves as the GPL
  corresponding-source/provenance record (see
  [[mplayerx-missing-mpx-mplayer-hooks]]); the actual arm64 binary is
  built from the vanilla MPlayer 1.5 tarball plus `tools/mpx-hooks.patch`,
  not from this submodule's tree directly.
- **`MPlayerX-Deploy`** (`~/git/MPlayerX-Deploy`): clean, up to date with
  `origin/master`. Contains old SourceForge/Sparkle-appcast release
  scripts (`prepareUpdate.sh`, `appcast*.xml`, `upload-sourceforge.sh`).
  Nothing actionable — this fork doesn't do automated Sparkle-based
  releases (that would need signing keys and update-server hosting, well
  out of scope), and packaging is handled by the out-of-repo
  `~/git/mplayerx-package.sh` instead.
- **`MPlayerX-Localization`** (`~/git/MPlayerX-Localization`): clean, up
  to date with `origin/sparkle`. **Finding, not acted on:** upstream's
  `sparkle` branch has gone up to a `1.1.4` localization directory (this
  fork currently uses `1.0.10`, matching `master`'s version before the
  2.0.0 bump — see "Gotcha this created" further down for why
  `localization/2.0.0/` is a local untracked copy of `1.0.10`, not a real
  translation update). Whether to pull in niltsh's newer translation work
  is a product decision for the user, not something this session changed
  unprompted — flagging it here per the existing memory note that this
  was worth checking.

### Verified: rebuilt and repackaged DMG

`~/Desktop/MPlayerX-2.0.0.dmg` was rebuilt from `62c0763` via
`~/git/mplayerx-package.sh` and verified by mounting: `binaries/` lists
only `arm64`, that `mplayer` is `arm64`-only via `lipo -info`, the app
binary is `arm64`-only, `CFBundleShortVersionString` is `2.0.0`,
`MPXCommitHash` is `62c07633a5ad0deae0eb5c0a791fb1653f780447`, and the
`mplayer` binary has all 12 `MPX_*` strings (11 from `fc62cf7` plus the
new `MPX_PBST`). **This is the DMG the user is installing/trying next.**
Feedback from that install will likely arrive in the next conversation —
see the memory system for the established workflow of reading this file
first, then updating it again before signing off.

## Update 2026-08-11 (later session): MPX_* hooks recovered and ported

The private mplayer patch mentioned throughout this document (`-nodispclog`,
`-stpause`, `-subid`, the custom `vo_corevideo` DO protocol, and — the actual
blocker found this session — custom `MPX_*` slave-protocol print hooks that
`LogAnalyzeOperation.m`/`coredef_private.m` parse for the seek bar and the
Inspector) turned out to still exist upstream, just never merged:
`https://github.com/niltsh/mplayer-for-MPlayerX`, `x86_64` branch, confirmed
by timestamp correlation to be what 1.0.14 actually shipped with (see
below). It's forked to `https://github.com/horowolf/mplayer-for-MPlayerX`
and wired into this repo as the `mplayer` git submodule
(`branch = arm64-support` in `.gitmodules`), following the same pattern as
this project's other four dependencies (Sparkle, BGHUDAppKit,
UniversalDetector, Apple Remote Control are all `niltsh/*` submodules
already).

That 2012-era tree's `configure` has zero AArch64 awareness (`uname -m`'s
`arm64` collapses into 32-bit-ARM handling), so rather than porting its whole
build system, only the specific hooks MPlayerX's UI reads were hand-ported
onto the vanilla MPlayer 1.5 tarball this repo already builds successfully on
arm64. The patch lives at `MPlayerX/tools/mpx-hooks.patch` and is applied
automatically by `build-mplayer-arm64.sh`. Verified end to end (fresh build,
real playback, screenshots): the seek bar renders/drags correctly and Window
> Media Info shows populated Demuxer/Track Info/Format fields. Full detail in
the `mplayerx-missing-mpx-mplayer-hooks` memory (auto-memory, not in this
repo).

Left out on purpose (separable follow-ups, not needed for the two reported
bugs): start-at-pause (`-stpause`/`MPX_PBST`), subtitle name enumeration
(`-subid`/`MPX_MPXSUBNAMES`), `MPX_MPXSUBFILEADD`, DVD chapter listing
(`MPX_CHAPTERINFO` in `stream/stream_dvd.c`), A-B loop, font fallback.

**Update: committed at `fc62cf7`** (the `mplayer` submodule, `.gitmodules`,
`tools/build-mplayer-arm64.sh`, `tools/mpx-hooks.patch` — not
`MPlayerX/binaries/arm64/` itself, see below). `~/Desktop/MPlayerX-2.0.0.dmg`
was rebuilt from this commit via `~/git/mplayerx-package.sh` and verified:
arm64-only app, arm64 mplayer with all 11 `MPX_*` strings present,
`CFBundleShortVersionString` 2.0.0, `MPXCommitHash fc62cf7af3397731aa5aebe9e99f15071cc8d452`.

**Correction to the "verified end to end" claim two paragraphs up:** that
verification (via computer-use screenshots) confirmed the seek bar *renders*
correctly with real time labels, but never actually tested dragging it — the
statement "renders/drags correctly" overclaimed. The user installed the DMG
themselves and found it does **not** actually drag/seek. See the new bug
list below.

## Update 2026-08-11 (same day, later): DMG-tested, three new bugs found

The user's own PR philosophy, stated this round: basic respect to the
original author — if niltsh is still active, a PR is the polite move; if
not, this becomes the user's own fork going forward. Doesn't change any
engineering decision, just the framing for why a clean PR-able history still
matters even though niltsh has been dormant since 2011.

The user installed `~/Desktop/MPlayerX-2.0.0.dmg` (built from `fc62cf7`) over
their existing app and reported three bugs from real usage. None of these
were fixed this round — this section is a diagnosis starting point for
whoever picks this up next, from a research pass (Explore agent, static
analysis only, no runtime testing done).

### Bug A: time slider renders but doesn't seek

Dragging or clicking the time slider doesn't change playback position, even
though it now shows correct time labels (the MPX_LENGTH/MPX_SEEKABLE fix
above is confirmed working at the mplayer stdout level — `MPX_SEEKABLE=1`
was seen directly). The break is somewhere on the UI/AppKit side.

Action chain, all confirmed intact: `ControlUIView.m:623 seekTo:` →
`PlayerController.m:748 seekTo:mode:` → `CoreController.m:567
setTimePos:mode:` → `PlayerCore.m:134 sendStringCommand:` (writes to
mplayer's stdin). The slave-protocol commands look like valid MPlayer 1.5
syntax: relative seeks send `"pausing_keep seek <delta> <type>\n"`
(`CoreController.m:590`), absolute seeks send `"pausing_keep set_property
time_pos <time>\n"` (`CoreController.m:574`).

Two leads to check first, in order:

1. **`MainMenu.xib`'s archived cell class for `timeSlider`** (object id
   427466563, cell id 921093681, around line 1615) reads as plain
   `NSSliderCell`, not `TimeSliderCell` — no `NSClassName` override was found
   near it in a grep pass. If that's really true at runtime, none of
   `TimeSliderCell.m`'s custom `startTrackingAt:`/`continueTracking:`
   overrides (lines 39-74) would ever fire, and `ControlUIView.m:632`'s
   unchecked cast `[(TimeSliderCell*)[timeSlider cell] isDragging]` would be
   sending a selector to an object that isn't actually a `TimeSliderCell` —
   likely crashing or returning garbage that breaks the seek branch.
   **But this is in tension with history**: the zero-`maxValue` crash fixed
   at `403d87c` was reported specifically inside
   `-[TimeSliderCell drawHorizontalKnobInFrame:]`, which could only have
   fired if `TimeSliderCell` *was* being instantiated. Possible explanations:
   the class binding is set programmatically at runtime rather than in the
   xib (check `ControlUIView.m`'s `awakeFromNib`/setup code for a
   `setCell:`-style swap), or the static grep missed the xib's class table
   (older keyed-archive xibs sometimes index class names in a shared table
   rather than inline next to each object, which a proximity grep can miss).
   **Don't trust this lead until confirmed live** — e.g. breakpoint on
   `TimeSliderCell`'s init or log `[[timeSlider cell] class]` at runtime.
2. **`PlayerController.m:751`**: `if (PlayerCouldAcceptCommand &&
   mplayer.movieInfo.seekable)` silently returns `-1` with no logging if
   false. `PlayerCouldAcceptCommand` is `(mplayer.state & 0x0100)!=0`
   (`PlayerController.m:62`). Worth breakpointing to see whether this gate is
   actually open when the user clicks the slider.

### Bug B: volume slider looks visually skewed

`volumeSlider` (outlet in `ControlUIView.h:62`, cell id 374058532 around
`MainMenu.xib:1712`) is also archived as a plain `NSSliderCell` — no
volume-specific custom cell class exists anywhere in the repo. Both sliders
sit inside the app's dark BGHUDAppKit-themed control bar but apparently
render as stock Aqua controls, which would plausibly look "crooked" against
the surrounding themed chrome regardless of the `TimeSliderCell` question
above. This overlaps with the pre-existing "UI layout... slightly skewed"
item already on the remaining-work list (XIBs are Interface Builder 3-era,
laid out against AppKit metrics that have since changed) — this may be the
same root cause finally getting a concrete repro instead of a vague report.

### Bug C: Cmd+` (half window size) shortcut is gone

Not a regression on this branch — it was never merged into this branch's
lineage in the first place. It exists on `niltsh/MPlayerX`'s `sparkle`
branch at commit `d1d153e "add half size"` (touches `ControlUIView.h/.m`,
`KeyCode.h/.m`, `MainMenu.xib`; defines `kSCMWindowZoomHalfSizeKeyEquivalent
= @"\`"` with `NSCommandKeyMask`), but `git merge-base --is-ancestor d1d153e
HEAD` is false against this branch's fork point (`1569042`). To restore it:
cherry-pick or hand-port that commit. Also worth checking at runtime after
porting — modern macOS reserves Cmd+` system-wide for "cycle through windows
of the frontmost app," which could shadow the app-level binding depending on
how it's registered (menu-item key equivalent vs. a local event monitor).

### Suggested model/effort for next round

All three leads above are concrete (file/line, specific hypotheses to
falsify) — none of them need novel architecture or deeply ambiguous
judgment calls, so Sonnet at high effort should carry all three
comfortably; that's also what did this round's work (the mplayer patch
archaeology was arguably the hardest reasoning task in this whole port, and
Sonnet handled it fine). The one place Opus might earn its keep: if Bug A's
two leads both turn out to be dead ends and it's a deeper protocol/runtime
mismatch, that specific sub-investigation could benefit from Opus's extra
depth — but don't reach for it up front, only if Sonnet gets stuck.

This does **not** change the "Do not commit yet" status of
`MPlayerX/binaries/arm64/` below — it was rebuilt from the patched source but
still only has light testing (basic playback of one file, seek bar/Inspector
check). It stays untracked in the working tree for now.

---

Branch: `arm64-support` (14 commits on top of upstream `master` @ `1569042`)
Working tree: clean except the build-generated bump in
`MPlayerX/MPlayerX-Info.plist` (`CFBundleVersion` / `MPXCommitHash`, rewritten
by every build — not meant to be committed).
`MPlayerX/binaries/arm64/` is now **committed** (as of `f90ebc2`,
2026-08-12) — the breadth-testing that was blocking this happened this
session; see the "Do not commit yet" section further down, which is now
historical.

Marketing version was bumped `1.0.10` → **`2.0.0`** at commit `eedcd0d`
(2026-08-11, by Sonnet), at the user's request: native Apple Silicon support
is a bigger jump than a patch release, and it makes the current DMG
unambiguous against older `1.0.x` builds already sitting on the Desktop.
**Gotcha this created:** the Xcode Localizations build phase
(`getAppVersion.rb` + `updateInfoPlist.rb`) `cd`s into
`../localization/<CFBundleShortVersionString>/` and runs `make` there — that
directory name must match the marketing version exactly or the build fails
with `make: *** No rule to make target 'clean'`. `localization/` is a
separate git submodule (`niltsh/MPlayerX-Localization`); rather than touching
its tracked history, `localization/2.0.0/` was created as a plain untracked
copy of `localization/1.0.10/` (no strings or xibs actually changed for this
port), the same way `MPlayerX/binaries/arm64/` is untracked. If that
directory is ever missing — a fresh clone, a different machine — recreate it
with `cp -R localization/1.0.10 localization/2.0.0 && rm -rf localization/2.0.0/results`
before building.

## Going arm64-only

At the user's explicit request (2026-08-11, after 2.0.0), this branch dropped
x86_64 support entirely instead of staying universal. Rationale: the
universal binary was originally built so *this* fork's own build could run
on both architectures; the user now wants a clean, unambiguous arm64-only
build for Apple Silicon Macs going forward, and is fine with Intel Mac users
staying on the original 2011-2012 release rather than this fork.

What changed (by Sonnet):

- `MPlayerX.xcodeproj/project.pbxproj`: the three project-level
  `ARCHS = "$(ARCHS_STANDARD)";` settings (Debug/Release/Deploy) became
  `ARCHS = arm64;`. There were no per-target overrides to also change.
- `MPlayerX/binaries/x86_64/` and `MPlayerX/binaries/m32/` (the 2011
  prebuilt x86_64 and i386 `mplayer` binaries, ~21 MB) were removed with
  `git rm -r` — they are gone from the working tree but still recoverable
  from git history if an Intel build is ever wanted again.
- `README.md` and `THIRD-PARTY-LICENSES.md` updated to describe an arm64-only
  build. This also **closes one of the two GPL compliance gaps** the legal
  section used to flag: the 2011 x86_64/i386 `mplayer` binaries had no
  recorded corresponding source, and since they are no longer redistributed
  that gap no longer applies to this branch. Only the `SPMediaKeyTap` /
  `NSObject+SPInvocationGrabbing` license-grant gap remains (see "Legal
  position" below).
- `PlayerController.m`'s `preferredMPlayerArchKey` was **not touched**. Its
  `#if defined(__arm64__)` / `#else` split already meant the x86_64/i386
  fallback branch (which references `kX86_64Key` / `kI386Key`) is compiled
  out entirely once `ARCHS` no longer includes those architectures — there is
  no live code path left that can select a non-arm64 mplayer, without having
  to touch the source. `kX86_64Key`/`kI386Key`/`kUDKeyPrefer64bitMPlayer` and
  their handful of other call sites (`CoreController.m`, `ParameterManager.m`)
  were left alone since they still compile fine as dead-for-arm64 code and
  ripping them out is a separable cleanup, not something this request asked
  for.
- **Side effect worth knowing:** with the app itself single-arch now,
  ticking **Get Info → Open using Rosetta** no longer silently falls back to
  an Intel mplayer (the old failure mode described below) — there is no
  x86_64 app slice left to run under Rosetta, so macOS simply refuses to
  launch the app at all with that box checked. If a "won't launch" report
  ever comes in, check that checkbox first.

**Done and verified 2026-08-11**, at commit `faa067f`: `~/Desktop/MPlayerX-2.0.0.dmg`
was rebuilt and mounted again — the app binary is now `arm64` only (no
`x86_64` slice), `Contents/Resources/binaries/` contains only `arm64/`, that
`mplayer` is `arm64`, and `MPXCommitHash` reads
`faa067facc519563fd25c081888db0ac1e8e68b6`. Everything earlier in this
document that says "universal (arm64 + x86_64)" describes the build as it
stood before this section; it is arm64-only from here on.

## Where things stand

Everything below is verified by running it, not by inspection.

| | Status |
|---|---|
| Builds in Xcode 26 / macOS 26 | Yes, arm64 only (see "Going arm64-only" above), Debug and Release |
| `git submodule update --init` then press Build | Works, no bootstrap step |
| DMG packaging | Works, `~/git/mplayerx-package.sh` |
| Playback with the 2011 x86_64 mplayer (Rosetta) | Historical only — that binary was removed going arm64-only; was confirmed working before removal |
| Playback with the new native arm64 mplayer | **Works.** Re-verified end to end at `403d87c` — see below |

Re-verified on 2026-08-11 by building `403d87c` clean and running it, not by
inspection: `lsappinfo` reports `Arch=ARM64` for both the app process and the
`Contents/Resources/binaries/arm64/mplayer` child it spawns,
`sysctl.proc_translated` is `0` for both, and two clips
(`VID_20231002_091946378~2.mp4` for 2m17s, `IMG_8984.mov`) played with no
crash and no new report in `~/Library/Logs/DiagnosticReports`. Native arm64
is working in the source tree.

`~/Desktop/MPlayerX-2.0.0.dmg` is the current, good build (repackaged and
verified 2026-08-11 from `403d87c` — see "How to fix it" below).
`~/Desktop/MPlayerX-1.0.10.dmg` is a **leftover, stale, Rosetta-only** build
from earlier in the same session and can be deleted once the new one is
confirmed good; do not test with it.

## "It still isn't native arm64" — diagnosed, not a code bug

The report that the app still runs under Rosetta on an M-series Mac is real,
but nothing in the branch is at fault. Three separate things conspire, and
all three are on the *delivery* side. Each was checked on this machine.

1. **The app being launched is the 2012 release, not this build.**
   `/Applications/MPlayerX.app` is the official MPlayerX 1.0.14 (build 1527,
   `MPXCommitHash 808b1231`, last touched 2023-12-14). Its main executable is
   `x86_64 i386` — no arm64 slice at all — and its
   `Contents/Resources/binaries/` holds only `m32` and `x86_64`. Opening a
   video from Finder, Launchpad or Spotlight gets that one, entirely under
   Rosetta. Activity Monitor showing "MPlayerX — Intel" is this, not the
   branch.

2. **The DMG on the Desktop has arm64 deliberately switched off.** Inside
   `~/Desktop/MPlayerX-1.0.10.dmg`, the app's
   `Contents/Resources/binaries/` contains `arm64.staged`, `m32`, `x86_64` —
   the arm64 directory was manually renamed before packaging (a previous
   session did it on purpose, while the crash below was still unfixed).
   `-[PlayerController preferredMPlayerArchKey]` looks for
   `binaries/arm64/mplayer` exactly; with the directory named `arm64.staged`
   the probe misses, and it falls through to `x86_64` — Rosetta mplayer,
   silently. Nothing in `mplayerx-package.sh` or the Xcode project does that
   rename, so it will not come back on its own.

3. **That DMG also predates the fix.** It was built at 08:57; commit
   `403d87c` landed at 09:27. Even with the directory renamed back it would
   still crash.

A fourth thing to check before believing any future "not native" report:
`preferredMPlayerArchKey` selects with `#if defined(__arm64__)`, which is
per-slice. If someone ticks **Get Info → Open using Rosetta** on the app, the
x86_64 slice runs, `__arm64__` is undefined, and the app correctly but
invisibly picks the Intel mplayer. That checkbox is sticky per bundle.

The branch used to report version **1.0.10** (upstream's tree) against the
installed release's **1.0.14**, which made a correct new build look "older"
than what was already installed. That's why the marketing version was bumped
to **2.0.0** (see top of this document) — `2.0.0 > 1.0.14`, so Finder will no
longer warn about replacing with something older, and the DMG filename itself
(`MPlayerX-2.0.0.dmg`) no longer collides with any prior `1.0.x` file on the
Desktop.

### How to fix it

The playback fix is already in the source; the work is to actually ship and
install it, then make the trap in (2) impossible to fall into again.

1. **Rebuild and repackage from `403d87c`.** Done 2026-08-11 by Sonnet, twice:
   once producing `MPlayerX-1.0.10.dmg` (now stale, superseded — see below),
   then again after the version bump to `2.0.0` (commit `eedcd0d`), producing
   the current `~/Desktop/MPlayerX-2.0.0.dmg`.

   ```bash
   cd ~/git && ./mplayerx-package.sh
   ```

2. **Verify the DMG before installing it.** Done 2026-08-11 against
   `MPlayerX-2.0.0.dmg`: mounted it, `binaries/` lists a plain `arm64` (not
   `arm64.staged`), `lipo -info` on that `mplayer` reports `arm64`, the app
   binary is `x86_64 arm64`, `CFBundleShortVersionString` reads `2.0.0`, and
   `MPXCommitHash` reads `eedcd0db171cbabc36cabc6b230b76f21368d7ca` (the
   version-bump commit, built on top of the `403d87c` fix).

   ```bash
   hdiutil attach ~/Desktop/MPlayerX-2.0.0.dmg -nobrowse -readonly -mountpoint /tmp/mpxdmg
   ls /tmp/mpxdmg/MPlayerX.app/Contents/Resources/binaries/   # must list a plain "arm64"
   lipo -info /tmp/mpxdmg/MPlayerX.app/Contents/Resources/binaries/arm64/mplayer
   hdiutil detach /tmp/mpxdmg
   ```

3. **Replace the 2012 install — still pending, needs the user.** Drag the
   new app from `~/Desktop/MPlayerX-2.0.0.dmg` over
   `/Applications/MPlayerX.app`. That bundle is `root:wheel`, so it needs the
   user's own admin authentication — an assistant should not script this
   with sudo or admin-privileged AppleScript. Until it is replaced, every
   double-clicked video keeps opening the 2012 Intel build. Verify afterward:

   ```bash
   lsappinfo list | grep -A6 -i mplayer   # want Arch=ARM64 on both app and mplayer
   ```

4. **Harden `~/git/mplayerx-package.sh` so a Rosetta-only DMG cannot ship
   silently.** Done 2026-08-11: it now asserts, right after the build and
   before staging, that `${APP}/Contents/Resources/binaries/arm64/mplayer`
   exists and that `lipo -archs` on it reports `arm64`, aborting with a clear
   message otherwise, and it echoes the arch directories actually shipped
   next to the existing `architectures:` line. (The script lives outside the
   repo on purpose — see [[mplayerx-keep-packaging-uncommitted]] — so this
   does not touch the PR branch.)

5. **Optional but cheap: make the choice observable.**
   `preferredMPlayerArchKey` decides in silence. An `NSLog` of the chosen key
   and resolved path, or a line in a diagnostics/About panel, turns "is it
   native?" into a question anyone can answer in one second instead of an
   `lsappinfo` session.

To confirm a running build really is native, without a screenshot:

```bash
lsappinfo list | grep -A6 -i mplayer   # want Arch=ARM64 on both app and mplayer
```

## The one open bug — fixed (commit `403d87c`)

Dropping `MPlayerX/binaries/arm64/` into place used to make the app crash
shortly after playback started. The crash report showed two faults, and the
open question was which one was the real bug and which was a symptom:

1. **Main thread** — `-[TimeSliderCell drawHorizontalKnobInFrame:]` calls
   `NSBezierPath appendBezierPathWithRoundedRect:xRadius:yRadius:`, which
   raises inside `_deviceMoveToPoint:`. That exception means a NaN or
   infinite rect.

2. **Render thread** — `-[DisplayLayer display]` → `CA::Render::copy_image`
   → vImage, instruction-abort translation fault.

**Root cause was fault 1, and it was the whole bug — fault 2 never
reproduces once fault 1 is fixed.** `TimeSliderCell.m` computed the knob's
width as `[self floatValue]/[self maxValue]`, unguarded. `maxValue` is
legitimately `0` until mplayer reports the movie's duration back, which
happens on the very first draw after playback starts — that division is
`0/0` or `x/0`, and the resulting NaN/infinite rect is what
`appendBezierPathWithRoundedRect:` raises on. The x86_64 build under Rosetta
is slow enough that duration is normally known before the first draw, so the
same bug there only ever showed up as slightly-off knob geometry, never a
crash. The native arm64 mplayer renders fast enough to hit the zero divisor
directly, on every launch. Fix: guard the divide, treat a zero `maxValue` as
knob-width `0`.

The three suspects originally listed against
`-[CoreController startWithWidth:withHeight:withBytes:withAspect:]` were
checked and **ruled out** for this crash, empirically, by instrumenting
`CoreController.m` with temporary `NSLog`s (not committed) and running real
files:

- **The bytes-to-pixel-format guess.** Real ambiguity (2 bytes is YUY2 *or*
  UYVY, 4 bytes is ARGB *or* BGRA), but not what crashed here. Two things
  confirm it: (a) upstream MPlayer's own format search
  (`find_best_out()` / `outfmt_list` in `libmpcodecs/vf_scale.c`) tries
  `IMGFMT_YUY2` before `IMGFMT_UYVY` and — on a little-endian Mac —
  `IMGFMT_BGR32` before `IMGFMT_RGB32`, and `vo_corevideo`'s
  `VFCAP_CSP_SUPPORTED_BY_HW` flag makes the search stop at the first
  match, so for ordinary YUV-sourced video (anything H.264/HEVC-like) YUY2
  always wins — matching MPlayerX's guess. (b) Logging confirmed it in
  practice: every test file negotiated `bytes=2` → `kYUVSPixelFormat`
  ('yuvs' = YUY2), and once fault 1 was fixed, the render path delivered
  frames continuously (~60fps) with no crash. A wrong guess here would
  misdraw colors (channel order swapped), not fault — it can't produce an
  out-of-bounds/NaN access. Worth revisiting only if someone reports a video
  with wrong colors, not for this crash.
- **The aspect conversion.** Logged values were sane (e.g. `aspect=92` for a
  750x814 clip, `92/100 = 0.92`, matching `750/814`); never observed as 0.
- **The single-buffer mmap.** `render` (no-frame-number, upstream flavor)
  always calls `render:0`, so `frameNow` never indexes past the
  single-buffer array. mmap size math checked out against the page size
  (16 KiB on Apple Silicon) too — plenty of same-page slack past the exact
  frame size. Not implicated.

**Not yet re-verified after this fix:** the "UI looks slightly skewed"
symptom on the working x86_64 path. It's plausible it's related (same
`TimeSliderCell` code path) but that wasn't confirmed — see "Remaining work"
below.

## How to reproduce

```bash
cd ~/git/MPlayerX/MPlayerX
xcodebuild -project MPlayerX.xcodeproj -target MPlayerX -configuration Release \
    ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build
open -a "$PWD/build/Release/MPlayerX.app" /path/to/any.mp4
```

To A/B against the working path, move
`build/Release/MPlayerX.app/Contents/Resources/binaries/arm64` aside and
relaunch; it will fall back to x86_64 and behave.

A useful trick for seeing exactly what MPlayerX passes to mplayer: replace the
binary in the built bundle with a shell script that appends `"$@"` to a log and
then `exec`s the real one.

## Committed as of 2026-08-12 (was "Do not commit yet")

`MPlayerX/binaries/arm64/` is now tracked (`f90ebc2`). This section is kept
for history: the crash that originally held it back was fixed at `403d87c`,
and the breadth pass this section called for (seeking, pause/resume,
fullscreen, two codecs) happened in the 2026-08-12 session — see the top of
this document. Subtitles and a wider codec spread are still untested. The
binary remains fully reproducible:

```bash
brew install pkgconf freetype fontconfig fribidi speex
./tools/build-mplayer-arm64.sh
```

That script is committed and is also the GPL corresponding-source record for
the binary, so it must stay accurate if the build changes.

## What each commit does

```
62c0763  Restore Cmd+` half window size shortcut
f90ebc2  Restore MPX_PBST so mplayer.state actually reaches kMPCPlayingState
920474b  Fix time slider progress fill misaligned from its track
fc62cf7  Restore MPX_* mplayer hooks lost when the private patch went missing
faa067f  Build arm64 only; drop the 2011 x86_64/i386 mplayer binaries
eedcd0d  Bump marketing version to 2.0.0
403d87c  Guard the time slider knob against a zero max value
d873d15  Add README, GPL license text and a third-party inventory
8a75353  Speak upstream mplayer's shared buffer protocol as well as MPlayerX's
7e1f548  Only pass mplayer options the binary in use understands
cf7afe7  Replace RubyCocoa in the build scripts with plutil
6bcfe94  Fix defects surfaced by modern compiler warnings
88614a3  Do not abort at startup when the media key tap cannot be created
144939b  Select the mplayer binary by architecture, not by a 64-bit flag
384b442  Build as a universal binary for Apple Silicon
```

Two findings worth carrying forward, because they are not obvious:

- **`VALID_ARCHS = "i386 x86_64"` made Xcode skip every compile and link step
  while still printing `** BUILD SUCCEEDED **`,** leaving an `.app` with no
  executable in it. If a build ever looks suspiciously fast, check that
  `CompileC` lines actually appear in the log.
- **MPlayerX was built against a privately patched mplayer.** `-nodispclog`,
  `-stpause` and `-subid` never existed upstream, and its `vo_corevideo` spoke
  a different DO protocol. Nobody could rebuild that binary, which is a large
  part of why the project stalled. The branch now probes the binary with
  `-list-options` and adapts, rather than carrying a patch set.

## Remaining work after the crash

0. **Ship it (see "How to fix it" above).** Repackaging from `403d87c`,
   verifying the DMG, and adding the arm64 assertion to
   `mplayerx-package.sh` are done (2026-08-11). Only the actual
   `/Applications` swap is left, and it needs the user's own admin
   authentication to do it. Nothing else on this list matters until that
   happens and the user is actually running the native build.
1. **UI layout** (`TimeSliderCell`, `ControlUIView`, the control bar). The user
   reports it renders "slightly skewed" even on the working path. The XIBs are
   2011-era Interface Builder 3 documents, laid out against AppKit metrics that
   have changed. They compile without error under current `ibtool`, so this is
   geometry, not format. Worth a fresh look now that the zero-`maxValue`
   divide in `TimeSliderCell.m` is fixed — re-check whether the skew is still
   there before hunting further.
2. **Warning cleanup.** `GCC_TREAT_WARNINGS_AS_ERRORS` is currently `NO`.
   Roughly 30 remaining warnings are renamed AppKit constants
   (`NSCommandKeyMask` → `NSEventModifierFlagCommand` and similar). Mechanical,
   but a large diff — worth its own commit, and worth doing before the PR if
   the goal is a clean tree.
3. **The PR itself.** Upstream `niltsh/MPlayerX` has had no code commit since
   2011-11-22, so expect the PR to sit. Maintaining the fork is the realistic
   path; the branch is written to be mergeable regardless.

## Legal position, in short

GPLv2-or-later. Forking and opening a PR is squarely within the license.
`THIRD-PARTY-LICENSES.md` used to record two compliance gaps inherited from
upstream; dropping the x86_64/i386 mplayer binaries (see "Going arm64-only"
above) closed one of them. The remaining gap: `SPMediaKeyTap` /
`NSObject+SPInvocationGrabbing` carry no license grant. Do not ship to the Mac
App Store; its terms conflict with the GPL.
