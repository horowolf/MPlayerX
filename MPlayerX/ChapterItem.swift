/*
 * MPlayerX - ChapterItem.swift
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

@objc(ChapterItem)
class ChapterItem: NSObject {
	@objc var name: String?
	@objc var start: Int = 0
	@objc var end: Int = 0

	override var description: String {
		let startStr = TimeFormatter.string(forIntegerValue: start / kMPCChapterTimeBase)
		let endStr = TimeFormatter.string(forIntegerValue: end / kMPCChapterTimeBase)
		return "\(name ?? "") [\(startStr) - \(endStr)]"
	}
}
