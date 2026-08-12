/*
 * MPlayerX - TimeSliderCell.swift
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

private enum TSDragState {
	case stopped
	case started
	case `continue`
}

@objc(TimeSliderCell)
class TimeSliderCell: BGHUDSliderCell {

	@objc private(set) var isDragging: Bool = false
	private var dragState: TSDragState = .stopped

	private func timeTrackRect(forFrame frame: NSRect) -> NSRect {
		var frame = frame
		frame.origin.x += 0.5
		frame.origin.y += (frame.size.height - 8.0) / 2.0
		frame.size.width -= 1.0
		frame.size.height = 8.0
		return frame
	}

	required init(coder decoder: NSCoder) {
		super.init(coder: decoder)
		isDragging = false
		dragState = .stopped
	}

	override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
		dragState = .started
		return super.startTracking(at: startPoint, in: controlView)
	}

	override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
		dragState = .stopped
		super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
	}

	override func continueTracking(last lastPoint: NSPoint, current currentPoint: NSPoint, in controlView: NSView) -> Bool {
		switch dragState {
		case .stopped:
			isDragging = false
		case .started:
			dragState = .continue
		case .continue:
			isDragging = true
		}
		return super.continueTracking(last: lastPoint, current: currentPoint, in: controlView)
	}

	override func drawBar(inside rect: NSRect, flipped: Bool) {
		if sliderType == .linear {
			if !isVertical {
				drawHorizontalBar(inFrame: rect)
				return
			}
			// else: drawVerticalBar(inFrame:) -- not implemented, matches original
		}
		// else: NSCircularSlider -- placeholder, matches original
		super.drawBar(inside: rect, flipped: flipped)
	}

	override func drawKnob(_ rect: NSRect) {
		if sliderType == .linear {
			if !isVertical {
				drawHorizontalKnob(inFrame: rect)
				return
			}
			// else: drawVerticalKnob(inFrame:) -- not implemented, matches original
		}
		// else: NSCircularSlider -- placeholder, matches original
		super.drawKnob(rect)
	}

	override func drawHorizontalBar(inFrame frame: NSRect) {
		guard controlSize == .small else {
			super.drawHorizontalBar(inFrame: frame)
			return
		}
		let frame = timeTrackRect(forFrame: frame)

		let path = NSBezierPath()
		path.appendRoundedRect(frame, xRadius: 4, yRadius: 4)

		if isEnabled {
			NSColor(deviceWhite: 0.04, alpha: 0.20).set()
			path.fill()

			NSColor(deviceWhite: 0.50, alpha: 0.20).set()
			path.stroke()
		} else {
			NSColor(deviceWhite: 0.04, alpha: 0.20).set()
			path.fill()
		}
	}

	override func drawHorizontalKnob(inFrame frame: NSRect) {
		guard controlSize == .small else {
			super.drawHorizontalKnob(inFrame: frame)
			return
		}

		var rcBounds = timeTrackRect(forFrame: controlView?.bounds ?? .zero)

		// maxValue is 0 before the movie's duration is known (e.g. the very
		// first draw after playback starts); floatValue/maxValue would then
		// be 0/0 or x/0, producing a NaN/infinite rect that crashes
		// appendRoundedRect:.
		let maxValue = self.maxValue
		var fillRatio = maxValue > 0 ? (self.floatValue / Float(maxValue)) : 0.0
		fillRatio = min(max(fillRatio, 0.0), 1.0)
		let capRadius = rcBounds.size.height / 2.0
		let usableWidth = max(rcBounds.size.width - (capRadius * 2.0), 0.0)
		let dotCenterX = rcBounds.origin.x + capRadius + (usableWidth * CGFloat(fillRatio))
		rcBounds.size.width = min(rcBounds.size.width, dotCenterX - rcBounds.origin.x + capRadius)

		let path = NSBezierPath()
		if rcBounds.size.width > 0 {
			path.appendRoundedRect(rcBounds, xRadius: 4, yRadius: 4)
		}

		let dot = NSBezierPath()
		dot.appendOval(in: NSRect(x: dotCenterX - 2.0, y: rcBounds.origin.y + 2.0, width: 4, height: 4))

		if isEnabled {
			NSColor(deviceWhite: 0.96, alpha: 1.0).set()
			path.fill()
		} else {
			NSColor(deviceWhite: 0.3, alpha: 1.0).set()
			path.fill()
		}

		NSColor(deviceWhite: 0.0, alpha: 0.3).set()
		path.stroke()

		NSColor.black.set()
		dot.fill()
	}
}
