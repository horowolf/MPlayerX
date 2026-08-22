/*
 * MPlayerX - MPXWindowButton.swift
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

// Was an NS_ENUM in MPXWindowButton.h, kept there only while TitleView was
// still Objective-C and referenced its cases as bare kMPXWindow*ButtonType
// identifiers.
@objc enum MPXWindowButtonType: Int {
	case closeButtonType = 1
	case minimizeButtonType = 2
	case zoomButtonType = 3
	case fullscreenButtonType = 4
}

private let kMPXAccessibilityCloseButtonDesc = "closeButton"
private let kMPXAccessibilityMinimizeButtonDesc = "minimizeButton"
private let kMPXAccessibilityZoomButtonDesc = "zoomButton"

@objc(MPXWindowButton)
class MPXWindowButton: NSButton {

	@objc private(set) var windowButtonType: MPXWindowButtonType

	@objc(initWithFrame:type:) init(frame: NSRect, type: MPXWindowButtonType) {
		windowButtonType = type
		super.init(frame: frame)

		self.setButtonType(.momentaryChange)
		self.imagePosition = .imageOnly
		self.isBordered = false
		self.autoresizingMask = [.maxXMargin, .maxYMargin]
		self.isContinuous = false
	}

	required init?(coder: NSCoder) {
		windowButtonType = .closeButtonType
		super.init(coder: coder)
	}

	override class var cellClass: AnyClass? {
		get { MPXWindowButtonCell.self }
		set { }
	}

	// MARK: Accessibility

	override func accessibilityPerformAction(_ action: String) {
		if action == NSAccessibility.Action.press.rawValue {
			if isEnabled {
				performClick(nil)
			}
		} else {
			super.accessibilityPerformAction(action)
		}
	}
}

@objc(MPXWindowButtonCell)
class MPXWindowButtonCell: NSButtonCell {

	override func accessibilityAttributeNames() -> [String]? {
		guard var ret = super.accessibilityAttributeNames() else { return nil }

		if let button = controlView as? MPXWindowButton {
			if !ret.contains(NSAccessibility.Attribute.subrole.rawValue) {
				ret.append(NSAccessibility.Attribute.subrole.rawValue)
			}
			if button.windowButtonType == .closeButtonType,
			   !ret.contains(NSAccessibility.Attribute.edited.rawValue) {
				ret.append(NSAccessibility.Attribute.edited.rawValue)
			}
		}
		return ret
	}

	override func accessibilityAttributeValue(_ attribute: String) -> Any? {
		guard let button = controlView as? MPXWindowButton else {
			return super.accessibilityAttributeValue(attribute)
		}

		let type = button.windowButtonType

		if attribute == NSAccessibility.Attribute.subrole.rawValue {
			switch type {
			case .closeButtonType:
				return NSAccessibility.Subrole.closeButton.rawValue
			case .minimizeButtonType:
				return NSAccessibility.Subrole.minimizeButton.rawValue
			case .zoomButtonType:
				return NSAccessibility.Subrole.zoomButton.rawValue
			default:
				return NSAccessibility.Subrole.unknown.rawValue
			}
		} else if attribute == NSAccessibility.Attribute.description.rawValue {
			switch type {
			case .closeButtonType:
				return kMPXAccessibilityCloseButtonDesc
			case .minimizeButtonType:
				return kMPXAccessibilityMinimizeButtonDesc
			case .zoomButtonType:
				return kMPXAccessibilityZoomButtonDesc
			default:
				return ""
			}
		} else if attribute == NSAccessibility.Attribute.edited.rawValue {
			return NSNumber(value: false)
		} else {
			return super.accessibilityAttributeValue(attribute)
		}
	}

	override func accessibilityIsAttributeSettable(_ attribute: String) -> Bool {
		if attribute == NSAccessibility.Attribute.subrole.rawValue ||
			attribute == NSAccessibility.Attribute.edited.rawValue {
			return false
		}
		return super.accessibilityIsAttributeSettable(attribute)
	}

	override func accessibilityIsIgnored() -> Bool { false }
}
