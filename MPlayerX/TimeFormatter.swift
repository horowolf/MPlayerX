/*
 * MPlayerX - TimeFormatter.swift
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

@objc(TimeFormatter)
class TimeFormatter: Formatter {

	@objc(stringForIntegerValue:)
	static func string(forIntegerValue time: Int) -> String {
		var time = time
		let negative = time < 0
		if negative {
			time = -time
		}

		let sec = time % 60
		time = (time - sec) / 60

		let minute = time % 60
		let hour = (time - minute) / 60

		let formatString = negative ? "-%02d:%02d:%02d" : "%02d:%02d:%02d"
		return String(format: formatString, hour, minute, sec)
	}

	override func string(for obj: Any?) -> String? {
		guard let num = obj as? NSNumber else { return nil }
		return TimeFormatter.string(forIntegerValue: num.intValue)
	}

	override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
		if !string.isEmpty {
			obj?.pointee = NSNumber(value: (string as NSString).floatValue)
			return true
		}
		return false
	}
}
