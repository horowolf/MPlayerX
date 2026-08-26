/*
 * MPlayerX - MPApplication.swift
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

import Cocoa

/// The application object is instantiated by NSPrincipalClass in
/// MPlayerX-Info.plist and by MainMenu.xib, both of which name the class by
/// string, so the ObjC runtime name has to stay exactly "MPApplication".
@objc(MPApplication)
class MPApplication: NSApplication {

	/// Unmodified key equivalents that have to act once per physical press.
	///
	/// While a key is held down the window server keeps delivering keyDown
	/// events with `isARepeat` set, and neither NSButton nor NSMenu filters
	/// them out before invoking the action. For a toggle that means the state
	/// flips once per repeat, so whether a held key appears to have done
	/// anything comes down to whether the number of repeats happened to be
	/// odd. Measured on a 900ms press: 13 repeats, 14 play/pause flips, the
	/// video still playing -- which is the long-standing report that the space
	/// bar "doesn't always work". The episode keys fail more visibly: holding
	/// `.` walks several files down the playlist instead of advancing one.
	///
	/// Only the unmodified keys are listed. The modified variants of these same
	/// characters are the step controls -- window size, subtitle scale, audio
	/// and subtitle delay -- where repeating is the whole point, as it is for
	/// volume and for the arrow keys that seek.
	private static let keysThatMustNotAutorepeat: Set<String> = [
		kSCMPlayPauseKeyEquivalent,             // space
		kSCMNextEpisodeKeyEquivalent,           // .
		kSCMPrevEpisodeKeyEquivalent,           // ,
		kSCMFullScrnKeyEquivalent,              // f
		kSCMSwitchAudioKeyEquivalent,           // a
		kSCMSwitchVideoKeyEquivalent,           // v
		kSCMShowMediaInfoKeyEquivalent,         // i
		kSCMToggleLetterBoxKeyEquivalent,       // l
		kSCMAcceControlKeyEquivalent,           // c
		kSCMVideoTunerPanelKeyEquivalent,       // d
		kSCMEqualizerPanelKeyEquivalent,        // e
		kSCMToggleLockAspectRatioKeyEquivalent, // r
		kSCMMuteKeyEquivalent,                  // m
	]

	private func shouldDropAutorepeat(of event: NSEvent) -> Bool {
		guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
			  let chars = event.charactersIgnoringModifiers,
			  Self.keysThatMustNotAutorepeat.contains(chars.lowercased()) else { return false }

		// Never intercept while text is being edited: holding a key down to
		// type a run of the same character still has to work in the Open URL
		// sheet, the preferences and anywhere else with a field editor.
		return !(keyWindow?.firstResponder is NSText)
	}

	override func sendEvent(_ event: NSEvent) {
		if event.type == .keyDown, event.isARepeat, shouldDropAutorepeat(of: event) {
			return
		}
		super.sendEvent(event)
	}
}
