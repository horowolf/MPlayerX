/*
 * MPlayerX - PlayingInfo.swift
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

// kPIAudioIDInvalid / kPIVideoIDInvalid existed in the original header but were
// never referenced anywhere else in the codebase; dropped as dead code rather
// than ported.

@objc(PlayingInfo)
class PlayingInfo: NSObject {
	@objc var currentChapter: UInt8 = 0
	@objc dynamic var currentTime: NSNumber = 0
	@objc dynamic var currentAudioID: NSNumber?
	@objc dynamic var currentVideoID: NSNumber?
	@objc var currentSubID: NSNumber?

	@objc var volume: Float = 100
	@objc var audioBalance: Float = 0
	@objc var mute: Bool = false
	@objc dynamic var audioDelay: NSNumber = 0
	@objc dynamic var subDelay: NSNumber = 0
	@objc var subPos: Float = 100
	@objc var subScale: NSNumber = 1.5
	@objc dynamic var speed: NSNumber = 1.0
	@objc dynamic var cachingPercent: NSNumber = 0

	@objc(resetWithParameterManager:)
	func reset(with pm: ParameterManager?) {
		currentChapter = 0

		// May all need KVO in the future
		audioBalance = 0

		// pm being nil here mirrors the original Objective-C, which sent
		// -volume/-subPos/-subScale to a possibly-nil pm and relied on
		// message-to-nil returning zero.
		volume = pm?.volume ?? 0
		subPos = pm?.subPos ?? 0
		subScale = NSNumber(value: pm?.subScale ?? 0)

		mute = false
		currentTime = 0
		audioDelay = 0
		subDelay = 0
		speed = 1
		cachingPercent = 0

		currentAudioID = nil
		currentVideoID = nil
		currentSubID = nil
	}
}
