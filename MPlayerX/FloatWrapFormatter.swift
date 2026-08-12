/*
 * MPlayerX - FloatWrapFormatter.swift
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

private let kFMTFloat1 = "%.1f"

@objc(FloatWrapFormatter)
class FloatWrapFormatter: Formatter {

	override func string(for obj: Any?) -> String? {
		guard let num = obj as? NSNumber else { return nil }
		return String(format: kFMTFloat1, num.floatValue)
	}

	override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
		obj?.pointee = NSNumber(value: (string as NSString).floatValue)
		return true
	}
}
