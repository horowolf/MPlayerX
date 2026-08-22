/*
 * MPlayerX - OsdText.swift
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
import QuartzCore

private let kOSDAutoHideTimeInterval: Float = 5

private let kOSDFontSizeMinDefault: Float = 24
private let kOSDFontSizeMaxDefault: Float = 48

/// Was a plain C enum in OsdTextDefs.h while ControlUIView and RootLayerView
/// were still ObjC and needed the bare kOSDOwner* spellings; both are Swift
/// now, so it lives here.
@objc(OSDOWNER)
enum OSDOWNER: Int {
	case time = 1
	case other = 2
}

@objc(OsdText)
class OsdText: NSTextField {

	private let ud = UserDefaults.standard

	private var activeValue = false
	private var shouldHide = true
	private var ownerValue = OSDOWNER.other

	/// Renamed from the original's `shadow` ivar: NSView already has a `shadow`
	/// property, which the ObjC ivar quietly shadowed without ever touching.
	private var textShadow: NSShadow

	private let fontSizeMax: Float
	private let fontSizeMin: Float
	private let fontSizeRatio: Float
	private let fontSizeOffset: Float

	private var autoHideTimer: Timer?
	private var autoHideTimeInterval: TimeInterval = 0

	@objc var active: Bool {
		@objc(isActive) get { activeValue }
		@objc(setActive:) set { activeValue = newValue }
	}

	@objc var owner: OSDOWNER { ownerValue }

	@objc var frontColor: NSColor?

	/// Replaces the ObjC +initialize.
	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [
			kUDKeyOSDFontSizeMax: kOSDFontSizeMaxDefault,
			kUDKeyOSDFontSizeMin: kOSDFontSizeMinDefault,
			// NSArchiver rather than NSKeyedArchiver on purpose: this value is
			// persisted in the user defaults, and switching format would silently
			// discard the color already saved on every existing install.
			kUDKeyOSDFrontColor: NSArchiver.archivedData(withRootObject: NSColor(deviceWhite: 1.0, alpha: 1.0)),
			kUDKeyOSDAutoHideTime: kOSDAutoHideTimeInterval,
		])
	}()

	required init?(coder: NSCoder) {
		_ = OsdText.registerDefaultsOnce

		let ud = UserDefaults.standard
		fontSizeMin = ud.float(forKey: kUDKeyOSDFontSizeMin)
		fontSizeMax = ud.float(forKey: kUDKeyOSDFontSizeMax)

		// mapping height of 300 px to font size Min
		//         height of 900 px to font size Max
		// 300 * ratio + offset = Min
		// 900 * ratio + offset = Max
		// so
		// ratio  = (  Max - Min) / 600
		// offset = (3*Min - Max) / 2
		fontSizeRatio = (fontSizeMax - fontSizeMin) / 600.0
		fontSizeOffset = (3 * fontSizeMin - fontSizeMax) / 2.0

		textShadow = NSShadow()

		super.init(coder: coder)

		if let data = ud.object(forKey: kUDKeyOSDFrontColor) as? Data {
			frontColor = NSUnarchiver.unarchiveObject(with: data) as? NSColor
		}

		textShadow.shadowOffset = NSSize(width: 1.0, height: -1.0)
		textShadow.shadowColor = NSColor.black
		textShadow.shadowBlurRadius = 8

		alphaValue = 0
		isSelectable = false
		allowsEditingTextAttributes = true
		drawsBackground = false
		isBezeled = false

		setAutoHideTimeInterval(TimeInterval(ud.float(forKey: kUDKeyOSDAutoHideTime)))
	}

	deinit {
		autoHideTimer?.invalidate()
	}

	override func animation(forKey key: NSAnimatablePropertyKey) -> Any? {
		nil
	}

	@objc(setAutoHideTimeInterval:)
	func setAutoHideTimeInterval(_ ti: TimeInterval) {
		autoHideTimer?.invalidate()
		autoHideTimer = nil

		guard ti > 0 else { return }

		autoHideTimeInterval = ti
		let timer = Timer(timeInterval: autoHideTimeInterval / 2,
						  target: self,
						  selector: #selector(tryToHide),
						  userInfo: nil,
						  repeats: true)
		autoHideTimer = timer

		let rl = RunLoop.main
		rl.add(timer, forMode: .default)
		rl.add(timer, forMode: .modalPanel)
		rl.add(timer, forMode: .eventTracking)
	}

	@objc private func tryToHide() {
		if shouldHide {
			alphaValue = 0
		} else {
			shouldHide = true
		}
	}

	@objc(setStringValue:owner:updateTimer:)
	func setStringValue(_ aString: String?, owner ow: OSDOWNER, updateTimer ut: Bool) {
		guard activeValue else { return }

		if ut || (alphaValue > 0 && ow == ownerValue) {
			// If the timer is being updated, that means the owner is going to change
			// If not updating, then update as long as self isn't hidden and the owner is unchanged
			// If it's nil, use the current value
			let text = aString ?? stringValue

			let sz = superview?.bounds.size ?? .zero

			let fontSize = min(fontSizeMax, max(fontSizeMin, (Float(sz.height) * fontSizeRatio) + fontSizeOffset))

			let font = NSFont.systemFont(ofSize: CGFloat(fontSize))

			var attrDict: [NSAttributedString.Key: Any] = [
				.font: font,
				.shadow: textShadow,
			]
			if let frontColor {
				attrDict[.foregroundColor] = frontColor
			}
			let str = NSAttributedString(string: text, attributes: attrDict)

			CATransaction.begin()
			CATransaction.setDisableActions(true)
			objectValue = str
			alphaValue = 1
			CATransaction.commit()
		}
		if ut {
			// If the timer is being updated, then update the owner
			ownerValue = ow
			shouldHide = false
		}
	}
}
