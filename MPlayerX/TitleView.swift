/*
 * MPlayerX - TitleView.swift
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

private let kStringDots = "..."
private let trackRect = NSRect(x: 0, y: 0, width: 70, height: 23)

@objc(TitleView)
class TitleView: NSView {

	@objc private(set) var closeButton: NSButton!
	@objc private(set) var miniButton: NSButton!
	@objc private(set) var zoomButton: NSButton!

	private var tbCornerLeft: NSImage!
	private var tbCornerRight: NSImage!
	private var tbMiddle: NSImage!

	private var imgCloseActive: NSImage!
	private var imgCloseInactive: NSImage!
	private var imgCloseRollover: NSImage!

	private var imgMiniActive: NSImage!
	private var imgMiniInactive: NSImage!
	private var imgMiniRollover: NSImage!

	private var imgZoomActive: NSImage!
	private var imgZoomInactive: NSImage!
	private var imgZoomRollover: NSImage!

	private var fsButton: NSButton?
	private var imgFSActive: NSImage?
	private var imgFSRollver: NSImage?

	/// Kept as an implicitly-unwrapped optional so the property imports back
	/// into ObjC (and into PlayerWindow.swift) exactly as the unannotated
	/// `NSString *title` did.
	@objc var title: String!
	private var titleAttr: [NSAttributedString.Key: Any] = [:]

	private var mouseEntered = false
	private var fsBtnEntered = false

	private var didSetup = false

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setup()
	}

	/// The ObjC original only implemented -initWithFrame:, relying on NSView's
	/// -initWithCoder: routing through it for the MainMenu.xib instance. The
	/// guard keeps that working whichever way AppKit gets here, without setting
	/// everything up twice.
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setup()
	}

	private func setup() {
		guard !didSetup else { return }
		didSetup = true

		UserDefaults.standard.addSuite(named: UserDefaults.globalDomain)

		title = nil
		titleAttr = [
			.foregroundColor: NSColor.white,
			.font: NSFont.titleBarFont(ofSize: 0),
		]

		tbCornerLeft = NSImage(named: "titlebar-corner-left.png")
		tbCornerRight = NSImage(named: "titlebar-corner-right.png")
		tbMiddle = NSImage(named: "titlebar-middle.png")

		let graphite = UserDefaults.standard.integer(forKey: "AppleAquaColorVariant") == 6

		// The Snow Leopard titlebar art -- the *.tiff button set, and a window
		// with no fullscreen button -- sat behind a pre-Lion branch that cannot
		// be reached on an 11.0 deployment target. Only the Lion artwork is left.
		if graphite {
			// graphite theme
			imgCloseActive = NSImage(named: "close-active-graphite-lion.png")
			imgCloseInactive = NSImage(named: "close-inactive-disabled-graphite-lion.png")
			imgCloseRollover = NSImage(named: "close-rollover-graphite-lion.png")

			imgMiniActive = NSImage(named: "minimize-active-graphite-lion.png")
			imgMiniInactive = NSImage(named: "minimize-inactive-disabled-graphite-lion.png")
			imgMiniRollover = NSImage(named: "minimize-rollover-graphite-lion.png")

			imgZoomActive = NSImage(named: "zoom-active-graphite-lion.png")
			imgZoomInactive = NSImage(named: "zoom-inactive-disabled-graphite-lion.png")
			imgZoomRollover = NSImage(named: "zoom-rollover-graphite-lion.png")
		} else {
			imgCloseActive = NSImage(named: "close-active-lion.png")
			imgCloseInactive = NSImage(named: "close-inactive-disabled-lion.png")
			imgCloseRollover = NSImage(named: "close-rollover-lion.png")

			imgMiniActive = NSImage(named: "minimize-active-lion.png")
			imgMiniInactive = NSImage(named: "minimize-inactive-disabled-lion.png")
			imgMiniRollover = NSImage(named: "minimize-rollover-lion.png")

			imgZoomActive = NSImage(named: "zoom-active-lion.png")
			imgZoomInactive = NSImage(named: "zoom-inactive-disabled-lion.png")
			imgZoomRollover = NSImage(named: "zoom-rollover-lion.png")
		}
		// read the image
		imgFSActive = NSImage(named: "fullscreen-active-lion")
		imgFSRollver = NSImage(named: "fullscreen-rollover-lion")
		//
		let fs = MPXWindowButton(frame: NSRect(x: 4, y: 0, width: 22, height: 22), type: .fullscreenButtonType)
		fs.image = imgFSActive
		fs.autoresizingMask = [.minXMargin, .maxYMargin]
		fsButton = fs

		closeButton = MPXWindowButton(frame: NSRect(x: 4, y: 0, width: 22, height: 22), type: .closeButtonType)
		miniButton = MPXWindowButton(frame: NSRect(x: 25, y: 0, width: 22, height: 22), type: .minimizeButtonType)
		zoomButton = MPXWindowButton(frame: NSRect(x: 46, y: 0, width: 22, height: 22), type: .zoomButtonType)

		closeButton.image = imgCloseActive
		miniButton.image = imgMiniActive
		zoomButton.image = imgZoomActive
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override func awakeFromNib() {
		super.awakeFromNib()

		addSubview(closeButton)
		addSubview(miniButton)
		addSubview(zoomButton)

		closeButton.target = window
		miniButton.target = window
		zoomButton.target = window

		closeButton.action = #selector(NSWindow.performClose(_:))
		miniButton.action = #selector(NSWindow.performMiniaturize(_:))
		zoomButton.action = #selector(NSWindow.performZoom(_:))

		if let fsButton {
			addSubview(fsButton)
			fsButton.target = window
			fsButton.action = #selector(NSWindow.toggleFullScreen(_:))

			var rc = fsButton.bounds
			rc.origin.x = bounds.size.width - 22
			fsButton.frame = rc
		}

		NotificationCenter.default.addObserver(self,
											   selector: #selector(windowDidBecomKey(_:)),
											   name: NSWindow.didBecomeKeyNotification,
											   object: window)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(windowDidResignKey(_:)),
											   name: NSWindow.didResignKeyNotification,
											   object: window)
	}

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override var acceptsFirstResponder: Bool { true }

	override func mouseUp(with event: NSEvent) {
		if event.clickCount == 2 {
			if UserDefaults.standard.bool(forKey: "AppleMiniaturizeOnDoubleClick") {
				window?.performMiniaturize(self)
			}
		}
	}

	override func mouseMoved(with event: NSEvent) {
		let pt = convert(event.locationInWindow, from: nil)

		var mouseIn = NSPointInRect(pt, trackRect)

		if mouseIn != mouseEntered {
			// state changed
			mouseEntered = mouseIn

			if mouseEntered {
				// entered
				closeButton.image = imgCloseRollover
				miniButton.image = imgMiniRollover
				zoomButton.image = imgZoomRollover
			} else {
				// exited
				if window?.isKeyWindow ?? false {
					closeButton.image = imgCloseActive
					miniButton.image = imgMiniActive
					zoomButton.image = imgZoomActive
				} else {
					closeButton.image = imgCloseInactive
					miniButton.image = imgMiniInactive
					zoomButton.image = imgZoomInactive
				}
			}
		}

		if let fsButton {
			mouseIn = NSPointInRect(pt, fsButton.frame)
			if mouseIn != fsBtnEntered {
				fsBtnEntered = mouseIn
				fsButton.image = fsBtnEntered ? imgFSRollver : imgFSActive
			}
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		let leftSize = tbCornerLeft.size
		let rightSize = tbCornerRight.size
		let titleSize = bounds.size

		var srcRect = NSRect.zero

		srcRect.size = leftSize
		tbCornerLeft.draw(at: .zero, from: srcRect, operation: .copy, fraction: 1.0)

		srcRect.size = rightSize
		tbCornerRight.draw(at: NSPoint(x: titleSize.width - rightSize.width, y: 0),
						   from: srcRect, operation: .copy, fraction: 1.0)

		srcRect.size = tbMiddle.size
		tbMiddle.draw(in: NSRect(x: leftSize.width, y: 0,
								 width: titleSize.width - leftSize.width - rightSize.width,
								 height: titleSize.height),
					  from: srcRect, operation: .copy, fraction: 1.0)

		guard let title else { return }

		// AppKit's -sizeWithAttributes:/-drawAtPoint:withAttributes: have been observed
		// (crash reports on macOS 26) to throw an internal NSException from
		// -[NSDictionary objectsForKeys:notFoundMarker:] for reasons that don't reproduce
		// under a debugger. Since the title text is cosmetic, skip drawing it for this
		// frame rather than take the whole app down with it. Swift cannot catch an
		// NSException, hence the trip through MPXCatchingNSException.
		let renderStr = NSMutableString(string: title)
		let attr = titleAttr

		MPXCatchingNSException({
			let dotSize = kStringDots.size(withAttributes: attr)
			var strSize = (renderStr as String).size(withAttributes: attr)
			// The 80pt subtracted here is the chrome budget on either side of the
			// title, but the window can end up narrower than that (a resize gone
			// wrong will do it), which makes widthMax negative -- and then no
			// amount of trimming ever satisfies the loop below. The original code
			// assumed "a title of fewer than 3 characters is never wider than
			// widthMax" and deleted characters without checking the length, which
			// walks off the end of the string and throws
			// -[__NSCFString deleteCharactersInRange:]: Range or index out of
			// bounds. Clamp the budget and check the length on every deletion.
			let widthMax = max(0, titleSize.width - 80)

			if strSize.width > widthMax {
				if renderStr.length > 2 {
					renderStr.deleteCharacters(in: NSRange(location: 0, length: 2))
					strSize = (renderStr as String).size(withAttributes: attr)
				}

				while renderStr.length > 0 && (dotSize.width + strSize.width > widthMax) {
					renderStr.deleteCharacters(in: NSRange(location: 0, length: 1))
					strSize = (renderStr as String).size(withAttributes: attr)
				}
				renderStr.insert(kStringDots, at: 0)
			}

			let drawnSize = (renderStr as String).size(withAttributes: attr)

			let drawPos = NSPoint(x: max(70, (titleSize.width - drawnSize.width) / 2),
								  y: (titleSize.height - drawnSize.height) / 2)

			(renderStr as String).draw(at: drawPos, withAttributes: attr)
		}, { exception in
			MPLogString("TitleView drawRect: title text drawing threw \(exception.name.rawValue): \(exception.reason ?? "")")
		})
	}

	@objc private func windowDidBecomKey(_ notif: Notification) {
		closeButton.image = imgCloseActive
		miniButton.image = imgMiniActive
		zoomButton.image = imgZoomActive
	}

	@objc private func windowDidResignKey(_ notif: Notification) {
		closeButton.image = imgCloseInactive
		miniButton.image = imgMiniInactive
		zoomButton.image = imgZoomInactive
	}
}
