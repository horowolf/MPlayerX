/*
 * MPlayerX - ResizeIndicator.swift
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

@objc(ResizeIndicator)
class ResizeIndicator: NSView {

	private var image: NSImage?
	private var imageRect: NSRect = .zero

	override func awakeFromNib() {
		image = NSImage(named: "resizeindicator")
		imageRect = NSRect(x: 0, y: 0, width: image?.size.width ?? 0, height: image?.size.height ?? 0)
	}

	override func draw(_ dirtyRect: NSRect) {
		// draw the image in the view's bottom-right corner
		image?.draw(at: NSPoint(x: bounds.size.width - imageRect.size.width, y: 0),
					from: imageRect,
					operation: .sourceOver,
					fraction: 1)
	}

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
