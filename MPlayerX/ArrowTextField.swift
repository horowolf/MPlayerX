/*
 * MPlayerX - ArrowTextField.swift
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

@objc(ArrowTextField)
class ArrowTextField: NSTextField, NSTextViewDelegate {

	@objc var stepValue: Float = 0

	func textView(_ aTextView: NSTextView, doCommandBy aSelector: Selector) -> Bool {
		// When use up/down arrow, to step the value
		if aSelector == #selector(NSResponder.moveUp(_:)) {
			self.floatValue += stepValue
			_ = target?.perform(action, with: self)
			return true
		} else if aSelector == #selector(NSResponder.moveDown(_:)) {
			self.floatValue -= stepValue
			_ = target?.perform(action, with: self)
			return true
		}
		return tryToPerform(aSelector, with: aTextView)
	}
}
