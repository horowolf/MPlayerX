/*
 * MPlayerX - PlayerControllerConstants.swift
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

// Was PlayerControllerConstants.h/.m, which only existed because the (then
// Objective-C) RootLayerView/ControlUIView referenced these notification names
// as bare identifiers. Both are Swift now, so the table can be Swift too.
//
// The names keep their string values, and the Notification.Name members below
// keep the spellings the Objective-C importer used to synthesize for them, so
// no call site changes.

import Foundation

let kMPCPlayOpenedNotification = "kMPCPlayOpenedNotification"
let kMPCPlayOpenedURLKey = "kMPCPlayOpenedURLKey"
let kMPCPlayLastStoppedTimeKey = "kMPCPlayLastStoppedTimeKey"
let kMPCPlayStartedNotification = "kMPCPlayStartedNotification"
let kMPCPlayStartedAudioOnlyKey = "kMPCPlayStartedAudioOnlyKey"
let kMPCPlayStoppedNotification = "kMPCPlayStoppedNotification"
let kMPCPlayWillStopNotification = "kMPCPlayWillStopNotification"
let kMPCPlayFinalizedNotification = "kMPCPlayFinalizedNotification"
let kMPCPlayInfoUpdatedNotification = "kMPCPlayInfoUpdatedNotification"
let kMPCPlayInfoUpdatedKeyPathKey = "kMPCPlayInfoUpdatedKeyPathKey"
let kMPCPlayInfoUpdatedChangeDictKey = "kMPCPlayInfoUpdatedChangeDictKey"

extension NSNotification.Name {
	static let mpcPlayOpened = NSNotification.Name(kMPCPlayOpenedNotification)
	static let mpcPlayStarted = NSNotification.Name(kMPCPlayStartedNotification)
	static let mpcPlayWillStop = NSNotification.Name(kMPCPlayWillStopNotification)
	static let mpcPlayStopped = NSNotification.Name(kMPCPlayStoppedNotification)
	static let mpcPlayFinalized = NSNotification.Name(kMPCPlayFinalizedNotification)
	static let mpcPlayInfoUpdated = NSNotification.Name(kMPCPlayInfoUpdatedNotification)
}
