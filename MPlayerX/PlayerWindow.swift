/*
 * MPlayerX - PlayerWindow.swift
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

@objc(PlayerWindow)
class PlayerWindow: NSWindow {

	// Not an implicitly-unwrapped optional: NSWindowTemplate sets the window's
	// title (via the `title` property below) during nib instantiation, before
	// outlets are connected -- titlebar is genuinely nil at that point. The
	// original Objective-C version tolerated this for free (messaging nil is
	// a no-op); Swift needs the nil checks spelled out.
	@IBOutlet weak var titlebar: TitleView?

	override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
		super.init(contentRect: contentRect, styleMask: .borderless, backing: bufferingType, defer: flag)
	}

	override func awakeFromNib() {
		self.hasShadow = true
		self.collectionBehavior = [.managed, .fullScreenPrimary]

		self.contentMinSize = NSSize(width: 480, height: 360)

		let screenRC = self.screen?.visibleFrame ?? .zero
		var winRC = self.frame
		winRC.origin.x = screenRC.origin.x + (screenRC.size.width - winRC.size.width) / 2
		winRC.origin.y = screenRC.origin.y + (screenRC.size.height - winRC.size.height) / 2
		self.setFrameOrigin(winRC.origin)
	}

	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { true }
	override var acceptsFirstResponder: Bool { true }

	override var title: String {
		get { titlebar?.title ?? "" }
		set {
			titlebar?.title = newValue
			titlebar?.needsDisplay = true
		}
	}

	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		return true
	}

	override func performZoom(_ sender: Any?) {
		if let delegate = self.delegate {
			let frm = delegate.windowWillUseStandardFrame?(self, defaultFrame: self.screen?.visibleFrame ?? .zero) ?? self.frame
			self.setFrame(frm, display: true, animate: true)
		} else {
			self.zoom(sender)
		}
	}

	override func performMiniaturize(_ sender: Any?) {
		self.miniaturize(sender)
	}

	override func performClose(_ sender: Any?) {
		self.close()
	}

	// When in full screen, clicking the icon in the top-right corner of the screen to return from full screen
	// directly triggers the window's toggleFullScreen function, which is not OK
	@objc func toggleFullScreenReal(_ sender: Any?) {
		super.toggleFullScreen(sender)
	}

	override func toggleFullScreen(_ sender: Any?) {
		// matches KeyCode.h's kSCMFullscreenKeyEquivalentModifierFlagMask (NSCommandKeyMask);
		// spelled out here since Swift's Clang importer won't import that macro
		if let event = NSEvent.makeKeyDownEvent(kSCMFullScrnKeyEquivalent, modifierFlags: NSEvent.ModifierFlags.command.rawValue) {
			self.postEvent(event, atStart: true)
		}
	}

	// MARK: Accessibility

	override func accessibilityAttributeNames() -> [String]? {
		guard var ret = super.accessibilityAttributeNames() else { return nil }
		if !ret.contains(NSAccessibility.Attribute.subrole.rawValue) {
			ret.append(contentsOf: [NSAccessibility.Attribute.subrole.rawValue, kMPXAccessibilityWindowFrameAttribute])
		}
		return ret
	}

	override func accessibilityAttributeValue(_ attribute: String) -> Any? {
		switch attribute {
		case NSAccessibility.Attribute.closeButton.rawValue:
			return titlebar?.closeButton
		case NSAccessibility.Attribute.minimizeButton.rawValue:
			return titlebar?.miniButton
		case NSAccessibility.Attribute.zoomButton.rawValue:
			return titlebar?.zoomButton
		case NSAccessibility.Attribute.description.rawValue:
			return kMPXAccessibilityPlayerWindowDesc
		case NSAccessibility.Attribute.subrole.rawValue:
			return NSAccessibility.Subrole.standardWindow.rawValue
		case kMPXAccessibilityWindowFrameAttribute:
			return NSValue(rect: self.frame)
		default:
			return super.accessibilityAttributeValue(attribute)
		}
	}

	override func accessibilityIsAttributeSettable(_ attribute: String) -> Bool {
		switch attribute {
		case NSAccessibility.Attribute.closeButton.rawValue,
			 NSAccessibility.Attribute.minimizeButton.rawValue,
			 NSAccessibility.Attribute.zoomButton.rawValue,
			 NSAccessibility.Attribute.description.rawValue,
			 NSAccessibility.Attribute.subrole.rawValue:
			// set unsettable
			return false
		case NSAccessibility.Attribute.position.rawValue,
			 NSAccessibility.Attribute.size.rawValue,
			 kMPXAccessibilityWindowFrameAttribute:
			// settable
			return self.contentView?.responds(to: #selector(NSObject.accessibilitySetValue(_:forAttribute:))) == true
		default:
			return super.accessibilityIsAttributeSettable(attribute)
		}
	}

	override func accessibilitySetValue(_ value: Any, forAttribute attribute: String) {
		if (attribute == NSAccessibility.Attribute.position.rawValue ||
			attribute == NSAccessibility.Attribute.size.rawValue ||
			attribute == kMPXAccessibilityWindowFrameAttribute),
		   self.contentView?.responds(to: #selector(NSObject.accessibilitySetValue(_:forAttribute:))) == true {
			self.contentView?.accessibilitySetValue(value, forAttribute: attribute)
		} else {
			super.accessibilitySetValue(value, forAttribute: attribute)
		}
	}

	override func accessibilityIsIgnored() -> Bool { false }
}
