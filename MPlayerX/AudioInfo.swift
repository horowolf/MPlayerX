/*
 * MPlayerX - AudioInfo.swift
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

private func mpxIntValue(_ obj: Any?) -> Int32 {
	if let n = obj as? NSNumber { return n.int32Value }
	if let s = obj as? NSString { return s.intValue }
	return 0
}

@objc(AudioInfo)
class AudioInfo: NSObject {
	@objc var ID: Int32 = -2
	@objc var language: String?
	@objc var name: String?

	@objc var codec: String?
	@objc var format: String?
	@objc var bitRate: Int32 = 0
	@objc var sampleRate: Int32 = 0
	@objc var sampleSize: Int32 = 0
	@objc var channels: Int32 = 0

	// What is in the arr?
	// [0] Not used (actually this is ID of the AI now)
	// [1] Format
	// [2] BitRate
	// [3] SampleRate
	// [4] Bits per Sample
	// [5] Number of channels
	// [6] Codec name
	//
	// This definition is depended on the output of mplayer.
	// should de-coupling with mplayer
	@objc(setInfoDataWithArray:)
	func setInfoData(with arr: [Any]) {
		guard arr.count >= 7 else { return }
		format = arr[1] as? String
		bitRate = mpxIntValue(arr[2])
		sampleRate = mpxIntValue(arr[3])
		sampleSize = mpxIntValue(arr[4]) * 8
		channels = mpxIntValue(arr[5])
		codec = arr[6] as? String
	}

	override var description: String {
		let strName = name ?? "noname"
		let strLang = language ?? "unknown"
		return "\(ID): \(strName) [\(strLang)]"
	}
}
