/*
 * MPlayerX - RootLayerView.swift
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

private let kOnTopModeNormal = 0
private let kOnTopModeAlways = 1
private let kOnTopModePlaying = 2

private let kScaleFrameRatioMinLimit: CGFloat = 0.05
private let kScaleFrameRatioStepMax: CGFloat = 0.20

private let kThreeFingersTapInit = 0
private let kThreeFingersTapInvalid = -1
private let kThreeFingersTapReady = 1

private let kThreeFingersPinchInit = 0
private let kThreeFingersPinchInvalid = -1
private let kThreeFingersPinchReady = 1

private let kFourFingersPinchInit = 0
private let kFourFingersPinchInvalid = -1
private let kFourFingersPinchReady = 1

// calculateFrame(from:toFit:mode:)
private struct CalFrameMode: OptionSet {
	let rawValue: UInt

	static let sizeDiag = CalFrameMode(rawValue: 1)
	static let sizeInFit = CalFrameMode(rawValue: 2)
	static let sizeMask = CalFrameMode(rawValue: 0xFF)

	static let fixPosCenter = CalFrameMode(rawValue: 1 << 8)
	static let fixPosUpleft = CalFrameMode(rawValue: 2 << 8)
	static let fixPosMask = CalFrameMode(rawValue: 0xFF00)
}

private let kFullScreenStatusNone = 0
private let kFullScreenStatusLion = 1
private let kFullScreenStatusOld = 2

/// The drag payload is still the legacy filenames array; spelled out here
/// rather than using the deprecated NSFilenamesPboardType symbol.
private let kFilenamesPboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

private func doesPrimaryScreenHasScreenAbove() -> Bool {
	let screens = NSScreen.screens
	guard let first = screens.first else { return false }

	// get the coordination of the Primary Screen
	let frm = first.frame

	// from the second screen
	for scrn in screens.dropFirst() {
		let curFrm = scrn.frame

		if (curFrm.origin.y - frm.origin.y) >= (frm.size.height - 1) {
			return true
		}
	}
	return false
}

private func DistanceOf(_ p1: NSPoint, _ p2: NSPoint, _ p3: NSPoint) -> CGFloat {
	abs(p1.x - p2.x) + abs(p1.y - p2.y) +
	abs(p1.x - p3.x) + abs(p1.y - p3.y) +
	abs(p2.x - p3.x) + abs(p2.y - p3.y)
}

private func AreaOf(_ p1: NSPoint, _ p2: NSPoint, _ p3: NSPoint, _ p4: NSPoint) -> CGFloat {
	var top = p1.y
	var bottom = p1.y
	var left = p1.x
	var right = p1.x

	for p in [p2, p3, p4] {
		if left > p.x { left = p.x }
		if right < p.x { right = p.x }
		if top < p.y { top = p.y }
		if bottom > p.y { bottom = p.y }
	}

	return abs(top - bottom) * abs(right - left)
}

@objc(RootLayerView)
class RootLayerView: NSView, CoreDisplayDelegate, CALayerDelegate, NSWindowDelegate {

	private let ud = UserDefaults.standard
	private let notifCenter = NotificationCenter.default

	private var trackingArea: NSTrackingArea!
	private var logo: NSBitmapImageRep?

	private var shouldResize = false
	private var rcBeforeFullScrn = NSRect.zero

	private var dispLayer: DisplayLayer!

	private var displaying = false
	private var fullScreenOptions: [NSView.FullScreenModeOptionKey: Any] = [:]
	private var fullScreenStatus = kFullScreenStatusNone

	private var lockAspectRatioValue = true
	private var frameAspectRatio = kDisplayAspectRatioInvalid

	private var dragMousePos = NSPoint.zero
	private var dragShouldResize = false

	private var firstDisplay = true
	private var playbackFinalized = true

	private var canMoveAcrossMenuBar = false

	private var threeFingersTap = kThreeFingersTapInit
	private var threeFingersPinch = kThreeFingersPinchInit
	private var threeFingersPinchDistance: CGFloat = 1
	private var fourFingersPinch = kFourFingersPinchInit
	private var fourFingersPinchDistance: CGFloat = 1

	// when toggling full screen, the view's window will change, so a member variable is used here to lock the window
	@IBOutlet weak var playerWindow: PlayerWindow!
	@IBOutlet weak var controlUI: ControlUIView!
	@IBOutlet weak var playerController: PlayerController!
	@IBOutlet weak var shortCutManager: ShortCutManager!
	@IBOutlet weak var VTController: VideoTunerController!
	@IBOutlet weak var titlebar: TitleView!

	/// The ObjC original's synthesized getter read the ivar directly, while the
	/// setter was hand-written; keeping them as two declarations preserves that
	/// exactly (several places inside the class assign the ivar on purpose,
	/// bypassing the setter's side effects).
	@objc var lockAspectRatio: Bool { lockAspectRatioValue }

	// MARK: Init/Dealloc

	/// Replaces the ObjC +initialize.
	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [
			kUDKeyOnTopMode: kOnTopModePlaying,
			kUDKeyStartByFullScreen: false,
			kUDKeyFullScreenKeepOther: true,
			kUDKeyQuitOnClose: false,
			kUDKeyPinPMode: false,
			kUDKeyAlwaysHideDockInFullScrn: false,
			kUDKeyDisableHScrollSeek: true,
			kUDKeyDisableVScrollVol: false,
			kUDKeyThreeFingersPinchThreshRatio: Float(1.5),
			kUDKeyFourFingersPinchThreshRatio: Float(1.8),
			kUDKeyCloseWndOnEsc: false,
			kUDKeyDontResizeWhenContinuousPlay: true,
			kUDKeyInitialFrameSizeRatio: Float(1.0),
			kUDKeyOldFullScreenMethod: false,
			kUDKeyAlwaysUseSecondaryScreen: false,
		])
	}()

	required init?(coder: NSCoder) {
		_ = RootLayerView.registerDefaultsOnce

		super.init(coder: coder)

		trackingArea = NSTrackingArea(rect: NSInsetRect(frame, 1, 1),
									  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
									  owner: self,
									  userInfo: nil)
		addTrackingArea(trackingArea)
		shouldResize = false
		rcBeforeFullScrn = window?.frame ?? .zero

		dispLayer = DisplayLayer()
		displaying = false
		fullScreenOptions = [
			.fullScreenModeApplicationPresentationOptions:
				NSNumber(value: NSApplication.PresentationOptions([.autoHideDock, .autoHideMenuBar]).rawValue),
			.fullScreenModeAllScreens: NSNumber(value: !ud.bool(forKey: kUDKeyFullScreenKeepOther)),
			.fullScreenModeWindowLevel: NSNumber(value: NSWindow.Level.tornOffMenu.rawValue),
		]
		fullScreenStatus = kFullScreenStatusNone
		lockAspectRatioValue = true
		frameAspectRatio = kDisplayAspectRatioInvalid
		dragShouldResize = false
		firstDisplay = true
		playbackFinalized = true
		canMoveAcrossMenuBar = doesPrimaryScreenHasScreenAbove()

		threeFingersTap = kThreeFingersTapInit
		threeFingersPinch = kThreeFingersPinchInit
		threeFingersPinchDistance = 1
		fourFingersPinch = kFourFingersPinchInit
		fourFingersPinchDistance = 1

		acceptsTouchEvents = true
		wantsRestingTouches = false
	}

	deinit {
		notifCenter.removeObserver(self)
		removeTrackingArea(trackingArea)
	}

	private func setupLayers() {
		// set up the LayerHost; currently it only hosts one Layer
		wantsLayer = true

		// get the basic rootLayer
		guard let root = layer else { return }

		CATransaction.begin()
		CATransaction.setDisableActions(true)

		root.removeAllAnimations()
		// disable the resize action
		root.delegate = self
		root.isDoubleSided = false

		// background color
		root.backgroundColor = CGColor(gray: 0.0, alpha: 1.0)

		// border color
		root.borderColor = CGColor(red: 0.392, green: 0.643, blue: 0.812, alpha: 0.75)

		// auto-resizing
		root.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

		// icon setup
		if let logoURL = Bundle.main.resourceURL?.appendingPathComponent("logo.png"),
		   let logoImage = CIImage(contentsOf: logoURL) {
			logo = NSBitmapImageRep(ciImage: logoImage)
		}
		root.contentsGravity = .center
		root.contents = logo?.cgImage

		// add dispLayer by default
		root.insertSublayer(dispLayer, at: 0)

		// notify DispLayer
		dispLayer.bounds = root.bounds
		dispLayer.position = CGPoint(x: root.bounds.size.width / 2, y: root.bounds.size.height / 2)

		CATransaction.commit()
	}

	func action(for layer: CALayer, forKey event: String) -> CAAction? { NSNull() }

	private func reorderSubviews() {
		// put ControlUI on the top layer to prevent it being covered
		controlUI.removeFromSuperviewWithoutNeedingDisplay()
		addSubview(controlUI, positioned: .above, relativeTo: nil)

		titlebar.removeFromSuperviewWithoutNeedingDisplay()
		addSubview(titlebar, positioned: .above, relativeTo: nil)
	}

	override func awakeFromNib() {
		super.awakeFromNib()

		setupLayers()

		reorderSubviews()

		// notify dispView to accept mplayer render notifications
		_ = playerController.setDisplayDelegateForMPlayer(self)

		// set up to accept Drag Files
		registerForDraggedTypes([kFilenamesPboardType])

		VTController.setLayer(dispLayer)

		notifCenter.addObserver(self, selector: #selector(playBackOpened(_:)),
								name: NSNotification.Name.mpcPlayOpened, object: playerController)
		notifCenter.addObserver(self, selector: #selector(playBackStarted(_:)),
								name: NSNotification.Name.mpcPlayStarted, object: playerController)
		notifCenter.addObserver(self, selector: #selector(playBackStopped(_:)),
								name: NSNotification.Name.mpcPlayStopped, object: playerController)
		notifCenter.addObserver(self, selector: #selector(playeBackFinalized(_:)),
								name: NSNotification.Name.mpcPlayFinalized, object: playerController)

		notifCenter.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)),
								name: NSApplication.didBecomeActiveNotification, object: NSApp)
		notifCenter.addObserver(self, selector: #selector(applicationDidResignActive(_:)),
								name: NSApplication.didResignActiveNotification, object: NSApp)

		notifCenter.addObserver(self, selector: #selector(screenConfigurationChanged(_:)),
								name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
	}

	@objc private func screenConfigurationChanged(_ notif: Notification) {
		canMoveAcrossMenuBar = doesPrimaryScreenHasScreenAbove()
		MPLogString("canMoveAcrossMenuBar:\(canMoveAcrossMenuBar)")

		if MPXGetSysVersion() >= kMPXSysVersionLion,
		   fullScreenStatus == kFullScreenStatusOld,
		   NSScreen.screens.count == 1 {
			// if it is a Lion system but the old fullscreen method was used, that means there were multiple screens at the time
			// but now there is only one screen, meaning the user unplugged the video cable, so we need to exit fullscreen
			controlUI.toggleFullScreen(nil)
		}
	}

	// MARK: MPCNotification

	@objc private func playeBackFinalized(_ notif: Notification) {
		playbackFinalized = true

		let fsStatus = fullScreenStatus

		// if not continuing playback, or there is no next file to play, exit fullscreen
		// at this point the display state, displaying, is NO
		// so, if in fullscreen it will exit fullscreen; if not in fullscreen it will not enter fullscreen either
		controlUI.toggleFullScreen(nil)
		// and reset the fillScreen state
		controlUI.toggleFillScreen(nil)

		if ud.bool(forKey: kUDKeyCloseWindowWhenStopped) {
			// close cannot be used here, since using close would trigger the windowWillClose method
			if fsStatus != kFullScreenStatusLion {
				// if the Lion-style mode was used when exiting fullscreen
				// then we cannot orderOut now, because Lion-style fullscreen is asynchronous, so at this point it has not actually exited fullscreen yet
				// the actual window hiding is handled in the delegate function
				window?.orderOut(nil)
			}
		} else {
			// at this point, if we are exiting from fullscreen, the window will not be shown
			// we need to force-show the window
			window?.makeKeyAndOrderFront(nil)
		}

		// playback fully completed, so resetAspectRatio now
		setExternalAspectRatio(kDisplayAspectRatioInvalid)

		// playback fully ended, move the render area back to center
		moveFrameToCenter()
		resetFrameScaleRatio()
	}

	@objc private func playBackStopped(_ notif: Notification) {
		firstDisplay = true
		playbackFinalized = false
		setPlayerWindowLevel()
		playerWindow.title = kMPCStringMPlayerX
		layer?.contents = logo?.cgImage
	}

	@objc private func playBackStarted(_ notif: Notification) {
		setPlayerWindowLevel()

		if (notif.userInfo?[kMPCPlayStartedAudioOnlyKey] as? NSNumber)?.boolValue ?? false {
			// if audio only
			layer?.contents = logo?.cgImage
			playerWindow.setContentSize(playerWindow.contentMinSize)
			if !NSApp.isHidden {
				playerWindow.makeKeyAndOrderFront(nil)
			}
		} else {
			// if has video
			layer?.contents = nil
		}
	}

	@objc private func playBackOpened(_ notif: Notification) {
		if let url = notif.userInfo?[kMPCPlayOpenedURLKey] as? URL {
			if url.isFileURL {
				playerWindow.title = ((url.path as NSString).lastPathComponent as NSString).deletingPathExtension
			} else {
				playerWindow.title = (url.absoluteString as NSString).lastPathComponent
			}
		} else {
			playerWindow.title = kMPCStringMPlayerX
		}
	}

	// MARK: keyboard/mouse

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
	override var acceptsFirstResponder: Bool { true }

	override func mouseMoved(with event: NSEvent) {
		if NSPointInRect(convert(event.locationInWindow, from: nil), bounds) {
			controlUI.showUp()
			controlUI.updateHintTime()
		}
		titlebar.mouseMoved(with: event)
	}

	override func mouseDown(with event: NSEvent) {
		dragMousePos = NSEvent.mouseLocation
		let winRC = playerWindow.frame

		dragShouldResize = (NSMaxX(winRC) - dragMousePos.x < 16) && (dragMousePos.y - NSMinY(winRC) < 16)
	}

	override func mouseDragged(with event: NSEvent) {
		// current location of the mouse
		let posNow = NSEvent.mouseLocation
		var delta = NSPoint(x: posNow.x - dragMousePos.x, y: posNow.y - dragMousePos.y)

		dragMousePos = posNow

		// The original switched on the masked flags and fell through from
		// shift+alt into the plain alt case; spelled out as a condition here.
		let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])

		if flags == [.shift, .option] || flags == kSCMDragFullScrFrameModifierFlagMask {
			let shiftKeyPressed = (flags == [.shift, .option])

			if isInFullScreenMode {
				// in fullscreen, move the render area
				var pt = dispLayer.positionOffsetRatio
				let sz = dispLayer.bounds.size

				if shiftKeyPressed {
					if abs(delta.x) > abs(8 * delta.y) {
						delta.y = 0
					} else if abs(8 * delta.x) < abs(delta.y) {
						delta.x = 0
					} else {
						// if use shift to drag the area, only X or only Y are accepted
						return
					}
				}

				pt.x += (delta.x / sz.width)
				pt.y += (delta.y / sz.height)

				dispLayer.setPositoinOffsetRatio(pt)
				dispLayer.display()
			}
		} else if flags.isEmpty {
			if !isInFullScreenMode {
				// move the window when not in fullscreen

				if dragShouldResize {
					var newFrame = playerWindow.frame

					// new frame formed by the current mouse position and the window
					newFrame.size.width = posNow.x - newFrame.origin.x
					newFrame.size.height = newFrame.size.height + newFrame.origin.y - posNow.y
					newFrame.origin.y = posNow.y

					let ar: CGFloat
					if displaying && lockAspectRatioValue {
						// there is video displaying
						// get the new window size
						ar = dispLayer.aspectRatio
					} else {
						ar = newFrame.size.width / newFrame.size.height
					}
					newFrame = calculateFrame(from: newFrame, toFit: ar, mode: [.sizeInFit, .fixPosUpleft])
					playerWindow.setFrame(newFrame, display: true, animate: false)
				} else {
					var winFrm = playerWindow.frame
					let currentScrn = window?.screen

					winFrm.origin.x += delta.x
					winFrm.origin.y += delta.y

					if currentScrn === NSScreen.screens.first, !canMoveAcrossMenuBar {
						// if the current screen has a menubar, do not let the window go past the menubar
						let scrnFrm = currentScrn?.visibleFrame ?? .zero

						if (winFrm.origin.y + winFrm.size.height) > (scrnFrm.origin.y + scrnFrm.size.height) {
							winFrm.origin.y = scrnFrm.origin.y + scrnFrm.size.height - winFrm.size.height
						}
					}

					playerWindow.setFrameOrigin(winFrm.origin)
				}
			}
		}
	}

	override func mouseUp(with event: NSEvent) {
		if event.clickCount == 2 {
			if event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty {
				controlUI.toggleFullScreen(nil)
			}
		}
		// do not use the playerWindow, since when fullscreen the window holds self is not playerWindow
		// when the mouse is released, automatically set FR to rootLayerView, so it can receive keyboard/mouse events
		window?.makeFirstResponder(self)
	}

	override func mouseEntered(with event: NSEvent) {
		controlUI.showUp()
	}

	override func mouseExited(with event: NSEvent) {
		if !isInFullScreenMode {
			// in fullscreen mode, be less aggressive about this
			controlUI.doHide()
		}
	}

	override func keyDown(with event: NSEvent) {
		if !shortCutManager.processKeyDown(event) {
			// if the shortcut manager does not handle this event, follow the default flow
			super.keyDown(with: event)
		}
	}

	override func cancelOperation(_ sender: Any?) {
		if isInFullScreenMode {
			// when pressing Escape, exit fullscreen if being fullscreen
			controlUI.toggleFullScreen(nil)
		} else {
			if ud.bool(forKey: kUDKeyCloseWndOnEsc) {
				window?.performClose(nil)
			}
		}
	}

	override func scrollWheel(with event: NSEvent) {
		var x = event.deltaX
		var y = event.deltaY

		if event.responds(to: #selector(getter: NSEvent.isDirectionInvertedFromDevice)) {
			MPLogString("scrolling in Lion")
			if event.isDirectionInvertedFromDevice {
				x = -x
				y = -y
			}
		}

		let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])

		if flags == kSCMScaleFrameKeyEquivalentModifierFlagMask {
			if isInFullScreenMode {
				// only in full screen mode
				// in Y direction
				let h = y / 100.0
				changeFrameScaleRatio(by: CGSize(width: h, height: h))
			}
		} else if flags.isEmpty {
			if abs(x) > abs(y * 8), !ud.bool(forKey: kUDKeyDisableHScrollSeek) {
				switch playerController.playerState() {
				case Int32(kMPCPausedState):
					if x < 0 {
						playerController.frameStep()
					}
				case Int32(kMPCPlayingState):
					controlUI.changeTime(by: Float(-x))
				default:
					break
				}
			} else if abs(x * 8) < abs(y), !ud.bool(forKey: kUDKeyDisableVScrollVol) {
				controlUI.changeVolumeBy(NSNumber(value: Float(y * 0.2)))
			}
		}
	}

	override func magnify(with event: NSEvent) {
		if isInFullScreenMode {
			// in full screen
			let h = event.magnification / 2
			changeFrameScaleRatio(by: CGSize(width: h, height: h))
		} else {
			changeWindowSize(by: NSSize(width: event.magnification, height: event.magnification), animate: false)
		}
	}

	override func swipe(with event: NSEvent) {
		let x = event.deltaX
		let y = event.deltaY
		var key: unichar = 0

		if x < 0 {
			key = unichar(NSRightArrowFunctionKey)
		} else if x > 0 {
			key = unichar(NSLeftArrowFunctionKey)
		} else if y > 0 {
			key = unichar(NSUpArrowFunctionKey)
		} else if y < 0 {
			key = unichar(NSDownArrowFunctionKey)
		}

		if key != 0 {
			var k = key
			let str = String(utf16CodeUnits: &k, count: 1)
			if let ev = NSEvent.makeKeyDownEvent(str, modifierFlags: 0) {
				_ = shortCutManager.processKeyDown(ev)
			}
		}
	}

	override func rotate(with event: NSEvent) {
		if !lockAspectRatioValue || NSEvent.modifierFlags.contains(.option) {
			// if not locked, or if alt is pressed while locked
			var angle = atan(1 / dispLayer.aspectRatio)

			if event.modifierFlags.contains(.shift) {
				angle += CGFloat(event.rotation) * 3.1415926 / 720
			} else {
				angle += CGFloat(event.rotation) * 3.1415926 / 180
			}
			angle = min(0.785 /* 45 degree */, max(0.17 /* 10 degree */, angle))
			setAspectRatio(1 / tan(angle))
		}
	}

	// MARK: multitouch

	override func touchesBegan(with event: NSEvent) {
		let touch = event.touches(matching: .touching, in: self)

		switch touch.count {
		case 3:
			if threeFingersTap == kThreeFingersTapInit {
				// if it is a three-finger tap, and the state is currently OK, then it is ready
				threeFingersTap = kThreeFingersTapReady
			}

			if threeFingersPinch == kThreeFingersPinchInit {
				threeFingersPinch = kThreeFingersPinchReady
				let touchAr = Array(touch)
				threeFingersPinchDistance = DistanceOf(touchAr[0].normalizedPosition,
													   touchAr[1].normalizedPosition,
													   touchAr[2].normalizedPosition)
				MPLogString("Init 3f Dist:\(threeFingersPinchDistance)")
			}
		case 4:
			threeFingersTap = kThreeFingersTapInit
			threeFingersPinch = kThreeFingersPinchInit

			if fourFingersPinch == kFourFingersPinchInit {
				fourFingersPinch = kFourFingersPinchReady
				let touchAr = Array(touch)
				fourFingersPinchDistance = AreaOf(touchAr[0].normalizedPosition,
												  touchAr[1].normalizedPosition,
												  touchAr[2].normalizedPosition,
												  touchAr[3].normalizedPosition)
				MPLogString("Init 4f Dist:\(fourFingersPinchDistance)")
			}
		default:
			break
		}
		super.touchesBegan(with: event)
	}

	override func touchesMoved(with event: NSEvent) {
		// whenever a move happens, it is no longer ready
		threeFingersTap = kThreeFingersTapInvalid

		if threeFingersPinch == kThreeFingersPinchReady {
			let touch = event.touches(matching: [.moved, .stationary], in: self)

			if touch.count == 3 {
				let touchAr = Array(touch)
				let dist = DistanceOf(touchAr[0].normalizedPosition,
									  touchAr[1].normalizedPosition,
									  touchAr[2].normalizedPosition)
				let thresh = CGFloat(ud.float(forKey: kUDKeyThreeFingersPinchThreshRatio))

				MPLogString("Curr 3f Dist:\(dist / threeFingersPinchDistance)")
				if (!isInFullScreenMode && (dist > threeFingersPinchDistance * thresh)) ||
					(isInFullScreenMode && (dist * thresh < threeFingersPinchDistance)) {
					// toggle fullscreen
					threeFingersPinch = kThreeFingersPinchInit
					controlUI.toggleFullScreen(nil)
				}
			}
		}

		if fourFingersPinch == kFourFingersPinchReady {
			let touch = event.touches(matching: [.moved, .stationary], in: self)

			if touch.count == 4 {
				let touchAr = Array(touch)
				let dist = AreaOf(touchAr[0].normalizedPosition,
								  touchAr[1].normalizedPosition,
								  touchAr[2].normalizedPosition,
								  touchAr[3].normalizedPosition)
				MPLogString("Curr 4f Dist:\(dist / fourFingersPinchDistance)")

				if dist * CGFloat(ud.float(forKey: kUDKeyFourFingersPinchThreshRatio)) < fourFingersPinchDistance {
					fourFingersPinch = kFourFingersPinchInit
					window?.performClose(self)
				}
			}
		}
		super.touchesMoved(with: event)
	}

	override func touchesEnded(with event: NSEvent) {
		let touch = event.touches(matching: .touching, in: self)

		if touch.isEmpty {
			// once all fingers have left (except resting ones)
			if threeFingersTap == kThreeFingersTapReady {
				// if it is ready, toggle play pause
				controlUI.togglePlayPause(nil)
			}
			// regardless of whether it is ready, init, or invalid, reset everything once all fingers have left
			threeFingersTap = kThreeFingersTapInit

			threeFingersPinch = kThreeFingersPinchInit
			fourFingersPinch = kFourFingersPinchInit
		}

		super.touchesEnded(with: event)
	}

	override func touchesCancelled(with event: NSEvent) {
		threeFingersTap = kThreeFingersTapInit
		threeFingersPinch = kThreeFingersPinchInit
		fourFingersPinch = kFourFingersPinchInit

		super.touchesCancelled(with: event)
	}

	// MARK: internal

	@objc func resetFrameScaleRatio() {
		dispLayer.scaleRatio = CGSize(width: 1, height: 1)
		dispLayer.display()
	}

	@objc(changeFrameScaleRatioBy:)
	func changeFrameScaleRatio(by rt: CGSize) {
		var rt = rt
		var ratio = dispLayer.scaleRatio

		if abs(rt.width) > kScaleFrameRatioStepMax {
			rt.width = (rt.width > 0) ? kScaleFrameRatioStepMax : -kScaleFrameRatioStepMax
		}
		if abs(rt.height) > kScaleFrameRatioStepMax {
			rt.height = (rt.height > 0) ? kScaleFrameRatioStepMax : -kScaleFrameRatioStepMax
		}

		ratio.width += rt.width
		ratio.height += rt.height

		if ratio.width < kScaleFrameRatioMinLimit {
			ratio.width = kScaleFrameRatioMinLimit
		}
		if ratio.height < kScaleFrameRatioMinLimit {
			ratio.height = kScaleFrameRatioMinLimit
		}

		dispLayer.scaleRatio = ratio
		dispLayer.display()
	}

	@objc func moveFrameToCenter() {
		dispLayer.setPositoinOffsetRatio(.zero)
		dispLayer.display()
	}

	private func findScreen(for frame: NSRect) -> NSScreen? {
		var areaMax: CGFloat = -1
		var ret: NSScreen?

		for scrn in NSScreen.screens {
			let inter = NSIntersectionRect(scrn.frame, frame)
			if (inter.size.width * inter.size.height) > areaMax {
				ret = scrn
				areaMax = inter.size.width * inter.size.height
			}
		}
		return ret
	}

	private func calculateFrame(from originalFrame: NSRect, toFit aspect: CGFloat, mode modeMask: CalFrameMode) -> NSRect {
		var orgFrame = originalFrame
		var ar = aspect

		let contentRect = playerWindow.contentRect(forFrameRect: orgFrame)
		let contentMinSize = playerWindow.contentMinSize

		let screenRc = findScreen(for: orgFrame)?.visibleFrame ?? .zero
		let screenContentSize = playerWindow.contentRect(forFrameRect: screenRc).size

		if (orgFrame.size.width <= 0) || (orgFrame.size.height <= 0) {
			// invalid size, so use the window's current size
			orgFrame = playerWindow.contentRect(forFrameRect: playerWindow.frame)
		} else {
			orgFrame = contentRect
		} // from here on, orgFrame is reused as the new content rect, to save stack

		if !IsDisplayLayerAspectValid(ar) {
			// if there is no target AR, then use the movie's original AR
			// note: not the movie's current AR -- when this API is called, the movie should already be in its current AR
			ar = dispLayer.originalAspectRatio
		}
		if !IsDisplayLayerAspectValid(ar) {
			ar = orgFrame.size.width / orgFrame.size.height
		}

		// we should really check whether ar > 0, but worst case it will just use orgFrame's current ar, so no check is needed

		// compute the transformed contentSize
		if modeMask.intersection(.sizeMask) == .sizeInFit {
			// compute based on the containment relationship
			if orgFrame.size.width > (orgFrame.size.height * ar) {
				// becoming a portrait image
				orgFrame.size.width = orgFrame.size.height * ar
			} else {
				// becoming a landscape image
				orgFrame.size.height = orgFrame.size.width / ar
			}
		} else {
			// compute based on the diagonal
			let diagLen = hypot(orgFrame.size.width, orgFrame.size.height)
			let angle = atan(1 / ar)

			orgFrame.size.width = diagLen * cos(angle)
			orgFrame.size.height = diagLen * sin(angle)
		}

		// the max size needs both dimensions guaranteed, while the min size only needs one dimension guaranteed
		if screenContentSize.width > (screenContentSize.height * ar) {
			// becoming a portrait image, height overflows first, then width
			if orgFrame.size.height > screenContentSize.height {
				orgFrame.size.height = screenContentSize.height
				orgFrame.size.width = orgFrame.size.height * ar
			}
		} else {
			// becoming a landscape image, width overflows first, then height
			if orgFrame.size.width > screenContentSize.width {
				orgFrame.size.width = screenContentSize.width
				orgFrame.size.height = orgFrame.size.width / ar
			}
		}

		if contentMinSize.width > (contentMinSize.height * ar) {
			// becoming a portrait image, width overflows first, then height
			if orgFrame.size.height < contentMinSize.height {
				orgFrame.size.height = contentMinSize.height
				orgFrame.size.width = orgFrame.size.height * ar
			}
		} else {
			// becoming a landscape image, height overflows first, then width
			if orgFrame.size.width < contentMinSize.width {
				// prioritize width
				orgFrame.size.width = contentMinSize.width
				orgFrame.size.height = orgFrame.size.width / ar
			}
		}
		// at this point we have the needed contentSize, stored in orgFrame.size

		// compute the new origin
		if modeMask.intersection(.fixPosMask) == .fixPosUpleft {
			// align to the upper-left corner
			orgFrame.origin.y = contentRect.origin.y + contentRect.size.height - orgFrame.size.height
		} else {
			// align to center
			orgFrame.origin.x += (contentRect.size.width - orgFrame.size.width) / 2
			orgFrame.origin.y += (contentRect.size.height - orgFrame.size.height) / 2
			orgFrame.origin.x = max(screenRc.origin.x, min(orgFrame.origin.x, screenRc.origin.x + screenRc.size.width - orgFrame.size.width))
			orgFrame.origin.y = max(screenRc.origin.y, min(orgFrame.origin.y, screenRc.origin.y + screenRc.size.height - orgFrame.size.height))
		}
		// from here on, orgFrame represents the latest content size and window origin

		// Apple's docs say ContentRect here uses Screen Coordinate
		// needs verification
		return playerWindow.frameRect(forContentRect: orgFrame)
	}

	private func setExternalAspectRatio(_ ar: CGFloat) {
		if IsDisplayLayerAspectValid(ar) {
			// if it is a valid value, that means it is an external AR, and the picture's AR needs to be computed from the external AR
			let lbMode = ud.integer(forKey: kUDKeyLetterBoxMode)
			let margin = CGFloat(ud.float(forKey: kUDKeyLetterBoxHeight))

			switch lbMode {
			case Int(kPMLetterBoxModeBoth):
				frameAspectRatio = ar * (1 + 2 * margin)
			case Int(kPMLetterBoxModeBottomOnly), Int(kPMLetterBoxModeTopOnly):
				frameAspectRatio = ar * (1 + margin)
			default:
				frameAspectRatio = ar
			}
		} else {
			frameAspectRatio = kDisplayAspectRatioInvalid
		}
		dispLayer.externalAspectRatio = ar
	}

	@objc(setLockAspectRatio:)
	func setLockAspectRatio(_ lock: Bool) {
		guard lock != lockAspectRatioValue else { return }

		lockAspectRatioValue = lock

		if lockAspectRatioValue {
			// if locking the aspect ratio, then go by the current window's
			// if in fullscreen, [self bounds] becomes the fullscreen size, which needs correcting
			var sz = bounds.size
			let ar = dispLayer.aspectRatio

			sz.width = sz.height * ar

			if IsDisplayLayerAspectValid(ar) {
				playerWindow.contentAspectRatio = sz
				setExternalAspectRatio(ar)
			}
		} else {
			playerWindow.contentResizeIncrements = NSSize(width: 1.0, height: 1.0)
		}
	}

	@objc func resetAspectRatio() {
		if displaying {
			lockAspectRatioValue = true
			setAspectRatio(kDisplayAspectRatioInvalid)
		}
	}

	@objc(setAspectRatio:)
	func setAspectRatio(_ aspect: CGFloat) {
		// if ar==kDisplayAspectRatioInvalid, that means it is a reset
		// the calculateFrame function will compute based on originalAspectRatio
		guard displaying else { return }

		var ar = aspect
		let newFrame: NSRect

		if IsDisplayLayerAspectValid(ar) {
			// valid means it is not a reset
			// if there is currently a letterbox, that would be a problem
			// needs compensating
			let lbMode = ud.integer(forKey: kUDKeyLetterBoxMode)
			let margin = CGFloat(ud.float(forKey: kUDKeyLetterBoxHeight))

			switch lbMode {
			case Int(kPMLetterBoxModeBoth):
				ar /= (1 + 2 * margin)
			case Int(kPMLetterBoxModeBottomOnly), Int(kPMLetterBoxModeTopOnly):
				ar /= (1 + margin)
			default:
				break
			}
		}

		if isInFullScreenMode {
			setExternalAspectRatio(ar)
			updateFrameForFullScreen()
			newFrame = rcBeforeFullScrn
		} else {
			newFrame = calculateFrame(from: window?.frame ?? .zero, toFit: ar, mode: [.fixPosCenter, .sizeDiag])
			playerWindow.setFrame(newFrame, display: true, animate: true)
			setExternalAspectRatio(ar)
		}

		if lockAspectRatioValue {
			// if AR is locked, then the ratio needs to be reset
			playerWindow.contentAspectRatio = playerWindow.contentRect(forFrameRect: newFrame).size

			dispLayer.display()
		} else {
			// if AR is not locked, dispLayer's AR will change along with the window, so nothing needs to be done for now
		}
	}

	@objc func snapshot() -> CIImage? {
		dispLayer.snapshot
	}

	@objc var aspectRatio: CGFloat { dispLayer.aspectRatio }

	@objc(changeWindowSizeBy:animate:)
	func changeWindowSize(by delta: NSSize, animate: Bool) {
		guard !isInFullScreenMode else { return }

		var delta = delta
		var frm = playerWindow.frame

		// the new target size
		delta.width *= frm.size.width
		delta.height *= frm.size.height

		// target Rect
		frm.origin.x -= delta.width / 2
		frm.origin.y -= delta.height / 2
		frm.size.width += delta.width
		frm.size.height += delta.height

		frm = calculateFrame(from: frm, toFit: dispLayer.aspectRatio, mode: [.fixPosCenter, .sizeDiag])

		playerWindow.setFrame(frm, display: true, animate: animate)
	}

	override var isInFullScreenMode: Bool {
		fullScreenStatus != kFullScreenStatusNone
	}

	@objc func toggleFullScreen() -> Bool {
		var oldWay = false

		if fullScreenStatus == kFullScreenStatusNone {
			// if not in fullscreen state, decide based on the current situation
			oldWay = (MPXGetSysVersion() < kMPXSysVersionLion) ||
					 (NSScreen.screens.count > 1) ||
					 ud.bool(forKey: kUDKeyOldFullScreenMethod)
		} else {
			// currently in fullscreen state, about to exit fullscreen
			// so it needs to stay consistent with the state used when entering fullscreen
			oldWay = (fullScreenStatus == kFullScreenStatusOld)
		}

		if oldWay {
			// ! note: the display state here differs from mplayer's playback state -- e.g. when mplayer is playing an MP3, the playback state is YES but the display state is NO
			if isInFullScreenMode {
				// fullscreen can be exited regardless of whether it is currently displaying

				// this must only be set right when exiting fullscreen
				// before exiting fullscreen, this view does not belong to the window, so setting contentSize has no effect
				if shouldResize {
					shouldResize = false
					dispLayer.forceAdjustToFitBounds(true)
					if displaying {
						// first put playerWindow behind the fullscreen window
						playerWindow.order(.below, relativeTo: window?.windowNumber ?? 0)
						// exit fullscreen
						exitFullScreenMode(options: fullScreenOptions)
						// cancel the various fullscreen-time settings
						dispLayer.enablePositionOffset(false)
						dispLayer.enableScale(false)
						// if CloseWindowWhenStopped is selected
						// when playback finishes and exits fullscreen, the window will be shown here, then closed back over in ControlUIView
						// this causes the window to flash, so only actively show the window when actually displaying
						playerWindow.makeKeyAndOrderFront(self)
					} else {
						// if not displaying, the window will not be shown at all
						// exit fullscreen
						exitFullScreenMode(options: fullScreenOptions)
						dispLayer.enablePositionOffset(false)
						dispLayer.enableScale(false)
					}

					// if not displaying, then no animation is needed
					playerWindow.setFrame(rcBeforeFullScrn, display: true, animate: displaying)
					dispLayer.display()
					dispLayer.forceAdjustToFitBounds(false)

					// when entering fullscreen, ar was force-locked
					// when exiting fullscreen, after updating the window size, the window's ar needs to be set once more here
					playerWindow.contentAspectRatio = playerWindow.contentRect(forFrameRect: rcBeforeFullScrn).size
				} else {
					exitFullScreenMode(options: fullScreenOptions)

					// after exiting fullscreen, re-render the image according to the current size ratio
					dispLayer.enablePositionOffset(false)
					dispLayer.enableScale(false)
					dispLayer.display()

					if displaying {
						// if CloseWindowWhenStopped is selected
						// when playback finishes and exits fullscreen, the window will be shown here, then closed back over in ControlUIView
						// this causes the window to flash, so only actively show the window when actually displaying
						playerWindow.makeKeyAndOrderFront(self)
					}
				}
				playerWindow.makeFirstResponder(self)

				// window level can only be set after exiting fullscreen
				setPlayerWindowLevel()

				fullScreenStatus = kFullScreenStatusNone

			} else if displaying {
				// should enter fullscreen
				// fullscreen can only be entered while an image is being displayed

				// force Lock Aspect Ratio
				setLockAspectRatio(true)

				let keepOtherSrn = ud.bool(forKey: kUDKeyFullScreenKeepOther)

				let scrnList = NSScreen.screens
				let chosenScreen: NSScreen?
				if scrnList.count > 1, ud.bool(forKey: kUDKeyAlwaysUseSecondaryScreen) {
					// if there are multiple screens, and always-use-secondary-screen is selected
					chosenScreen = scrnList[1]
				} else {
					// get the screen the window is currently on
					chosenScreen = playerWindow.screen
				}

				// Presentation Options
				let opts: NSApplication.PresentationOptions

				if chosenScreen === scrnList.first || !keepOtherSrn {
					// if the main screen
					// there is no reason to always hide Dock, when MPX displayed in the secondary screen
					// so only do it in main screen
					if ud.bool(forKey: kUDKeyAlwaysHideDockInFullScrn) {
						opts = [.hideDock, .autoHideMenuBar]
					} else {
						opts = [.autoHideDock, .autoHideMenuBar]
					}
				} else {
					// in secondary screens
					opts = NSApp.presentationOptions
				}

				fullScreenOptions[.fullScreenModeApplicationPresentationOptions] = NSNumber(value: opts.rawValue)
				// whether grab all the screens
				fullScreenOptions[.fullScreenModeAllScreens] = NSNumber(value: !keepOtherSrn)

				shouldResize = true
				// first record the window's position before fullscreen
				rcBeforeFullScrn = playerWindow.frame
				// animate into fullscreen

				dispLayer.forceAdjustToFitBounds(true)
				playerWindow.setFrame(chosenScreen?.frame ?? .zero, display: true, animate: true)
				dispLayer.display()

				// enter fullscreen
				if let chosenScreen {
					_ = enterFullScreenMode(chosenScreen, withOptions: fullScreenOptions)
				}
				// exit fullscreen, re-render the image according to the current size ratio
				dispLayer.enablePositionOffset(true)
				dispLayer.enableScale(true)
				// so it displays correctly when paused
				dispLayer.display()
				dispLayer.forceAdjustToFitBounds(false)

				playerWindow.orderOut(self)

				window?.collectionBehavior = .managed

				// get the screen's resolution, and compare it with the image being played
				// to know whether it is landscape or portrait
				let sz = bounds.size

				controlUI.setFillScreenMode(((sz.height * dispLayer.aspectRatio) >= sz.width) ? kFillScreenButtonImageUBKey : kFillScreenButtonImageLRKey,
											state: dispLayer.fillScreen ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue)
				fullScreenStatus = kFullScreenStatusOld
			} else {
				// force a render once
				dispLayer.display()
				fullScreenStatus = kFullScreenStatusNone
				return false
			}
		} else {
			// when it is Lion and there is only one screen
			if isInFullScreenMode {
				// exit fullscreen
				if shouldResize {
					shouldResize = false
					// Lion-style fullscreen does not hide playerWindow
					// need to hide or show the window in the delegate function
					playerWindow.toggleFullScreenReal(self)
				} else {
					playerWindow.toggleFullScreenReal(self)
				}

				fullScreenStatus = kFullScreenStatusNone
			} else if displaying {
				// enter fullscreen
				// force Lock Aspect Ratio
				setLockAspectRatio(true)

				shouldResize = true
				// first record the window's position before fullscreen
				rcBeforeFullScrn = playerWindow.frame

				playerWindow.toggleFullScreenReal(self)

				fullScreenStatus = kFullScreenStatusLion
			} else {
				dispLayer.display()
				fullScreenStatus = kFullScreenStatusNone
				return false
			}
		}
		return true
	}

	func windowDidEnterFullScreen(_ notification: Notification) {
		window?.makeFirstResponder(self)

		let sz = bounds.size

		controlUI.setFillScreenMode(((sz.height * dispLayer.aspectRatio) >= sz.width) ? kFillScreenButtonImageUBKey : kFillScreenButtonImageLRKey,
									state: dispLayer.fillScreen ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue)
	}

	func windowDidExitFullScreen(_ notification: Notification) {
		if !displaying, ud.bool(forKey: kUDKeyCloseWindowWhenStopped) {
			window?.orderOut(self)
		}
		// when entering fullscreen, ar was force-locked
		// when exiting fullscreen, after updating the window size, the window's ar needs to be set once more here
		window?.contentAspectRatio = window?.contentRect(forFrameRect: rcBeforeFullScrn).size ?? .zero

		window?.makeFirstResponder(self)

		// window level can only be set after exiting fullscreen
		setPlayerWindowLevel()
	}

	func window(_ window: NSWindow, willUseFullScreenContentSize proposedSize: NSSize) -> NSSize {
		MPLogString("Prop Size:\(proposedSize.width), \(proposedSize.height)")
		return proposedSize
	}

	func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
		if ud.bool(forKey: kUDKeyAlwaysHideDockInFullScrn) {
			return [.fullScreen, .hideDock, .autoHideMenuBar]
		} else {
			return [.fullScreen, .autoHideDock, .autoHideMenuBar]
		}
	}

	func customWindowsToEnterFullScreen(for window: NSWindow) -> [NSWindow]? {
		if window === playerWindow {
			return [window]
		}
		return nil
	}

	func customWindowsToExitFullScreen(for window: NSWindow) -> [NSWindow]? {
		if window === playerWindow {
			return [window]
		}
		return nil
	}

	func window(_ window: NSWindow, startCustomAnimationToEnterFullScreenWithDuration duration: TimeInterval) {
		invalidateRestorableState()

		window.styleMask.insert(.fullScreen)

		let screenFrame = window.screen?.frame ?? .zero
		var proposedFrame = screenFrame

		proposedFrame.size = self.window(window, willUseFullScreenContentSize: proposedFrame.size)

		proposedFrame.origin.x += floor(0.5 * (NSWidth(screenFrame) - NSWidth(proposedFrame)))
		proposedFrame.origin.y += floor(0.5 * (NSHeight(screenFrame) - NSHeight(proposedFrame)))

		dispLayer.forceAdjustToFitBounds(true)
		dispLayer.enablePositionOffset(true)
		dispLayer.enableScale(true)

		NSAnimationContext.runAnimationGroup({ context in
			context.duration = 0.5 * duration
			window.animator().setFrame(proposedFrame, display: true)
		}, completionHandler: { [weak self] in
			guard let self else { return }
			self.dispLayer.display()
			self.dispLayer.forceAdjustToFitBounds(false)
		})
	}

	func window(_ window: NSWindow, startCustomAnimationToExitFullScreenWithDuration duration: TimeInterval) {
		window.styleMask.remove(.fullScreen)

		dispLayer.forceAdjustToFitBounds(true)
		dispLayer.enablePositionOffset(false)
		dispLayer.enableScale(false)

		NSAnimationContext.runAnimationGroup({ [weak self] context in
			guard let self else { return }
			context.duration = 0.5 * duration
			window.animator().setFrame(self.rcBeforeFullScrn, display: true, animate: self.displaying)
		}, completionHandler: { [weak self] in
			guard let self else { return }
			// so it displays correctly when paused
			self.dispLayer.display()
			self.dispLayer.forceAdjustToFitBounds(false)
		})
	}

	@objc func toggleFillScreen() -> Bool {
		dispLayer.fillScreen = !dispLayer.fillScreen
		// so it displays correctly when paused
		dispLayer.display()
		return dispLayer.fillScreen
	}

	@objc func setPlayerWindowLevel() {
		// in window mode
		let onTopMode = ud.integer(forKey: kUDKeyOnTopMode)
		let fullscr = isInFullScreenMode

		if (((onTopMode == kOnTopModeAlways) ||
			 ((onTopMode == kOnTopModePlaying) && (playerController.playerState() == Int32(kMPCPlayingState)))) && !fullscr) ||
			(NSApp.isActive && fullscr) {
			window?.level = .tornOffMenu
		} else {
			window?.level = .normal
		}
	}

	@objc var mirror: Bool { dispLayer.mirror }

	@objc var flip: Bool { dispLayer.flip }

	@objc(setMirror:)
	func setMirror(_ m: Bool) {
		dispLayer.mirror = m
		dispLayer.display()
	}

	@objc(setFlip:)
	func setFlip(_ f: Bool) {
		dispLayer.flip = f
		dispLayer.display()
	}

	@objc(zoomToSize:)
	func zoomToSize(_ ratio: Float) {
		guard displaying else { return }

		var orgSize = dispLayer.displaySize
		let ar = dispLayer.aspectRatio

		orgSize.width *= CGFloat(ratio)
		orgSize.height *= CGFloat(ratio)

		if isInFullScreenMode {
			let curSize = dispLayer.bounds.size
			var sr = dispLayer.scaleRatio

			orgSize.width = min(orgSize.width, orgSize.height * ar)

			let r = max(orgSize.width / curSize.width, orgSize.height / curSize.height)
			sr.width *= r
			sr.height *= r

			dispLayer.scaleRatio = sr
			dispLayer.display()
		} else {
			// not in full screen
			var rc = playerWindow.contentRect(forFrameRect: playerWindow.frame)
			rc.origin.x -= (orgSize.width - rc.size.width) / 2
			rc.origin.y -= (orgSize.height - rc.size.height) / 2
			rc.size = orgSize
			rc = calculateFrame(from: playerWindow.frameRect(forContentRect: rc), toFit: ar, mode: [.fixPosCenter, .sizeDiag])
			playerWindow.setFrame(rc, display: true, animate: true)
		}
	}

	private func updateFrameForFullScreen() {
		// this function must be called while in fullscreen
		shouldResize = true

		var newFrame = calculateFrame(from: rcBeforeFullScrn, toFit: dispLayer.aspectRatio, mode: [.fixPosCenter, .sizeDiag])

		rcBeforeFullScrn = newFrame

		// determine the fillscreen state; this must be done after setExternalAspectRatio
		newFrame.size = bounds.size
		controlUI.setFillScreenMode(((newFrame.size.height * dispLayer.aspectRatio) >= newFrame.size.width) ? kFillScreenButtonImageUBKey : kFillScreenButtonImageLRKey,
									state: dispLayer.fillScreen ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue)
	}

	@objc private func prepareForStartingDisplay() {
		if firstDisplay {
			// if this is the first display
			// but at this point the current externalAspectRatio is not known
			// if it is invalid, that means we need to keep our own state; if there is a value, that means we need to keep this aspect
			// until reset or finalized
			firstDisplay = false

			lockAspectRatioValue = true

			controlUI.displayStarted()

			if isInFullScreenMode {
				updateFrameForFullScreen()
			} else {
				if !ud.bool(forKey: kUDKeyDontResizeWhenContinuousPlay) || playbackFinalized {
					// if forced to resize, or it is not continuous playback, resize to the original size
					zoomToSize(ud.float(forKey: kUDKeyInitialFrameSizeRatio))
				} else {
					// AR needs to be adjusted here
					// if an external forced AR was set, set the window according to this AR
					// if no AR was set, fall the AR back to the original AR
					setAspectRatio(dispLayer.externalAspectRatio)
				}

				playerWindow.contentAspectRatio = bounds.size

				if ud.bool(forKey: kUDKeyStartByFullScreen) {
					// if using Lion-style fullscreen mode, since the window is never shown anywhere, a bug would occur
					// if using SL-style fullscreen mode, even though the window is shown here, it will be hidden again upon entering fullscreen, so it will not leak through
					playerWindow.makeKeyAndOrderFront(self)
					controlUI.toggleFullScreen(nil)
				} else {
					if !NSApp.isHidden {
						playerWindow.makeKeyAndOrderFront(self)
					}
				}
			}
		} else {
			// display being opened again during playback means either:
			// 1. letterbox and the like changing the AR from user action
			// 2. or a spontaneous change
			controlUI.displayStarted()

			var ar = kDisplayAspectRatioInvalid

			if IsDisplayLayerAspectValid(frameAspectRatio) {
				let lbMode = ud.integer(forKey: kUDKeyLetterBoxMode)
				let margin = CGFloat(ud.float(forKey: kUDKeyLetterBoxHeight))

				switch lbMode {
				case Int(kPMLetterBoxModeBoth):
					ar = frameAspectRatio / (1 + 2 * margin)
				case Int(kPMLetterBoxModeBottomOnly), Int(kPMLetterBoxModeTopOnly):
					ar = frameAspectRatio / (1 + margin)
				default:
					ar = frameAspectRatio
				}
			}

			if isInFullScreenMode {
				updateFrameForFullScreen()

				if IsDisplayLayerAspectValid(ar) {
					if ud.bool(forKey: kUDKeyLBAutoHeightInFullScrn) {
						// this is here to handle the AR for [auto height][landscape]
						// if it is portrait, letterbox will not be set, but display also will not be closed and reopened, so this is safe for now
						let sz = bounds.size
						dispLayer.externalAspectRatio = sz.width / sz.height
						MPLogString("prepare AR: \(sz.width / sz.height)")
					} else {
						// no need to use setExternalAspectRatio here
						// that function would set frameAspectRatio again based on ar, which would be wasted work
						dispLayer.externalAspectRatio = ar
					}
				}
				dispLayer.display()
			} else {
				let frm = calculateFrame(from: playerWindow.frame,
										 toFit: IsDisplayLayerAspectValid(ar) ? ar : dispLayer.originalAspectRatio,
										 mode: [.fixPosCenter, .sizeDiag])
				playerWindow.setFrame(frm, display: true, animate: true)
				if IsDisplayLayerAspectValid(dispLayer.externalAspectRatio) {
					// if externalAspectRatio has a value set, that means it is forced
					// then update extAR
					// if extAR is invalid, that means we should respect the original AR, so nothing needs to be done
					setExternalAspectRatio(ar)
				}
			}
		}
	}

	// MARK: drag/drop

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		let pboard = sender.draggingPasteboard
		let sourceDragMask = sender.draggingSourceOperationMask

		if pboard.types?.contains(kFilenamesPboardType) ?? false, sourceDragMask.contains(.copy) {
			layer?.borderWidth = 6.0
			return .copy
		}
		return []
	}

	override func draggingExited(_ sender: NSDraggingInfo?) {
		layer?.borderWidth = 0.0
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		let pboard = sender.draggingPasteboard
		let sourceDragMask = sender.draggingSourceOperationMask

		if pboard.types?.contains(kFilenamesPboardType) ?? false {
			if sourceDragMask.contains(.copy) {
				layer?.borderWidth = 0.0
				if let files = pboard.propertyList(forType: kFilenamesPboardType) as? [Any] {
					playerController.loadFiles(files, fromLocal: true)
				}
			}
		}
		return true
	}

	// MARK: coreController delegate
	///////////////////////////////////!!!!!!!!!!!!!!!! these three methods are called on the worker thread; be careful if you need to touch the UI !!!!!!!!!!!!!!!!!!!!!!!!!/////////////////////////////////////////

	func coreController(_ sender: Any!, startWith df: DisplayFormat, buffer data: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>!, total num: UInt) -> Int32 {
		if dispLayer.start(withFormat: df, buffer: data, total: num) == 0 {
			displaying = true

			perform(#selector(prepareForStartingDisplay), on: .main, with: nil, waitUntilDone: true)

			return 0
		}
		return 1
	}

	func coreController(_ sender: Any!, draw frameNum: UInt) {
		dispLayer.draw(frameNum)
	}

	func coreControllerStop(_ sender: Any!) {
		dispLayer.stop()

		displaying = false
		controlUI.displayStopped()
		playerWindow.contentResizeIncrements = NSSize(width: 1.0, height: 1.0)
	}

	// MARK: Application notification

	@objc private func applicationDidBecomeActive(_ notif: Notification) {
		setPlayerWindowLevel()
	}

	@objc private func applicationDidResignActive(_ notif: Notification) {
		setPlayerWindowLevel()
	}

	// MARK: Window Delegate

	func windowWillClose(_ notification: Notification) {
		(notification.object as? NSWindow)?.orderOut(nil)

		if ud.bool(forKey: kUDKeyQuitOnClose) {
			NSApp.terminate(nil)
		} else {
			playerController.stop()
		}
	}

	func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
		displaying && !window.isZoomed
	}

	func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
		if window === playerWindow {
			return calculateFrame(from: window.screen?.visibleFrame ?? .zero,
								  toFit: dispLayer.aspectRatio,
								  mode: [.sizeDiag, .fixPosCenter])
		}
		return newFrame
	}

	func windowDidResize(_ notification: Notification) {
		if !lockAspectRatioValue {
			// if aspect ratio is not locked
			let sz = bounds.size
			setExternalAspectRatio(sz.width / sz.height)
			dispLayer.display()
		}
	}

	// MARK: Accessibility

	override func accessibilitySetValue(_ value: Any, forAttribute attribute: String) {
		guard !isInFullScreenMode else { return }

		var rc = playerWindow.frame

		switch attribute {
		case NSAccessibility.Attribute.position.rawValue:
			rc.origin = (value as? NSValue)?.pointValue ?? rc.origin
		case NSAccessibility.Attribute.size.rawValue:
			let sz = (value as? NSValue)?.sizeValue ?? rc.size

			// target Rect
			rc.origin.x -= (sz.width - rc.size.width) / 2
			rc.origin.y -= (sz.height - rc.size.height) / 2
			rc.size = sz
		case kMPXAccessibilityWindowFrameAttribute:
			rc = (value as? NSValue)?.rectValue ?? rc
		default:
			// only respond to position and size
			return
		}

		rc = calculateFrame(from: rc, toFit: dispLayer.aspectRatio, mode: [.fixPosCenter, .sizeInFit])
		playerWindow.setFrame(rc, display: true, animate: false)
	}
}
