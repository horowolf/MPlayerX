/*
 * MPlayerX - VideoInfo.swift
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

private func mpxFloatValue(_ obj: Any?) -> Float {
	if let n = obj as? NSNumber { return n.floatValue }
	if let s = obj as? NSString { return s.floatValue }
	return 0
}

@objc(VideoInfo)
class VideoInfo: NSObject {
	@objc var ID: Int32 = -2
	@objc var language: String?
	@objc var name: String?

	@objc var codec: String?
	@objc var format: String?
	@objc var bitRate: Int32 = 0
	@objc var width: Int32 = 0
	@objc var height: Int32 = 0
	@objc var fps: Float = 0
	@objc var aspect: Float = 0

	// What is in the arr?
	// [0] Not used (actually the ID of VI)
	// [1] Format
	// [2] BitRate
	// [3] Width
	// [4] Height
	// [5] Frames per second
	// [6] Aspect ratio
	// [7] Codec name
	//
	// This definition is depended on mplayer,
	// should de-coupling with mplayer
	@objc(setInfoDataWithArray:)
	func setInfoData(with arr: [Any]) {
		guard arr.count >= 8 else { return }
		format = arr[1] as? String
		bitRate = mpxIntValue(arr[2])
		width = mpxIntValue(arr[3])
		height = mpxIntValue(arr[4])
		fps = mpxFloatValue(arr[5])
		aspect = mpxFloatValue(arr[6])
		codec = arr[7] as? String
	}

	override var description: String {
		let strName = name ?? "noname"
		let strLang = language ?? "unknown"
		return "\(ID): \(strName) [\(strLang)]"
	}
}
