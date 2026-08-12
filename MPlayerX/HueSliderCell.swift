/*
 * MPlayerX - HueSliderCell.swift
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

@objc(HueSliderCell)
class HueSliderCell: BGHUDSliderCell {

	private var hueGradient: NSGradient?

	private static func makeDefaultGradient() -> NSGradient? {
		return NSGradient(colors: [.cyan, .blue, .magenta, .red, .yellow, .green, .cyan])
	}

	override init() {
		super.init()
		hueGradient = HueSliderCell.makeDefaultGradient()
	}

	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)

		if aDecoder.containsValue(forKey: "themeKey") {
			hueGradient = aDecoder.decodeObject(forKey: "themeKey") as? NSGradient
		} else {
			hueGradient = HueSliderCell.makeDefaultGradient()
		}
	}

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(hueGradient, forKey: "themeKey")
	}

	override func drawHorizontalBar(inFrame frame: NSRect) {
		var frame = frame

		switch controlSize {
		case .regular:
			if numberOfTickMarks != 0 {
				if tickMarkPosition == .below {
					frame.origin.y += 4
				} else {
					frame.origin.y += frame.size.height - 10
				}
			} else {
				frame.origin.y = frame.origin.y + (((frame.origin.y + frame.size.height) / 2) - 2.5)
			}

			frame.origin.x += 2.5
			frame.origin.y += 0.5
			frame.size.width -= 5
			frame.size.height = 5

		case .small:
			if numberOfTickMarks != 0 {
				if tickMarkPosition == .below {
					frame.origin.y += 2
				} else {
					frame.origin.y += frame.size.height - 8
				}
			} else {
				frame.origin.y = frame.origin.y + (((frame.origin.y + frame.size.height) / 2) - 2.5)
			}

			frame.origin.x += 0.5
			frame.origin.y += 0.5
			frame.size.width -= 1
			frame.size.height = 5

		case .mini:
			if numberOfTickMarks != 0 {
				if tickMarkPosition == .below {
					frame.origin.y += 2
				} else {
					frame.origin.y += frame.size.height - 6
				}
			} else {
				frame.origin.y = frame.origin.y + (((frame.origin.y + frame.size.height) / 2) - 2)
			}

			frame.origin.x += 0.5
			frame.origin.y += 0.5
			frame.size.width -= 1
			frame.size.height = 3

		default:
			// matches the original Objective-C switch, which only handled
			// NSRegularControlSize/NSSmallControlSize/NSMiniControlSize and
			// left the frame untouched for anything else
			break
		}

		// Draw Bar
		let path = NSBezierPath()
		path.appendRoundedRect(frame, xRadius: 2, yRadius: 2)

		hueGradient?.draw(in: path, angle: 0.0)

		let theme = BGThemeManager.keyed()?.theme(forKey: self.themeKey)
		if isEnabled {
			theme?.strokeColor()?.set()
			path.stroke()
		} else {
			theme?.disabledSliderTrackColor()?.set()
			path.fill()

			theme?.disabledStrokeColor()?.set()
			path.stroke()
		}
	}
}
