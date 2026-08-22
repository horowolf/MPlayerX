/*
 * MPlayerX - KeyCode.swift
 *
 * Copyright (C) 2009 - 2011, Zongyao QU
 *
 * MPlayerX is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * MPlayerX is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with MPlayerX; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

// Was KeyCode.h/.m. The key equivalents keep the exact same bare identifiers
// they had as `extern NSString * const`, so every call site is unchanged; the
// modifier masks, which used to be C macros spelled with the pre-10.12 AppKit
// names (NSCommandKeyMask etc.), are now typed NSEvent.ModifierFlags values.
import Cocoa

// MARK: - short keys definition

let kSCMVolumeUpKeyEquivalent   = "="
let kSCMVolumeDownKeyEquivalent = "-"
let kSCMSwitchAudioKeyEquivalent = "a"
let kSCMSwitchSubKeyEquivalent   = "s"
let kSCMSnapShotKeyEquivalent    = "S"
let kSCMMuteKeyEquivalent        = "m"
let kSCMPlayPauseKeyEquivalent   = " "
let kSCMSwitchVideoKeyEquivalent = "v"

let kSCMSwitchTimeHintKeyModifierMask: NSEvent.ModifierFlags = .function

let kSCMFullScrnKeyEquivalent = "f"
let kSCMFullscreenKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .command

let kSCMFillScrnKeyEquivalent    = "F"
let kSCMAcceControlKeyEquivalent = "c"

let kSCMSubScaleIncreaseKeyEquivalent = "="
let kSCMSubScaleIncreaseKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .command
let kSCMSubScaleDecreaseKeyEquivalent = "-"
let kSCMSubScaleDecreaseKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .command

let kSCMPlayFromLastStoppedKeyEquivalent = "c"
let kSCMPlayFromLastStoppedKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .shift

let kSCMToggleLockAspectRatioKeyEquivalent = "r"

let kSCMResetLockAspectRatioKeyEquivalent = "r"
let kSCMResetLockAspectRatioKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .shift

let kSCMVideoTunerPanelKeyEquivalent = "d"

let kSCMToggleLetterBoxKeyEquivalent = "l"

let kSCMSpeedUpKeyEquivalent    = "]"
let kSCMSpeedDownKeyEquivalent  = "["
let kSCMSpeedResetKeyEquivalent = "\\"

let kSCMAudioDelayPlusKeyEquivalent  = "]"
let kSCMAudioDelayMinusKeyEquivalent = "["
let kSCMAudioDelayResetKeyEquivalent = "\\"
let kSCMAudioDelayKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .option

let kSCMSubDelayPlusKeyEquivalent  = "]"
let kSCMSubDelayMinusKeyEquivalent = "["
let kSCMSubDelayResetKeyEquivalent = "\\"
let kSCMSubDelayKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .command

let kSCMFFMpegHandleStreamShortCurKey: NSEvent.ModifierFlags = .command

let kSCMWindowSizeIncKeyEquivalent = "="
let kSCMWindowSizeIncKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = [.command, .option]
let kSCMWindowSizeDecKeyEquivalent = "-"
let kSCMWindowSizeDecKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = [.command, .option]

let kSCMShowMediaInfoKeyEquivalent = "i"

let kSCMEqualizerPanelKeyEquivalent = "e"

/// NSBackspaceCharacter; set on the menu item as a one-character string.
let kSCMMoveToTrashKeyEquivalent: unichar = 8
let kSCMMoveToTrashKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .command

let kSCMMoveFrameToCenterKeyEquivalent = "t"

let kSCMNextEpisodeKeyEquivalent = "."
let kSCMPrevEpisodeKeyEquivalent = ","

let kSCMScaleFrameKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .option

let kSCMResetFrameScaleRatioKeyEquivalent = "t"
let kSCMResetFrameScaleRatioKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .shift

let kSCMDragFullScrFrameModifierFlagMask: NSEvent.ModifierFlags = .option

/**
 * ctrl + = has bug, always fallback to =
 */
let kSCMScaleFrameLargerKeyEquivalent = "="
let kSCMScaleFrameLargerKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .option
let kSCMScaleFrameSmallerKeyEquivalent = "-"
let kSCMScaleFrameSmallerKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .option

let kSCMScaleFrameLarger2KeyEquivalent = "="
let kSCMScaleFrameLarger2KeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = [.option, .shift]
let kSCMScaleFrameSmaller2KeyEquivalent = "-"
let kSCMScaleFrameSmaller2KeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = [.option, .shift]

let kSCMMirrorKeyEquivalent = "m"
let kSCMMirrorKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .option
let kSCMFlipKeyEquivalent = "f"
let kSCMFlipKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .option

let kSCMWindowZoomHalfSizeKeyEquivalent = "`"
let kSCMWindowZoomHalfSizeKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .command
let kSCMWindowZoomToOrgSizeKeyEquivalent = "1"
let kSCMWindowZoomToOrgSizeKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .command
let kSCMWindowZoomDblSizeKeyEquivalent = "2"
let kSCMWindowZoomDblSizeKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .command
let kSCMWindowFitToScreenKeyEquivalent = "3"
let kSCMWindowFitToScreenKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .command

let kSCMRotateKeyEquivalentModifierFlagMask: NSEvent.ModifierFlags = .option
