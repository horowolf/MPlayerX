/*
 * MPlayerX - ShortCutManager.swift
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

private let kSCMRepeatCounterThreshold = 6

@objc(ShortCutManager)
class ShortCutManager: NSObject {
	private let ud = UserDefaults.standard

	private var appleRemoteControl: AppleRemote?

	private var repeatEntered = false
	private var repeatCanceled = false
	private var repeatCounter = 0
	private var arKeyRepTime: Float = 0

	private var seekStepTimeL: Float = 0
	private var seekStepTimeR: Float = 0
	private var seekStepTimeU: Float = 0
	private var seekStepTimeB: Float = 0

	@IBOutlet weak var playerController: PlayerController?
	@IBOutlet weak var controlUI: ControlUIView?
	// Never referenced from the implementation below -- carried over unused
	// from the ObjC original, which also never touched it. Kept only so the
	// existing MainMenu.xib outlet connection doesn't fail to resolve at
	// nib-load time.
	@IBOutlet weak var dispView: RootLayerView?
	@IBOutlet weak var mainMenu: NSMenu?

	// Equivalent of the ObjC original's +initialize (see CharsetQueryController
	// for why this lazily-evaluated static stands in for it in Swift).
	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [
			kUDKeySpeedStep: 0.1,
			kUDKeySeekStepL: -10,
			kUDKeySeekStepR: 10,
			kUDKeySeekStepU: 60,
			kUDKeySeekStepB: -60,
			kUDKeySubDelayStepTime: 0.1,
			kUDKeyAudioDelayStepTime: 0.1,
			kUDKeyARKeyRepeatTimeInterval: 0.3,
			kUDKeyARKeyRepeatTimeIntervalLong: 1.0,
			kUDKeySupportAppleRemote: true,
		])
	}()

	override init() {
		super.init()
		_ = ShortCutManager.registerDefaultsOnce

		seekStepTimeL = ud.float(forKey: kUDKeySeekStepL)
		seekStepTimeR = ud.float(forKey: kUDKeySeekStepR)
		seekStepTimeU = ud.float(forKey: kUDKeySeekStepU)
		seekStepTimeB = ud.float(forKey: kUDKeySeekStepB)

		arKeyRepTime = ud.float(forKey: kUDKeyARKeyRepeatTimeInterval)

		if ud.bool(forKey: kUDKeySupportAppleRemote) {
			appleRemoteControl = AppleRemote(delegate: self)
		} else {
			appleRemoteControl = nil
		}

		NotificationCenter.default.addObserver(self, selector: #selector(applicationWillBecomeActive(_:)),
												name: NSApplication.willBecomeActiveNotification, object: NSApp)
		NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive(_:)),
												name: NSApplication.willResignActiveNotification, object: NSApp)
		NotificationCenter.default.addObserver(self, selector: #selector(mediaKeyPressed(_:)),
												name: NSNotification.Name.mpxMediaKeyPlayPause, object: NSApp)
		NotificationCenter.default.addObserver(self, selector: #selector(mediaKeyPressed(_:)),
												name: NSNotification.Name.mpxMediaKeyForward, object: NSApp)
		NotificationCenter.default.addObserver(self, selector: #selector(mediaKeyPressed(_:)),
												name: NSNotification.Name.mpxMediaKeyBackward, object: NSApp)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	@objc private func mediaKeyPressed(_ notif: Notification) {
		switch notif.name {
		case NSNotification.Name.mpxMediaKeyPlayPause:
			controlUI?.togglePlayPause(nil)
		case NSNotification.Name.mpxMediaKeyForward:
			_ = mainMenu?.performKeyEquivalent(with: NSEvent.makeKeyDownEvent(kSCMNextEpisodeKeyEquivalent, modifierFlags: 0))
		case NSNotification.Name.mpxMediaKeyBackward:
			_ = mainMenu?.performKeyEquivalent(with: NSEvent.makeKeyDownEvent(kSCMPrevEpisodeKeyEquivalent, modifierFlags: 0))
		default:
			break
		}
	}

	@objc(processKeyDown:)
	@discardableResult
	func processKeyDown(_ event: NSEvent) -> Bool {
		guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
			return false
		}

		let key = chars.utf16.first!
		var ret = true

		switch event.modifierFlags.intersection([.shift, .control, .option, .command]) {
		case .control:
			switch key {
			case UInt16(NSUpArrowFunctionKey):
				_ = playerController?.changeSpeedBy(ud.float(forKey: kUDKeySpeedStep))
			case UInt16(NSDownArrowFunctionKey):
				_ = playerController?.changeSpeedBy(-ud.float(forKey: kUDKeySpeedStep))
			case UInt16(NSLeftArrowFunctionKey):
				_ = playerController?.setSpeed(1)
			default:
				ret = false
			}

		case .shift:
			ret = false

		case .option:
			switch key {
			case UInt16(NSUpArrowFunctionKey):
				_ = playerController?.changeAudioDelayBy(ud.float(forKey: kUDKeyAudioDelayStepTime))
			case UInt16(NSDownArrowFunctionKey):
				_ = playerController?.changeAudioDelayBy(-ud.float(forKey: kUDKeyAudioDelayStepTime))
			case UInt16(NSLeftArrowFunctionKey):
				_ = playerController?.setAudioDelay(0)
			default:
				ret = false
			}

		case .command:
			switch key {
			case UInt16(NSUpArrowFunctionKey):
				_ = playerController?.changeSubDelayBy(ud.float(forKey: kUDKeySubDelayStepTime))
			case UInt16(NSDownArrowFunctionKey):
				_ = playerController?.changeSubDelayBy(-ud.float(forKey: kUDKeySubDelayStepTime))
			case UInt16(NSLeftArrowFunctionKey):
				_ = playerController?.setSubDelay(0)
			default:
				ret = false
			}

		case []:
			switch key {
			case UInt16(NSRightArrowFunctionKey):
				if playerController?.playerState() == kMPCPausedState {
					playerController?.frameStep()
				} else {
					controlUI?.changeTime(by: seekStepTimeR)
				}
			case UInt16(NSLeftArrowFunctionKey):
				controlUI?.changeTime(by: seekStepTimeL)
			case UInt16(NSUpArrowFunctionKey):
				controlUI?.changeTime(by: seekStepTimeU)
			case UInt16(NSDownArrowFunctionKey):
				controlUI?.changeTime(by: seekStepTimeB)
			default:
				ret = false
			}

		default:
			ret = false
		}

		return ret
	}

	// RemoteControl.h declares this as an informal NSObject(RemoteControlDelegate)
	// category method, so every NSObject subclass sees it as already declared
	// (with no implementation) -- Swift accordingly treats providing a body
	// here as an override, not a fresh declaration.
	@objc(sendRemoteButtonEvent:pressedDown:remoteControl:)
	override func sendRemoteButtonEvent(_ event: RemoteControlEventIdentifier, pressedDown: Bool, remoteControl: RemoteControl?) {
		if pressedDown {
			repeatCanceled = false

			var keyEqTemp: String?
			var key: unichar = 0
			var target: AnyObject?
			// Same selector name (`performKeyEquivalent:`) resolves on both
			// NSMenu and NSResponder (ControlUIView); NSSelectorFromString
			// sidesteps having to pick one declaration for #selector.
			let performKeyEquivalentSel = NSSelectorFromString("performKeyEquivalent:")
			var action: Selector?

			switch event {
			case kRemoteButtonPlus_Hold, kRemoteButtonPlus:
				keyEqTemp = kSCMVolumeUpKeyEquivalent
				target = mainMenu
				action = performKeyEquivalentSel

			case kRemoteButtonMinus_Hold, kRemoteButtonMinus:
				keyEqTemp = kSCMVolumeDownKeyEquivalent
				target = mainMenu
				action = performKeyEquivalentSel

			case kRemoteButtonMenu:
				keyEqTemp = kSCMFullScrnKeyEquivalent
				target = mainMenu
				action = performKeyEquivalentSel

			case kRemoteButtonMenu_Hold:
				keyEqTemp = kSCMFillScrnKeyEquivalent
				target = mainMenu
				action = performKeyEquivalentSel

			case kRemoteButtonPlay:
				keyEqTemp = kSCMPlayPauseKeyEquivalent
				target = controlUI
				action = performKeyEquivalentSel

			case kRemoteButtonPlay_Hold:
				if playerController?.playerState() == kMPCPlayingState {
					controlUI?.togglePlayPause(nil)
				}
				let sleepScript = NSAppleScript(source: "do shell script \"pmset sleepnow\"")
				var err: NSDictionary?
				sleepScript?.executeAndReturnError(&err)

			case kRemoteButtonRight_Hold:
				repeatEntered = true
				repeatCounter = 0
				arKeyRepTime = ud.float(forKey: kUDKeyARKeyRepeatTimeInterval)
				fallthrough
			case kRemoteButtonRight:
				key = UInt16(NSRightArrowFunctionKey)
				target = self
				action = #selector(ShortCutManager.processKeyDown(_:))

			case kRemoteButtonLeft_Hold:
				repeatEntered = true
				repeatCounter = 0
				arKeyRepTime = ud.float(forKey: kUDKeyARKeyRepeatTimeInterval)
				fallthrough
			case kRemoteButtonLeft:
				key = UInt16(NSLeftArrowFunctionKey)
				target = self
				action = #selector(ShortCutManager.processKeyDown(_:))

			default:
				break
			}

			if let target = target, let action = action {
				let ev: NSEvent
				if let keyEqTemp = keyEqTemp {
					ev = NSEvent.makeKeyDownEvent(keyEqTemp, modifierFlags: 0)
				} else {
					ev = NSEvent.makeKeyDownEvent(String(utf16CodeUnits: [key], count: 1), modifierFlags: 0)
				}
				simulateEvent(SimulateEventBox(target: target, selector: action, event: ev))
			}
		} else {
			repeatCanceled = true
			repeatEntered = false
		}
	}

	// Stands in for the NSArray of (target, action-as-boxed-SEL, event) the
	// ObjC original passed to -performSelector:withObject:afterDelay: -- SEL
	// isn't an object in ObjC either, hence that version's NSNumber-encoded
	// pointer trick; a plain typed box is simpler in Swift.
	private final class SimulateEventBox: NSObject {
		let target: AnyObject
		let selector: Selector
		let event: NSEvent
		init(target: AnyObject, selector: Selector, event: NSEvent) {
			self.target = target
			self.selector = selector
			self.event = event
		}
	}

	// Deliberately kept as -performSelector:withObject:afterDelay: (rather
	// than e.g. GCD) so the repeat, like the ObjC original, only fires while
	// the main run loop is in the default mode -- e.g. it naturally pauses
	// while a menu is tracking.
	@objc private func simulateEvent(_ box: SimulateEventBox) {
		if !repeatCanceled {
			_ = box.target.perform(box.selector, with: box.event)
		}

		if repeatEntered {
			repeatCounter += 1

			if repeatCounter != kSCMRepeatCounterThreshold {
				perform(#selector(ShortCutManager.simulateEvent(_:)), with: box, afterDelay: TimeInterval(arKeyRepTime))
			} else if repeatCounter == kSCMRepeatCounterThreshold {
				var newEv = box.event
				var key = box.event.charactersIgnoringModifiers?.utf16.first ?? 0
				var timeLong = arKeyRepTime

				if key == UInt16(NSRightArrowFunctionKey) || key == UInt16(NSLeftArrowFunctionKey) {
					key = (key == UInt16(NSRightArrowFunctionKey)) ? UInt16(NSUpArrowFunctionKey) : UInt16(NSDownArrowFunctionKey)
					newEv = NSEvent.makeKeyDownEvent(String(utf16CodeUnits: [key], count: 1), modifierFlags: 0)
					timeLong = ud.float(forKey: kUDKeyARKeyRepeatTimeIntervalLong)
				}

				let newBox = SimulateEventBox(target: box.target, selector: box.selector, event: newEv)
				perform(#selector(ShortCutManager.simulateEvent(_:)), with: newBox, afterDelay: TimeInterval(arKeyRepTime))
				arKeyRepTime = timeLong
			}
		}
	}

	@objc private func applicationWillBecomeActive(_ notif: Notification) {
		appleRemoteControl?.startListening(self)
	}

	@objc private func applicationWillResignActive(_ notif: Notification) {
		appleRemoteControl?.stopListening(self)
	}
}
