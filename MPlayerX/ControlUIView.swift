/*
 * MPlayerX - ControlUIView.swift
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

private let CONTROLALPHA: CGFloat = 1
private let BACKGROUNDALPHA: CGFloat = 0.9

private let CONTROL_CORNER_RADIUS: CGFloat = 6

private let NUMOFVOLUMEIMAGES = 3 // this value is the number of images excluding the no-volume one
private let AUTOHIDETIMEINTERNAL: Double = 3

private let LASTSTOPPEDTIMERATIO = 100

private let ASPECTRATIOBASE: CGFloat = 900

/// These two used to be `extern NSString * const` in ControlUIView.h for
/// RootLayerView.m's benefit; both callers are Swift now, so they are plain
/// module-internal constants.
let kFillScreenButtonImageLRKey = "LR"
let kFillScreenButtonImageUBKey = "UB"

private let kStringFMTTimeAppendTotal = " / %@"

private let PlayState = NSControl.StateValue.on
private let PauseState = NSControl.StateValue.off

// The localized strings below are the same keys and comments LocalizedStrings.h
// declares as macros; Swift cannot use those macros, so the NSLocalizedString
// calls are spelled out with identical key and comment text, which keeps
// genstrings producing the same Localizable.strings entries.
private var kMPXStringDisable: String { NSLocalizedString("Disable", comment: "") }
private var kMPXStringOSDSettingChanged: String { NSLocalizedString("OSD settings changed", comment: "OSD hint") }
private var kMPXStringOSDPlaybackStopped: String { NSLocalizedString("Stopped", comment: "OSD hint") }
private var kMPXStringOSDPlaybackPaused: String { NSLocalizedString("Paused", comment: "OSD hint") }
private var kMPXStringOSDNull: String { NSLocalizedString(" ", comment: "OSD hint") }
private var kMPXStringOSDMuteON: String { NSLocalizedString("Mute ON", comment: "OSD hint") }
private var kMPXStringOSDMuteOFF: String { NSLocalizedString("Mute OFF", comment: "OSD hint") }
private var kMPXStringOSDVolumeHint: String { NSLocalizedString("Volume: %.1f", comment: "OSD hint") }
private var kMPXStringOSDSubtitleHint: String { NSLocalizedString("Sub: %@", comment: "OSD hint") }
private var kMPXStringOSDAudioHint: String { NSLocalizedString("Audio %@", comment: "OSD hint") }
private var kMPXStringOSDVideoHint: String { NSLocalizedString("Video %@", comment: "OSD hint") }
private var kMPXStringOSDChapterHint: String { NSLocalizedString("Chapter: %@", comment: "OSD hint") }
private var kMPXStringOSDSpeedHint: String { NSLocalizedString("Speed: %.1fX", comment: "OSD hint") }
private var kMPXStringOSDSubDelayHint: String { NSLocalizedString("Sub Delay: %.1f s", comment: "OSD hint") }
private var kMPXStringOSDAudioDelayHint: String { NSLocalizedString("Audio Delay: %.1f s", comment: "OSD hint") }
private var kMPXStringOSDCachingPercent: String { NSLocalizedString("Caching: %4.2f%%", comment: "OSD hint") }
private var kMPXStringOSDAspectRatioLocked: String { NSLocalizedString("Aspect Ratio: Locked", comment: "OSD hint") }
private var kMPXStringOSDAspectRatioUnLocked: String { NSLocalizedString("Aspect Ratio: Unlocked", comment: "OSD hint") }
private var kMPXStringOSDAspectRatioReset: String { NSLocalizedString("Aspect Ratio: Restored", comment: "OSD hint") }
private var kMPXStringMenuUnlockAspectRatio: String { NSLocalizedString("Unlock Aspect Ratio", comment: "menu") }
private var kMPXStringMenuLockAspectRatio: String { NSLocalizedString("Lock Aspect Ratio", comment: "menu") }
private var kMPXStringMenuShowLetterBox: String { NSLocalizedString("Show Letterbox", comment: "menu") }
private var kMPXStringMenuHideLetterBox: String { NSLocalizedString("Hide Letterbox", comment: "menu") }
private var kMPXStringMenuEnterFullscrn: String { NSLocalizedString("Enter Fullscreen", comment: "menu") }
private var kMPXStringMenuExitFullscrn: String { NSLocalizedString("Exit Fullscreen", comment: "menu") }
private var kMPXStringMenuShowAuxCtrls: String { NSLocalizedString("Show Auxiliary Controls", comment: "menu") }
private var kMPXStringMenuHideAuxCtrls: String { NSLocalizedString("Hide Auxiliary Controls", comment: "menu") }

@objc(ControlUIView)
class ControlUIView: NSView {

	private let ud = UserDefaults.standard
	private let notifCenter = NotificationCenter.default

	// button images
	private var fillScreenButtonAllImages: [String: [NSImage?]] = [:]
	private var volumeButtonImages: [NSImage?] = []

	private var fillGradient: NSGradient?
	private var backGroundColor: NSColor?
	private var backGroundColor2: NSColor?

	// formatters
	private let timeFormatter = TimeFormatter()
	private let floatWrapFormatter = FloatWrapFormatter()

	// autohide things
	private var autoHideTimeInterval: TimeInterval = 0
	private var shouldHide = false
	private var autoHideTimer: Timer?

	// list for sub/audio/video
	private let subListMenu = NSMenu(title: "SubListMenu")
	private let audioListMenu = NSMenu(title: "AudioListMenu")
	private let videoListMenu = NSMenu(title: "VideoListMenu")
	private let chapterListMenu = NSMenu(title: "ChapterListMenu")

	private var volStep: Float = 0
	private var orgHeight: CGFloat = 0

	@IBOutlet weak var playerController: PlayerController!
	@IBOutlet weak var dispView: RootLayerView!
	@IBOutlet weak var fillScreenButton: NSButton!
	@IBOutlet weak var fullScreenButton: NSButton!
	@IBOutlet weak var playPauseButton: NSButton!
	@IBOutlet weak var volumeButton: NSButton!
	@IBOutlet weak var volumeSlider: NSSlider!
	@IBOutlet weak var timeText: NSTextField!
	@IBOutlet weak var timeTextAlt: NSTextField!
	@IBOutlet weak var nextEPButton: NSButton!
	@IBOutlet weak var prevEPButton: NSButton!
	@IBOutlet weak var timeDispSwitch: NSButton!

	@IBOutlet weak var timeSlider: NSSlider!
	@IBOutlet weak var hintTime: NSTextField!

	@IBOutlet weak var accessaryContainer: NSView!
	@IBOutlet weak var toggleAcceButton: NSButton!

	@IBOutlet weak var speedText: ArrowTextField!
	@IBOutlet weak var subDelayText: ArrowTextField!
	@IBOutlet weak var audioDelayText: ArrowTextField!

	@IBOutlet weak var rzIndicator: ResizeIndicator!
	@IBOutlet weak var osd: OsdText!
	@IBOutlet weak var title: TitleView!

	@IBOutlet weak var menuSnapshot: NSMenuItem!
	@IBOutlet weak var menuSwitchSub: NSMenuItem!
	@IBOutlet weak var menuSubScaleInc: NSMenuItem!
	@IBOutlet weak var menuSubScaleDec: NSMenuItem!
	@IBOutlet weak var menuPlayFromLastStoppedPlace: NSMenuItem!
	@IBOutlet weak var menuSwitchAudio: NSMenuItem!
	@IBOutlet weak var menuVolInc: NSMenuItem!
	@IBOutlet weak var menuVolDec: NSMenuItem!
	@IBOutlet weak var menuToggleLockAspectRatio: NSMenuItem!
	@IBOutlet weak var menuResetLockAspectRatio: NSMenuItem!
	@IBOutlet weak var menuToggleLetterBox: NSMenuItem!
	@IBOutlet weak var menuSwitchVideo: NSMenuItem!
	@IBOutlet weak var menuSizeInc: NSMenuItem!
	@IBOutlet weak var menuSizeDec: NSMenuItem!
	@IBOutlet weak var menuShowMediaInfo: NSMenuItem!
	@IBOutlet weak var menuToggleFullScreen: NSMenuItem!
	@IBOutlet weak var menuToggleFillScreen: NSMenuItem!
	@IBOutlet weak var menuToggleAuxiliaryCtrls: NSMenuItem!
	@IBOutlet weak var menuMoveToTrash: NSMenuItem!
	@IBOutlet weak var menuMoveFrameToCenter: NSMenuItem!
	@IBOutlet weak var menuNextEpisode: NSMenuItem!
	@IBOutlet weak var menuPrevEpisode: NSMenuItem!
	@IBOutlet weak var menuResetFrameScaleRatio: NSMenuItem!
	@IBOutlet weak var menuEnlargeFrame: NSMenuItem!
	@IBOutlet weak var menuShrinkFrame: NSMenuItem!
	@IBOutlet weak var menuEnlargeFrame2: NSMenuItem!
	@IBOutlet weak var menuShrinkFrame2: NSMenuItem!
	@IBOutlet weak var menuMirror: NSMenuItem!
	@IBOutlet weak var menuFlip: NSMenuItem!

	@IBOutlet weak var menuSpeedUp: NSMenuItem!
	@IBOutlet weak var menuSpeedDown: NSMenuItem!
	@IBOutlet weak var menuSpeedReset: NSMenuItem!
	@IBOutlet weak var menuAudioDelayInc: NSMenuItem!
	@IBOutlet weak var menuAudioDelayDec: NSMenuItem!
	@IBOutlet weak var menuAudioDelayReset: NSMenuItem!
	@IBOutlet weak var menuSubDelayInc: NSMenuItem!
	@IBOutlet weak var menuSubDelayDec: NSMenuItem!
	@IBOutlet weak var menuSubDelayReset: NSMenuItem!

	@IBOutlet weak var menuZoomToHalfSize: NSMenuItem!
	@IBOutlet weak var menuZoomToOriginSize: NSMenuItem!
	@IBOutlet weak var menuZoomToDoubleSize: NSMenuItem!
	@IBOutlet weak var menuWndFitToScrn: NSMenuItem!
	@IBOutlet weak var menuAudioChannels: NSMenuItem!
	@IBOutlet weak var menuChapterList: NSMenuItem!

	/// The ObjC original sent -floatValue / -tag to an untyped `id` sender:
	/// sometimes a control from the nib, sometimes an NSMenuItem, sometimes an
	/// NSNumber posted by ShortCutManager. These spell out the same duck typing.
	private func senderFloatValue(_ sender: Any?) -> Float {
		if let n = sender as? NSNumber { return n.floatValue }
		if let c = sender as? NSControl { return c.floatValue }
		return 0
	}

	private func senderTag(_ sender: Any?) -> Int {
		if let i = sender as? NSMenuItem { return i.tag }
		if let v = sender as? NSView { return v.tag }
		return 0
	}

	/// A value pulled out of a KVO change dictionary that has been round-tripped
	/// through a notification's userInfo can arrive wrapped in an extra layer of
	/// Optional (an `Any` holding `Optional<Any>` holding the NSNumber), and a
	/// plain `as? NSNumber` on that silently yields nil -- which is how the whole
	/// time/length/speed readout ended up frozen at zero the first time this file
	/// was ported. Mirror is the only way to see through the extra layer.
	private func kvoUnwrap(_ value: Any?) -> Any? {
		guard let value else { return nil }

		let mirror = Mirror(reflecting: value)
		if mirror.displayStyle == .optional {
			guard let inner = mirror.children.first?.value else { return nil }
			return kvoUnwrap(inner)
		}
		if value is NSNull { return nil }
		return value
	}

	/// CoreController fills movieInfo/playingInfo through -setValue:forKeyPath:
	/// with the raw text it parsed out of mplayer's stdout, so a property Swift
	/// declares as NSNumber really holds an NSString at runtime. The ObjC caller
	/// got away with it because -floatValue exists on both classes; Swift's
	/// `as? NSNumber` just returns nil, which froze every numeric readout.
	/// (Same trap as the kMITypeStateChanged bug fixed in CoreController.)
	private func kvoNumber(_ value: Any?) -> NSNumber? {
		switch kvoUnwrap(value) {
		case let n as NSNumber:
			return n
		case let s as NSString:
			return NSNumber(value: s.doubleValue)
		default:
			return nil
		}
	}

	private func kvoArray(_ value: Any?) -> [Any]? {
		kvoUnwrap(value) as? [Any]
	}

	/// The ObjC original assigned float expressions straight into -setIntValue:,
	/// where an infinite or NaN value is merely undefined; Swift's Int32() traps
	/// on those, and a zero-width timeSlider really can produce one.
	private func safeInt32(_ v: Double) -> Int32 {
		guard v.isFinite else { return 0 }
		return Int32(max(Double(Int32.min), min(Double(Int32.max), v)))
	}

	/// Replaces the ObjC +initialize.
	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [
			kUDKeyVolume: Float(50),
			kUDKeyCtrlUIAutoHideTime: AUTOHIDETIMEINTERNAL,
			kUDKeySwitchTimeHintPressOnAbusolute: false,
			kUDKeyTimeTextAltTotal: false,
			kUDKeyVolumeStep: Float(10),
			kUDKeyCtrlUIBackGroundAlpha: Float(BACKGROUNDALPHA),
			kUDKeyShowOSD: true,
			kUDKeyResizeStep: Float(0.1),
			kUDKeyCloseWindowWhenStopped: true,
			kUDKeyHideTitlebar: false,
			kUDKeyFrameScaleStep: Float(0.001),
			kUDKeyLBAutoHeightInFullScrn: false,
			kUDKeyPlayWhenEnterFullScrn: false,
			kUDKeyResizeControlBar: true,
		])
	}()

	required init?(coder: NSCoder) {
		_ = ControlUIView.registerDefaultsOnce
		super.init(coder: coder)
	}

	override init(frame frameRect: NSRect) {
		_ = ControlUIView.registerDefaultsOnce
		super.init(frame: frameRect)
	}

	override func awakeFromNib() {
		super.awakeFromNib()

		orgHeight = bounds.size.height

		// settings for itself
		alphaValue = CONTROLALPHA
		refreshBackgroundAlpha()
		// auto-hide settings
		refreshAutoHideTimer()

		if ud.bool(forKey: kUDKeyResizeControlBar) {
			autoresizingMask = [.width, .minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
		} else {
			autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
		}

		////////////////////////////////////////set KeyEquivalents////////////////////////////////////////
		volumeButton.keyEquivalent = kSCMMuteKeyEquivalent
		playPauseButton.keyEquivalent = kSCMPlayPauseKeyEquivalent
		fullScreenButton.keyEquivalentModifierMask = kSCMFullscreenKeyEquivalentModifierFlagMask
		fullScreenButton.keyEquivalent = kSCMFullScrnKeyEquivalent

		menuSnapshot.keyEquivalent = kSCMSnapShotKeyEquivalent

		menuSubScaleInc.keyEquivalentModifierMask = kSCMSubScaleIncreaseKeyEquivalentModifierFlagMask
		menuSubScaleInc.keyEquivalent = kSCMSubScaleIncreaseKeyEquivalent
		menuSubScaleDec.keyEquivalentModifierMask = kSCMSubScaleDecreaseKeyEquivalentModifierFlagMask
		menuSubScaleDec.keyEquivalent = kSCMSubScaleDecreaseKeyEquivalent

		menuPlayFromLastStoppedPlace.keyEquivalent = kSCMPlayFromLastStoppedKeyEquivalent
		menuPlayFromLastStoppedPlace.keyEquivalentModifierMask = kSCMPlayFromLastStoppedKeyEquivalentModifierFlagMask

		menuSwitchSub.keyEquivalent = kSCMSwitchSubKeyEquivalent
		menuSwitchAudio.keyEquivalent = kSCMSwitchAudioKeyEquivalent
		menuSwitchVideo.keyEquivalent = kSCMSwitchVideoKeyEquivalent

		menuVolInc.keyEquivalent = kSCMVolumeUpKeyEquivalent
		menuVolDec.keyEquivalent = kSCMVolumeDownKeyEquivalent
		menuVolInc.keyEquivalentModifierMask = []
		menuVolDec.keyEquivalentModifierMask = []

		menuToggleLockAspectRatio.keyEquivalent = kSCMToggleLockAspectRatioKeyEquivalent

		menuResetLockAspectRatio.keyEquivalent = kSCMResetLockAspectRatioKeyEquivalent
		menuResetLockAspectRatio.keyEquivalentModifierMask = kSCMResetLockAspectRatioKeyEquivalentModifierFlagMask

		menuToggleLetterBox.keyEquivalent = kSCMToggleLetterBoxKeyEquivalent

		menuSizeInc.keyEquivalentModifierMask = kSCMWindowSizeIncKeyEquivalentModifierFlagMask
		menuSizeDec.keyEquivalentModifierMask = kSCMWindowSizeDecKeyEquivalentModifierFlagMask
		menuSizeInc.keyEquivalent = kSCMWindowSizeIncKeyEquivalent
		menuSizeDec.keyEquivalent = kSCMWindowSizeDecKeyEquivalent

		menuShowMediaInfo.keyEquivalent = kSCMShowMediaInfoKeyEquivalent

		menuToggleFullScreen.keyEquivalent = kSCMFullScrnKeyEquivalent
		menuToggleFillScreen.keyEquivalent = kSCMFillScrnKeyEquivalent
		menuToggleAuxiliaryCtrls.keyEquivalent = kSCMAcceControlKeyEquivalent

		menuMoveToTrash.keyEquivalentModifierMask = kSCMMoveToTrashKeyEquivalentModifierFlagMask
		var keyTemp = kSCMMoveToTrashKeyEquivalent
		menuMoveToTrash.keyEquivalent = String(utf16CodeUnits: &keyTemp, count: 1)

		menuMoveFrameToCenter.keyEquivalent = kSCMMoveFrameToCenterKeyEquivalent

		menuNextEpisode.keyEquivalent = kSCMNextEpisodeKeyEquivalent
		menuPrevEpisode.keyEquivalent = kSCMPrevEpisodeKeyEquivalent

		menuResetFrameScaleRatio.keyEquivalentModifierMask = kSCMResetFrameScaleRatioKeyEquivalentModifierFlagMask
		menuResetFrameScaleRatio.keyEquivalent = kSCMResetFrameScaleRatioKeyEquivalent

		menuEnlargeFrame.keyEquivalentModifierMask = kSCMScaleFrameLargerKeyEquivalentModifierFlagMask
		menuEnlargeFrame.keyEquivalent = kSCMScaleFrameLargerKeyEquivalent
		menuShrinkFrame.keyEquivalentModifierMask = kSCMScaleFrameSmallerKeyEquivalentModifierFlagMask
		menuShrinkFrame.keyEquivalent = kSCMScaleFrameSmallerKeyEquivalent

		menuEnlargeFrame2.keyEquivalentModifierMask = kSCMScaleFrameLarger2KeyEquivalentModifierFlagMask
		menuEnlargeFrame2.keyEquivalent = kSCMScaleFrameLargerKeyEquivalent
		menuShrinkFrame2.keyEquivalentModifierMask = kSCMScaleFrameSmaller2KeyEquivalentModifierFlagMask
		menuShrinkFrame2.keyEquivalent = kSCMScaleFrameSmallerKeyEquivalent

		menuMirror.keyEquivalentModifierMask = kSCMMirrorKeyEquivalentModifierFlagMask
		menuMirror.keyEquivalent = kSCMMirrorKeyEquivalent
		menuFlip.keyEquivalentModifierMask = kSCMFlipKeyEquivalentModifierFlagMask
		menuFlip.keyEquivalent = kSCMFlipKeyEquivalent

		menuSpeedUp.keyEquivalent = kSCMSpeedUpKeyEquivalent
		menuSpeedDown.keyEquivalent = kSCMSpeedDownKeyEquivalent
		menuSpeedReset.keyEquivalent = kSCMSpeedResetKeyEquivalent

		menuAudioDelayInc.keyEquivalentModifierMask = kSCMAudioDelayKeyEquivalentModifierFlagMask
		menuAudioDelayInc.keyEquivalent = kSCMAudioDelayPlusKeyEquivalent
		menuAudioDelayDec.keyEquivalentModifierMask = kSCMAudioDelayKeyEquivalentModifierFlagMask
		menuAudioDelayDec.keyEquivalent = kSCMAudioDelayMinusKeyEquivalent
		menuAudioDelayReset.keyEquivalentModifierMask = kSCMAudioDelayKeyEquivalentModifierFlagMask
		menuAudioDelayReset.keyEquivalent = kSCMAudioDelayResetKeyEquivalent

		menuSubDelayInc.keyEquivalentModifierMask = kSCMSubDelayKeyEquivalentModifierFlagMask
		menuSubDelayInc.keyEquivalent = kSCMSubDelayPlusKeyEquivalent
		menuSubDelayDec.keyEquivalentModifierMask = kSCMSubDelayKeyEquivalentModifierFlagMask
		menuSubDelayDec.keyEquivalent = kSCMSubDelayMinusKeyEquivalent
		menuSubDelayReset.keyEquivalentModifierMask = kSCMSubDelayKeyEquivalentModifierFlagMask
		menuSubDelayReset.keyEquivalent = kSCMSubDelayResetKeyEquivalent

		menuZoomToHalfSize.keyEquivalentModifierMask = kSCMWindowZoomHalfSizeKeyEquivalentModifierFlagMask
		menuZoomToHalfSize.keyEquivalent = kSCMWindowZoomHalfSizeKeyEquivalent
		menuZoomToOriginSize.keyEquivalentModifierMask = kSCMWindowZoomToOrgSizeKeyEquivalentModifierFlagMask
		menuZoomToOriginSize.keyEquivalent = kSCMWindowZoomToOrgSizeKeyEquivalent
		menuZoomToDoubleSize.keyEquivalentModifierMask = kSCMWindowZoomDblSizeKeyEquivalentModifierFlagMask
		menuZoomToDoubleSize.keyEquivalent = kSCMWindowZoomDblSizeKeyEquivalent
		menuWndFitToScrn.keyEquivalentModifierMask = kSCMWindowFitToScreenKeyEquivalentModifierFlagMask
		menuWndFitToScrn.keyEquivalent = kSCMWindowFitToScreenKeyEquivalent

		////////////////////////////////////////load Images////////////////////////////////////////
		// initialize the volume-level icons
		volumeButtonImages = [NSImage(named: "vol_no"), NSImage(named: "vol_low"),
							  NSImage(named: "vol_mid"), NSImage(named: "vol_high")]
		// fillScreenButton initialization
		fillScreenButtonAllImages = [
			kFillScreenButtonImageLRKey: [NSImage(named: "fillscreen_lr"), NSImage(named: "exitfillscreen_lr")],
			kFillScreenButtonImageUBKey: [NSImage(named: "fillscreen_ub"), NSImage(named: "exitfillscreen_ub")],
		]

		// get the default volume value from userdefault
		setVolume(ud.object(forKey: kUDKeyVolume))

		// Mask mouseup event
		volumeSlider.sendAction(on: [.leftMouseDown, .leftMouseDragged])

		// set Volume menu
		menuVolInc.isEnabled = true
		menuVolInc.tag = 1
		menuVolDec.isEnabled = true
		menuVolDec.tag = -1

		// set Volume step
		volStep = ud.float(forKey: kUDKeyVolumeStep)

		// initialize the time display slider and text
		timeText.cell?.formatter = timeFormatter
		timeText.stringValue = ""
		useTabularFigures(timeText)
		timeTextAlt.cell?.formatter = timeFormatter
		timeTextAlt.stringValue = ""
		useTabularFigures(timeTextAlt)

		timeSlider.isEnabled = false
		timeSlider.maxValue = 0
		timeSlider.minValue = -1
		// only trigger the event on drag and mouse down
		timeSlider.sendAction(on: [.leftMouseDown, .leftMouseDragged])

		// set Time hint text
		hintTime.alphaValue = 0
		hintTime.cell?.formatter = timeFormatter
		hintTime.stringValue = ""
		useTabularFigures(hintTime)

		// initial state is hidden
		fullScreenButton.isHidden = true

		// set fillscreen button status and image
		fillScreenButton.isHidden = true
		if let fillScrnBtnModeImages = fillScreenButtonAllImages[kFillScreenButtonImageUBKey] {
			fillScreenButton.image = fillScrnBtnModeImages[0]
			fillScreenButton.alternateImage = fillScrnBtnModeImages[1]
		}
		fillScreenButton.state = .off

		// set fomatter and step
		speedText.cell?.formatter = floatWrapFormatter
		subDelayText.cell?.formatter = floatWrapFormatter
		audioDelayText.cell?.formatter = floatWrapFormatter

		speedText.stepValue = ud.float(forKey: kUDKeySpeedStep)
		subDelayText.stepValue = ud.float(forKey: kUDKeySubDelayStepTime)
		audioDelayText.stepValue = ud.float(forKey: kUDKeyAudioDelayStepTime)

		// set list for sub/audio/video menu
		menuSwitchSub.submenu = subListMenu
		subListMenu.autoenablesItems = false
		resetSubtitleMenu()

		menuSwitchAudio.submenu = audioListMenu
		audioListMenu.autoenablesItems = false
		resetAudioMenu()

		menuSwitchVideo.submenu = videoListMenu
		videoListMenu.autoenablesItems = false
		resetVideoMenu()

		menuChapterList.submenu = chapterListMenu
		chapterListMenu.autoenablesItems = false
		resetChapterListMenu()

		// set menuItem tags
		menuSubScaleInc.tag = 1
		menuSubScaleDec.tag = -1

		menuSizeInc.tag = 1
		menuSizeDec.tag = -1

		// set menu status
		menuToggleLockAspectRatio.isEnabled = false
		menuToggleLockAspectRatio.title = dispView.lockAspectRatio ? kMPXStringMenuUnlockAspectRatio : kMPXStringMenuLockAspectRatio

		menuToggleLetterBox.title = (ud.integer(forKey: kUDKeyLetterBoxMode) == Int(kPMLetterBoxModeNotDisplay))
			? kMPXStringMenuShowLetterBox : kMPXStringMenuHideLetterBox

		menuToggleFullScreen.isEnabled = false
		menuToggleFullScreen.title = kMPXStringMenuEnterFullscrn

		menuToggleFillScreen.isEnabled = false

		toggleAcceButton.tag = 0

		menuToggleAuxiliaryCtrls.tag = 0
		menuToggleAuxiliaryCtrls.title = kMPXStringMenuShowAuxCtrls
		menuToggleAuxiliaryCtrls.isEnabled = false

		//////ibtool bug fix, set noborder////////
		volumeButton.isBordered = false
		nextEPButton.isBordered = false
		prevEPButton.isBordered = false
		playPauseButton.isBordered = false
		fillScreenButton.isBordered = false
		fullScreenButton.isBordered = false
		toggleAcceButton.isBordered = false
		timeText.isBordered = false
		timeTextAlt.isBordered = false
		timeDispSwitch.isBordered = false

		// set OSD active status
		osd.active = false

		notifCenter.addObserver(self, selector: #selector(windowHasResized(_:)),
								name: NSWindow.didResizeNotification, object: window)

		notifCenter.addObserver(self, selector: #selector(playBackOpened(_:)),
								name: .mpcPlayOpened, object: playerController)
		notifCenter.addObserver(self, selector: #selector(playBackStarted(_:)),
								name: .mpcPlayStarted, object: playerController)
		notifCenter.addObserver(self, selector: #selector(playBackWillStop(_:)),
								name: .mpcPlayWillStop, object: playerController)
		notifCenter.addObserver(self, selector: #selector(playBackStopped(_:)),
								name: .mpcPlayStopped, object: playerController)

		notifCenter.addObserver(self, selector: #selector(playInfoUpdated(_:)),
								name: .mpcPlayInfoUpdated, object: playerController)

		// this functioin must be called after the Notification is setuped
		playerController.setupKVO()

		// force hide titlebar
		title.alphaValue = ud.bool(forKey: kUDKeyHideTitlebar) ? 0 : CONTROLALPHA
	}

	deinit {
		notifCenter.removeObserver(self)
		autoHideTimer?.invalidate()

		menuSwitchSub?.submenu = nil
		menuSwitchAudio?.submenu = nil
		menuSwitchVideo?.submenu = nil
		menuChapterList?.submenu = nil
	}

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
	override var acceptsFirstResponder: Bool { true }

	@objc func refreshBackgroundAlpha() {
		let backAlpha = CGFloat(ud.float(forKey: kUDKeyCtrlUIBackGroundAlpha))

		fillGradient = NSGradient(colorsAndLocations:
			(NSColor(deviceWhite: 0.220, alpha: backAlpha), 0.00),
			(NSColor(deviceWhite: 0.150, alpha: backAlpha), 0.30),
			(NSColor(deviceWhite: 0.090, alpha: backAlpha), 0.33),
			(NSColor(deviceWhite: 0.050, alpha: backAlpha), 1.00))
		backGroundColor = NSColor(deviceWhite: 0.45, alpha: backAlpha)
		backGroundColor2 = NSColor(deviceWhite: 0.32, alpha: backAlpha)

		needsDisplay = true
	}

	@objc func refreshOSDSetting() {
		let new = ud.bool(forKey: kUDKeyShowOSD)
		if new {
			// if showing OSD, then get the new value
			osd.setAutoHideTimeInterval(ud.double(forKey: kUDKeyOSDAutoHideTime))
			if let data = ud.object(forKey: kUDKeyOSDFrontColor) as? Data {
				osd.frontColor = NSUnarchiver.unarchiveObject(with: data) as? NSColor
			}
			// and force-show OSD, but this may not match the OSD's current state
			osd.active = true
			osd.setStringValue(kMPXStringOSDSettingChanged, owner: .other, updateTimer: true)
		}
		if playerController.couldAcceptCommand() {
			// if currently playing, then set it to show
			// if not playing, osd's active state will be force-set to OFF, so it cannot be set here
			// the active state will be set again when playback starts
			osd.active = new
		}
	}

	/// Transient, user-triggered feedback ("this is already the last episode",
	/// "next/previous only works on local media") used to come up as an
	/// app-modal NSAlert. That panel is small, untitled and easy to miss on top
	/// of a playing video, and until it is dismissed it swallows *every*
	/// subsequent key press -- almost certainly the long-standing "the space
	/// bar / `,` / `.` sometimes stop working" reports. Messages like these
	/// belong on the OSD instead.
	///
	/// Forced visible even when the OSD is currently inactive (playback stopped,
	/// or the "Show OSD" preference is off): this is a direct answer to a key
	/// the user just pressed, so silently dropping it would leave them with no
	/// feedback at all. The previous active state is restored afterwards, since
	/// hiding is driven by the auto-hide timer, not by `active`.
	@objc func displayOSDMessage(_ message: String) {
		let oldAct = osd.active
		osd.active = true
		osd.setStringValue(message, owner: .other, updateTimer: true)
		osd.active = oldAct
	}

	////////////////////////////////////////////////AutoHideThings//////////////////////////////////////////////////
	@objc func refreshAutoHideTimer() {
		let ti = ud.double(forKey: kUDKeyCtrlUIAutoHideTime)

		if ti != autoHideTimeInterval, ti > 0 {
			autoHideTimer?.invalidate()
			autoHideTimer = nil

			autoHideTimeInterval = ti
			let timer = Timer(timeInterval: autoHideTimeInterval / 2,
							  target: self,
							  selector: #selector(tryToHide),
							  userInfo: nil,
							  repeats: true)
			autoHideTimer = timer
			RunLoop.main.add(timer, forMode: .default)
		}
	}

	@objc func doHide() {
		// this code must not be reentered, otherwise it will keep calling hidecursor
		guard alphaValue > (CONTROLALPHA - 0.05) else { return }

		// get the mouse coordinates in this window
		let pos = window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? .zero

		// if not within this View, then hide itself
		// if HideTitlebar is ON, ignore the titlebar area when hiding the cursor
		if !NSPointInRect(convert(pos, from: nil), bounds),
		   !NSPointInRect(title.convert(pos, from: nil), title.bounds) || ud.bool(forKey: kUDKeyHideTitlebar) {
			animator().alphaValue = 0

			// also hide the mouse if in fullscreen mode
			if dispView.isInFullScreenMode {
				// [self window] here is not the member window, but self's new window after entering fullscreen
				if window?.isKeyWindow ?? false, NSPointInRect(NSEvent.mouseLocation, window?.frame ?? .zero) {
					// if it is not the key window, do not hide the mouse
					NSCursor.hide()
				}
			} else {
				// if not fullscreen, hide the resizeindicator
				// if fullscreen, leave it alone
				rzIndicator.animator().alphaValue = 0
				// this should check kUDKeyHideTitlebar, but since we are hiding the title here anyway
				// setting AlphaValue to 0 multiple times will not cause any harm
				title.animator().alphaValue = 0
			}
		}
	}

	@objc private func tryToHide() {
		if shouldHide {
			doHide()
		} else {
			shouldHide = true
		}
	}

	@objc func showUp() {
		shouldHide = false

		animator().alphaValue = CONTROLALPHA

		if dispView.isInFullScreenMode {
			// also show the mouse in fullscreen mode
			NSCursor.unhide()
		} else {
			// if not fullscreen mode, show the resizeindicator
			// leave it alone in fullscreen
			rzIndicator.animator().alphaValue = CONTROLALPHA

			if !ud.bool(forKey: kUDKeyHideTitlebar) {
				// if kUDKeyHideTitlebar is OFF, go to display the titlebar
				title.animator().alphaValue = CONTROLALPHA
			}
		}
	}

	////////////////////////////////////////////////Actions//////////////////////////////////////////////////
	@IBAction func togglePlayPause(_ sender: Any?) {
		playerController.togglePlayPause()

		let osdStr: String

		switch playerController.playerState() {
		case Int32(kMPCStoppedState):
			// stopped state
			playBackStopped(nil)
			osdStr = kMPXStringOSDPlaybackStopped
		case Int32(kMPCPausedState):
			// paused state
			dispView.setPlayerWindowLevel()
			playPauseButton.state = PauseState
			osdStr = kMPXStringOSDPlaybackPaused
		case Int32(kMPCPlayingState):
			// playing state
			dispView.setPlayerWindowLevel()
			playPauseButton.state = PlayState
			osdStr = kMPXStringOSDNull
		default:
			osdStr = kMPXStringOSDNull
		}
		osd.setStringValue(osdStr, owner: .other, updateTimer: true)
	}

	@IBAction func toggleMute(_ sender: Any?) {
		let mute = playerController.toggleMute()

		// set buttons and menu status
		volumeButton.state = mute ? .on : .off
		volumeSlider.isEnabled = !mute
		menuVolInc.isEnabled = !mute
		menuVolDec.isEnabled = !mute

		// update OSD
		osd.setStringValue(mute ? kMPXStringOSDMuteON : kMPXStringOSDMuteOFF,
						   owner: .other, updateTimer: true)
	}

	@IBAction func setVolume(_ sender: Any?) {
		guard volumeSlider.isEnabled else { return }

		// floatValue must be obtained from sender here, not directly from volumeSlider
		// because it could be a keyboard shortcut, in which case ShortCutManager sends an NSNumber as the sender
		let vol = playerController.setVolume(senderFloatValue(sender))

		// update buttons status
		volumeSlider.floatValue = vol

		let maxVal = volumeSlider.maxValue
		let now = Int((Double(vol) * Double(NUMOFVOLUMEIMAGES) + maxVal - 1) / maxVal)
		if now >= 0, now < volumeButtonImages.count {
			volumeButton.image = volumeButtonImages[now]
		}

		// store the volume in UserDefaults
		ud.set(vol, forKey: kUDKeyVolume)

		// update OSD
		osd.setStringValue(String(format: kMPXStringOSDVolumeHint, vol),
						   owner: .other, updateTimer: true)
	}

	@IBAction func changeVolumeBy(_ sender: Any?) {
		let delta: Float = (sender is NSMenuItem)
			? Float(senderTag(sender))
			: senderFloatValue(sender)

		setVolume(NSNumber(value: volumeSlider.floatValue + (delta * volStep)))
	}

	@IBAction func seekTo(_ sender: Any?) {
		var sender = sender

		if let item = sender as? NSMenuItem {
			// action from menu
			sender = NSNumber(value: max(0, (Float(item.tag) / Float(LASTSTOPPEDTIMERATIO)) - 5))
		}

		// when dragging, use absolute seeking
		let dragging = (timeSlider.cell as? TimeSliderCell)?.isDragging ?? false
		let time = playerController.seekTo(senderFloatValue(sender),
										   mode: dragging ? kMPCSeekModeAbsolute : kMPCSeekModeRelative)

		updateHintTime()

		if osd.active, time > 0 {
			var osdStr = timeFormatter.string(for: NSNumber(value: time)) ?? ""
			let length = timeSlider.maxValue

			if length > 0 {
				osdStr += String(format: kStringFMTTimeAppendTotal, timeFormatter.string(for: NSNumber(value: length)) ?? "")
			}
			osd.setStringValue(osdStr, owner: .time, updateTimer: true)
		}
	}

	@objc(changeTimeBy:)
	func changeTime(by delta: Float) {
		let newDelta = playerController.changeTimeBy(delta)

		if osd.active, newDelta > 0 {
			var osdStr = timeFormatter.string(for: NSNumber(value: newDelta)) ?? ""
			let length = timeSlider.maxValue

			if length > 0 {
				osdStr += String(format: kStringFMTTimeAppendTotal, timeFormatter.string(for: NSNumber(value: length)) ?? "")
			}
			osd.setStringValue(osdStr, owner: .time, updateTimer: true)
		}
	}

	@IBAction func toggleFullScreen(_ sender: Any?) {
		if dispView.toggleFullScreen() {
			// succeeded
			if dispView.isInFullScreenMode {
				// entering fullscreen

				fullScreenButton.state = .on
				menuToggleFullScreen.title = kMPXStringMenuExitFullscrn

				// setting fillScreenButton's Image and the like,
				// is implemented in RootLayerView, because setting this needs quite a few parameters
				// which would make the interface look ugly
				fillScreenButton.isHidden = false
				menuToggleFillScreen.isEnabled = true

				// if self has already been hidden, then hide the mouse too
				if alphaValue < (CONTROLALPHA - 0.05) {
					NSCursor.hide()
				}

				// entering fullscreen, force-hide the resizeindicator
				rzIndicator.alphaValue = 0
				// this should check kUDKeyHideTitlebar, but since we are hiding the title here anyway
				// setting AlphaValue to 0 multiple times will not cause any harm
				title.alphaValue = 0

				menuToggleLockAspectRatio.title = dispView.lockAspectRatio ? kMPXStringMenuUnlockAspectRatio : kMPXStringMenuLockAspectRatio
				menuToggleLockAspectRatio.isEnabled = false

				menuEnlargeFrame.isEnabled = true
				menuShrinkFrame.isEnabled = true
				menuEnlargeFrame2.isEnabled = true
				menuShrinkFrame2.isEnabled = true
				menuWndFitToScrn.isEnabled = false

				if ud.bool(forKey: kUDKeyLBAutoHeightInFullScrn) {
					applyAutoLetterBoxHeightInFullScreen()
				}

				if ud.bool(forKey: kUDKeyPlayWhenEnterFullScrn), playerController.playerState() == Int32(kMPCPausedState) {
					togglePlayPause(nil)
				}
			} else {
				// exiting fullscreen
				NSCursor.unhide()

				fullScreenButton.state = .off
				menuToggleFullScreen.title = kMPXStringMenuEnterFullscrn

				fillScreenButton.isHidden = true
				menuToggleFillScreen.isEnabled = false

				if alphaValue > (CONTROLALPHA - 0.05) {
					// if controlUI is not hidden, show the resizeindicator
					rzIndicator.animator().alphaValue = CONTROLALPHA

					if !ud.bool(forKey: kUDKeyHideTitlebar) {
						// if kUDKeyHideTitlebar is OFF, go to display the titlebar
						title.animator().alphaValue = CONTROLALPHA
					}
				}
				menuToggleLockAspectRatio.isEnabled = true

				menuEnlargeFrame.isEnabled = false
				menuShrinkFrame.isEnabled = false
				menuEnlargeFrame2.isEnabled = false
				menuShrinkFrame2.isEnabled = false
				menuWndFitToScrn.isEnabled = true

				if ud.bool(forKey: kUDKeyLBAutoHeightInFullScrn) {
					toggleLetterBox(nil)
				}
			}
		} else {
			// failed
			fullScreenButton.state = .off
			menuToggleFullScreen.title = kMPXStringMenuEnterFullscrn

			fillScreenButton.isHidden = true
			menuToggleFillScreen.isEnabled = false

			menuToggleLockAspectRatio.isEnabled = false

			menuEnlargeFrame.isEnabled = false
			menuShrinkFrame.isEnabled = false
			menuEnlargeFrame2.isEnabled = false
			menuShrinkFrame2.isEnabled = false
			menuWndFitToScrn.isEnabled = false
		}
		windowHasResized(nil)
	}

	/// Split out of toggleFullScreen: only to keep that method readable; the
	/// logic is the original's kUDKeyLBAutoHeightInFullScrn branch verbatim.
	private func applyAutoLetterBoxHeightInFullScreen() {
		let lb = ud.integer(forKey: kUDKeyLetterBoxMode)
		let height = CGFloat(ud.float(forKey: kUDKeyLetterBoxHeight))

		let scrnSize = dispView.window?.screen?.frame.size ?? .zero
		guard scrnSize.width > 0 else { return }

		let ar = dispView.aspectRatio
		var margin: CGFloat

		switch lb {
		case Int(kPMLetterBoxModeBoth):
			margin = ((scrnSize.height * (1 + height * 2) * ar / scrnSize.width) - 1) / 2
			MPLogString("AutoLBH, AR:\(ar), margin:\(margin)")
			if margin > 0 {
				playerController.setLetterBox(true, top: Float(margin), bottom: Float(margin))
			}
		case Int(kPMLetterBoxModeBottomOnly):
			margin = (scrnSize.height * (1 + height) * ar / scrnSize.width) - 1
			MPLogString("AutoLBH, AR:\(ar), margin:\(margin)")
			if margin > 0 {
				playerController.setLetterBox(true, top: -1.0, bottom: Float(margin))
			}
		case Int(kPMLetterBoxModeTopOnly):
			margin = (scrnSize.height * (1 + height) * ar / scrnSize.width) - 1
			MPLogString("AutoLBH, AR:\(ar), margin:\(margin)")
			if margin > 0 {
				playerController.setLetterBox(true, top: Float(margin), bottom: -1.0)
			}
		default:
			margin = (scrnSize.height * ar / scrnSize.width) - 1
			MPLogString("AutoLBH, AR:\(ar), margin:\(margin)")
			if margin > 0 {
				let lbAlt = ud.integer(forKey: kUDKeyLetterBoxModeAlt)

				switch lbAlt {
				case Int(kPMLetterBoxModeBoth):
					margin /= 2
					playerController.setLetterBox(true, top: Float(margin), bottom: Float(margin))
				case Int(kPMLetterBoxModeBottomOnly):
					playerController.setLetterBox(true, top: -1.0, bottom: Float(margin))
				case Int(kPMLetterBoxModeTopOnly):
					playerController.setLetterBox(true, top: Float(margin), bottom: -1.0)
				default:
					break
				}
			}
		}
	}

	@IBAction func toggleFillScreen(_ sender: Any?) {
		if sender != nil || fillScreenButton.state == .on {
			// if sender is nil
			// that means it is an internal reset signal, and whether to trigger toggle is decided by the button's state
			let status = dispView.toggleFillScreen()
			if status {
				fillScreenButton.state = .on
				menuToggleFillScreen.state = .on
			} else {
				fillScreenButton.state = .off
				menuToggleFillScreen.state = .off
			}
		}
	}

	@IBAction func toggleAccessaryControls(_ sender: Any?) {
		var rcSelf = frame
		let delta = accessaryContainer.frame.size.height - 10
		var rcAcc = accessaryContainer.frame

		if senderTag(sender) == 0 {
			// to show
			rcSelf.size.height = orgHeight + delta
			rcSelf.origin.y -= min(rcSelf.origin.y, delta)

			animator().frame = rcSelf

			rcAcc.origin.y = 0
			rcAcc.origin.x = (rcSelf.size.width - rcAcc.size.width) / 2
			accessaryContainer.setFrameOrigin(rcAcc.origin)

			accessaryContainer.animator().isHidden = false

			menuToggleAuxiliaryCtrls.title = kMPXStringMenuHideAuxCtrls
			menuToggleAuxiliaryCtrls.tag = 1
			toggleAcceButton.state = .on
			toggleAcceButton.tag = 1

		} else {
			accessaryContainer.animator().isHidden = true

			rcSelf.size.height = orgHeight
			rcSelf.origin.y += delta

			animator().frame = rcSelf

			rcAcc.origin.y = 0
			rcAcc.origin.x = (rcSelf.size.width - rcAcc.size.width) / 2
			accessaryContainer.setFrameOrigin(rcAcc.origin)

			menuToggleAuxiliaryCtrls.title = kMPXStringMenuShowAuxCtrls
			menuToggleAuxiliaryCtrls.tag = 0
			toggleAcceButton.state = .off
			toggleAcceButton.tag = 0
		}
		hintTime.animator().alphaValue = 0
	}

	@IBAction func changeSpeed(_ sender: Any?) {
		if let item = sender as? NSMenuItem {
			// from changespeed menu
			if item.tag != 0 {
				// if not zero, means not reset
				_ = playerController.changeSpeedBy(Float(item.tag) * ud.float(forKey: kUDKeySpeedStep))
			} else {
				// if zero, reset
				_ = playerController.setSpeed(1)
			}
		} else {
			// from textfield
			_ = playerController.setSpeed(senderFloatValue(sender))
		}
	}

	@IBAction func changeAudioDelay(_ sender: Any?) {
		if let item = sender as? NSMenuItem {
			if item.tag != 0 {
				_ = playerController.changeAudioDelayBy(Float(item.tag) * ud.float(forKey: kUDKeyAudioDelayStepTime))
			} else {
				_ = playerController.setAudioDelay(0)
			}
		} else {
			_ = playerController.setAudioDelay(senderFloatValue(sender))
		}
	}

	@IBAction func changeSubDelay(_ sender: Any?) {
		if let item = sender as? NSMenuItem {
			if item.tag != 0 {
				_ = playerController.changeSubDelayBy(Float(item.tag) * ud.float(forKey: kUDKeySubDelayStepTime))
			} else {
				_ = playerController.setSubDelay(0)
			}
		} else {
			_ = playerController.setSubDelay(senderFloatValue(sender))
		}
	}

	@IBAction func changeSubScale(_ sender: Any?) {
		let tag = senderTag(sender)
		_ = playerController.changeSubScaleBy(Float(tag) * ud.float(forKey: kUDKeySubScaleStepValue))
	}

	@IBAction func stepSubtitles(_ sender: Any?) {
		var selectedTag = -2

		// find the currently selected subtitle
		for mItem in subListMenu.items where mItem.state == .on && !mItem.isSeparatorItem {
			selectedTag = mItem.tag
			break
		}
		// get the next subtitle's tag
		// if no menu item is selected, then select "hide subtitles"
		selectedTag += 1

		var item = subListMenu.item(withTag: selectedTag)
		if item == nil {
			// if it is the last subtitle item, then wrap around to the "hide subtitles" menu item
			item = subListMenu.item(withTag: -1)
		}
		setSubWithID(item)
	}

	@IBAction func setSubWithID(_ sender: Any?) {
		guard let sender = sender as? NSMenuItem else { return }

		playerController.setSubtitle(Int32(sender.tag))

		for mItem in subListMenu.items where mItem.state == .on && !mItem.isSeparatorItem {
			mItem.state = .off
			break
		}
		sender.state = .on

		osd.setStringValue(String(format: kMPXStringOSDSubtitleHint, sender.title),
						   owner: .other, updateTimer: true)
	}

	@IBAction func stepAudios(_ sender: Any?) {
		let num = audioListMenu.numberOfItems
		guard num > 0 else { return }

		var idx = 0
		var found = 0

		for mItem in audioListMenu.items {
			if mItem.state == .on {
				found = idx + 1
				break
			}
			idx += 1
		}
		if found >= num {
			found = 0
		}
		setAudioWithID(audioListMenu.item(at: found))
	}

	@IBAction func setAudioWithID(_ sender: Any?) {
		guard let sender = sender as? NSMenuItem else { return }

		playerController.setAudio(Int32(sender.tag))

		// This is a hack
		// since I have to reset the volume when switch audio
		// so I should disable OSD when set volume
		let oldAct = osd.active
		osd.active = false
		// this might be an mplayer bug -- when cycling all the way around through the audio tracks to silent and back to a track, the volume jumps to max, so set the volume again here
		setVolume(volumeSlider)
		osd.active = oldAct

		for mItem in audioListMenu.items where mItem.state == .on {
			mItem.state = .off
			break
		}
		sender.state = .on

		osd.setStringValue(String(format: kMPXStringOSDAudioHint, sender.title),
						   owner: .other, updateTimer: true)
	}

	@IBAction func stepVideos(_ sender: Any?) {
		let num = videoListMenu.numberOfItems
		guard num > 0 else { return }

		var idx = 0
		var found = 0

		for mItem in videoListMenu.items {
			if mItem.state == .on {
				found = idx + 1
				break
			}
			idx += 1
		}
		if found >= num {
			found = 0
		}
		setVideoWithID(videoListMenu.item(at: found))
	}

	@IBAction func setVideoWithID(_ sender: Any?) {
		guard let sender = sender as? NSMenuItem else { return }

		playerController.setVideo(Int32(sender.tag))

		for mItem in videoListMenu.items where mItem.state == .on {
			mItem.state = .off
			break
		}
		sender.state = .on

		osd.setStringValue(String(format: kMPXStringOSDVideoHint, sender.title),
						   owner: .other, updateTimer: true)
	}

	@IBAction func setChapterWithTime(_ sender: Any?) {
		guard let sender = sender as? NSMenuItem else { return }

		_ = playerController.seekTo(Float(sender.tag) / Float(kMPCChapterTimeBase), mode: kMPCSeekModeRelative)

		updateHintTime()

		osd.setStringValue(String(format: kMPXStringOSDChapterHint, (sender.representedObject as? String) ?? ""),
						   owner: .other, updateTimer: true)
	}

	@IBAction func changeSubPosBy(_ sender: Any?) {
		if let num = sender as? NSNumber {
			// if it is an NSNumber, that means it did not come from Target-Action
			_ = playerController.changeSubPosBy(num.floatValue)
		}
	}

	@IBAction func changeAudioBalanceBy(_ sender: Any?) {
		if sender != nil {
			if let num = sender as? NSNumber {
				// if it is an NSNumber, that means it did not come from Target-Action
				_ = playerController.changeAudioBalanceBy(num.floatValue)
			}
		} else {
			// nil means the intent is to restore
			playerController.setAudioBalance(0)
		}
	}

	@IBAction func toggleLockAspectRatio(_ sender: Any?) {
		dispView.setLockAspectRatio(!dispView.lockAspectRatio)

		let lock = dispView.lockAspectRatio
		menuToggleLockAspectRatio.title = lock ? kMPXStringMenuUnlockAspectRatio : kMPXStringMenuLockAspectRatio

		osd.setStringValue(lock ? kMPXStringOSDAspectRatioLocked : kMPXStringOSDAspectRatioUnLocked,
						   owner: .other, updateTimer: true)
	}

	@IBAction func resetAspectRatio(_ sender: Any?) {
		dispView.resetAspectRatio()
		menuToggleLockAspectRatio.title = dispView.lockAspectRatio ? kMPXStringMenuUnlockAspectRatio : kMPXStringMenuLockAspectRatio

		osd.setStringValue(kMPXStringOSDAspectRatioReset, owner: .other, updateTimer: true)
	}

	@IBAction func setAspectRatio(_ sender: Any?) {
		let tag = senderTag(sender)
		dispView.setAspectRatio(CGFloat(tag) / ASPECTRATIOBASE)
	}

	@IBAction func toggleLetterBox(_ sender: Any?) {
		var lbMode = ud.integer(forKey: kUDKeyLetterBoxMode)

		if sender != nil {
			// means the event was triggered from the menu
			// if it is nil, it means the event was triggered internally, so just update the menu state
			if lbMode == Int(kPMLetterBoxModeNotDisplay) {
				// not currently showing
				lbMode = ud.integer(forKey: kUDKeyLetterBoxModeAlt)
				ud.set(lbMode, forKey: kUDKeyLetterBoxMode)
			} else {
				// currently showing
				lbMode = Int(kPMLetterBoxModeNotDisplay)
				ud.set(lbMode, forKey: kUDKeyLetterBoxMode)
			}
		}

		// not in the fullscreen mode
		let margin = ud.float(forKey: kUDKeyLetterBoxHeight)

		switch lbMode {
		case Int(kPMLetterBoxModeBoth):
			menuToggleLetterBox.title = kMPXStringMenuHideLetterBox
			playerController.setLetterBox(true, top: margin, bottom: margin)
		case Int(kPMLetterBoxModeBottomOnly):
			menuToggleLetterBox.title = kMPXStringMenuHideLetterBox
			playerController.setLetterBox(true, top: -1.0, bottom: margin)
		case Int(kPMLetterBoxModeTopOnly):
			menuToggleLetterBox.title = kMPXStringMenuHideLetterBox
			playerController.setLetterBox(true, top: margin, bottom: -1.0)
		default:
			menuToggleLetterBox.title = kMPXStringMenuShowLetterBox
			playerController.setLetterBox(false, top: -1.0, bottom: -1.0)
		}
	}

	@IBAction func stepWindowSize(_ sender: Any?) {
		if let item = sender as? NSMenuItem {
			let step = CGFloat(Float(item.tag) * ud.float(forKey: kUDKeyResizeStep))

			dispView.changeWindowSize(by: NSSize(width: step, height: step), animate: true)
		}
	}

	@IBAction func moveFrameToCenter(_ sender: Any?) {
		dispView.moveFrameToCenter()
	}

	@IBAction func resetFrameScaleRatio(_ sender: Any?) {
		dispView.resetFrameScaleRatio()
	}

	@IBAction func stepFrameScale(_ sender: Any?) {
		let tag = senderTag(sender)
		let w = CGFloat(Float(tag) * ud.float(forKey: kUDKeyFrameScaleStep))

		dispView.changeFrameScaleRatio(by: CGSize(width: w, height: w))
	}

	@IBAction func toggleMirror(_ sender: Any?) {
		dispView.setMirror(!dispView.mirror)

		menuMirror.state = dispView.mirror ? .on : .off
	}

	@IBAction func toggleFlip(_ sender: Any?) {
		dispView.setFlip(!dispView.flip)

		menuFlip.state = dispView.flip ? .on : .off
	}

	@IBAction func zoomToSize(_ sender: Any?) {
		let tag = senderTag(sender)
		dispView.zoomToSize(Float(tag) / 4)
	}

	@IBAction func toggleTimeAltDisplayMode(_ sender: Any?) {
		ud.set(!ud.bool(forKey: kUDKeyTimeTextAltTotal), forKey: kUDKeyTimeTextAltTotal)
	}

	@IBAction func mapAudioChannelsTo(_ sender: Any?) {
		guard let sender = sender as? NSMenuItem else { return }

		playerController.mapAudioChannelsTo(sender.tag)

		for mitem in menuAudioChannels.submenu?.items ?? [] where mitem.state == .on && !mitem.isSeparatorItem {
			mitem.state = .off
			break
		}
		sender.state = .on
	}

	////////////////////////////////////////////////FullscreenThings//////////////////////////////////////////////////
	@objc(setFillScreenMode:state:)
	func setFillScreenMode(_ modeKey: String, state: Int) {
		if let fillScrnBtnModeImages = fillScreenButtonAllImages[modeKey] {
			fillScreenButton.image = fillScrnBtnModeImages[0]
			fillScreenButton.alternateImage = fillScrnBtnModeImages[1]
		}
		fillScreenButton.state = NSControl.StateValue(rawValue: state)
	}

	////////////////////////////////////////////////displayThings//////////////////////////////////////////////////
	@objc func displayStarted() {
		fullScreenButton.isHidden = false

		menuToggleFullScreen.isEnabled = true
		menuSnapshot.isEnabled = true
		if !dispView.isInFullScreenMode {
			menuToggleLockAspectRatio.isEnabled = true
			menuWndFitToScrn.isEnabled = true
		}
		menuToggleLockAspectRatio.title = dispView.lockAspectRatio ? kMPXStringMenuUnlockAspectRatio : kMPXStringMenuLockAspectRatio
		menuZoomToHalfSize.isEnabled = true
		menuZoomToOriginSize.isEnabled = true
		menuZoomToDoubleSize.isEnabled = true
	}

	@objc func displayStopped() {
		fullScreenButton.isHidden = true

		menuToggleFullScreen.isEnabled = false
		menuSnapshot.isEnabled = false
		menuToggleLockAspectRatio.isEnabled = false
		menuZoomToHalfSize.isEnabled = false
		menuZoomToOriginSize.isEnabled = false
		menuZoomToDoubleSize.isEnabled = false
		menuWndFitToScrn.isEnabled = false
	}

	////////////////////////////////////////////////playback//////////////////////////////////////////////////
	@objc private func playBackOpened(_ notif: Notification) {
		osd.active = ud.bool(forKey: kUDKeyShowOSD)

		if let stopTime = notif.userInfo?[kMPCPlayLastStoppedTimeKey] as? NSNumber {
			menuPlayFromLastStoppedPlace.tag = stopTime.intValue * LASTSTOPPEDTIMERATIO
			menuPlayFromLastStoppedPlace.isEnabled = true
		} else {
			menuPlayFromLastStoppedPlace.isEnabled = false
		}
	}

	@objc private func playBackStarted(_ notif: Notification) {
		playPauseButton.state = (playerController.playerState() == Int32(kMPCPlayingState)) ? PlayState : PauseState

		speedText.isEnabled = true
		audioDelayText.isEnabled = true

		menuSwitchAudio.isEnabled = true
		menuSwitchVideo.isEnabled = true

		menuToggleAuxiliaryCtrls.isEnabled = true

		menuSpeedUp.isEnabled = true
		menuSpeedDown.isEnabled = true
		menuAudioDelayInc.isEnabled = true
		menuAudioDelayDec.isEnabled = true

		if playerController.isPassingThrough() {
			volumeButton.isEnabled = false
			volumeSlider.isEnabled = false
			menuVolInc.isEnabled = false
			menuVolDec.isEnabled = false
		} else {
			menuAudioChannels.isEnabled = true
			for mitem in menuAudioChannels.submenu?.items ?? [] {
				mitem.state = (mitem.tag == Int(kMPCMonoAudioNone)) ? .on : .off
				// The submenu is autoenablesItems="NO", so nothing enables these
				// but this. Only the parent item's enabled state was ever
				// managed, which left every channel mapping permanently greyed
				// out -- the whole Audio > Channels feature was unreachable.
				mitem.isEnabled = !mitem.isSeparatorItem
			}
			// if it is a DD setting, ParameterManager will not set the volume.
			// but if the file ends up not playing as DD, the volume needs to be set again
			// and do not show the OSD
			let oldAct = osd.active
			osd.active = false
			// this might be an mplayer bug -- when cycling all the way around through the audio tracks to silent and back to a track, the volume jumps to max, so set the volume again here
			setVolume(volumeSlider)
			osd.active = oldAct
		}

		showUp()
	}

	@objc private func playBackWillStop(_ notif: Notification) {
		osd.setStringValue("", owner: .other, updateTimer: true)
		osd.active = false
	}

	/** this API is called at two points in time,
	 * 1. when mplayer playback ends, whether forced or natural
	 * 2. when mplayer playback fails */
	@objc private func playBackStopped(_ notif: Notification?) {
		playPauseButton.state = PauseState

		timeText.stringValue = ""
		timeTextAlt.stringValue = ""
		timeSlider.floatValue = -1

		// since mplayer cannot start muted, we must always return to the unmuted state
		volumeButton.state = .off
		volumeButton.isEnabled = true
		volumeSlider.isEnabled = true
		menuVolInc.isEnabled = true
		menuVolDec.isEnabled = true

		speedText.isEnabled = false
		subDelayText.isEnabled = false
		audioDelayText.isEnabled = false

		menuSwitchAudio.isEnabled = false
		menuSwitchSub.isEnabled = false
		menuSwitchVideo.isEnabled = false

		menuSubScaleInc.isEnabled = false
		menuSubScaleDec.isEnabled = false
		menuPlayFromLastStoppedPlace.isEnabled = false

		menuSpeedUp.isEnabled = false
		menuSpeedDown.isEnabled = false
		menuAudioDelayInc.isEnabled = false
		menuAudioDelayDec.isEnabled = false
		menuSubDelayInc.isEnabled = false
		menuSubDelayDec.isEnabled = false

		menuAudioChannels.isEnabled = false
		for mitem in menuAudioChannels.submenu?.items ?? [] {
			mitem.isEnabled = false
		}
	}

	@objc private func playInfoUpdated(_ notif: Notification) {
		guard let userInfo = notif.userInfo,
			  let keyPath = userInfo[kMPCPlayInfoUpdatedKeyPathKey] as? String
		else { return }

		// The change dictionary travelled through NSNotification's userInfo, so
		// it comes back bridged as an NSDictionary. Read it as [AnyHashable: Any]
		// and look each key up both as NSKeyValueChangeKey and as its raw string:
		// casting straight to [NSKeyValueChangeKey: Any] silently fails, which is
		// how the whole time/length/speed display ended up frozen the first time.
		let change = userInfo[kMPCPlayInfoUpdatedChangeDictKey] as? [AnyHashable: Any] ?? [:]

		func changeValue(_ key: NSKeyValueChangeKey) -> Any? {
			change[key] ?? change[key.rawValue]
		}

		let newValue = changeValue(.newKey)

		switch keyPath {
		case kKVOPropertyKeyPathCurrentTime:
			// get the current playback time
			gotCurentTime(kvoNumber(newValue))

		case kKVOPropertyKeyPathSpeed:
			// get the playback speed
			gotSpeed(kvoNumber(newValue))

		case kKVOPropertyKeyPathSubDelay:
			// get the subtitle delay
			gotSubDelay(kvoNumber(newValue))

		case kKVOPropertyKeyPathAudioDelay:
			// get the audio delay
			gotAudioDelay(kvoNumber(newValue))

		case kKVOPropertyKeyPathLength:
			// get the media file's length
			gotMediaLength(kvoNumber(newValue))

		case kKVOPropertyKeyPathSeekable:
			// get whether seeking is possible
			gotSeekableState(kvoNumber(newValue))

		case kKVOPropertyKeyPathCachingPercent:
			// get the current caching percent
			gotCachingPercent(kvoNumber(newValue))

		case kKVOPropertyKeyPathSubInfo:
			// get the subtitle info
			gotSubInfo(kvoArray(newValue),
					   changed: kvoNumber(changeValue(.kindKey))?.uintValue ?? 0)

		case kKVOPropertyKeyPathAudioInfo:
			// get the audio info
			gotAudioInfo(kvoArray(newValue))

		case kKVOPropertyKeyPathVideoInfo:
			// got the video info
			gotVideoInfo(kvoArray(newValue))

		case kKVOPropertyKeyPathChapterInfo:
			// got chapter info
			gotChapterInfo(kvoArray(newValue))

		default:
			break
		}
	}

	/// Make a time readout use tabular (fixed-width) figures.
	///
	/// The system font's digits are proportional: "-00:04:58" is 54.2pt wide while
	/// "-00:04:57" is only 53.4pt, so a readout that is just wide enough for one
	/// value gets tail-truncated to "-00:04:…" on the next second. Tabular figures
	/// give every digit the same advance, so the width no longer depends on which
	/// digits happen to be showing (it also stops the text from jittering as the
	/// time ticks).
	private func useTabularFigures(_ field: NSTextField) {
		let size = field.font?.pointSize ?? NSFont.smallSystemFontSize
		field.font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
	}

	////////////////////////////////////////////////KVO for time//////////////////////////////////////////////////
	private func gotMediaLength(_ length: NSNumber?) {
		let len = length?.doubleValue ?? 0

		if len > 0 {
			timeSlider.maxValue = len
			timeSlider.minValue = 0
			if ud.bool(forKey: kUDKeyTimeTextAltTotal) {
				// diplay total time
				timeTextAlt.intValue = safeInt32(len + 0.5)
			} else {
				// display remain time
				timeTextAlt.intValue = safeInt32(-len - 0.5)
			}
		} else {
			timeSlider.isEnabled = false
			timeSlider.maxValue = 0
			timeSlider.minValue = -1
			hintTime.animator().alphaValue = 0
		}
	}

	private func gotCurentTime(_ timePos: NSNumber?) {
		let time = timePos?.doubleValue ?? 0
		let length = timeSlider.maxValue

		if length > 0 {
			if ud.bool(forKey: kUDKeyTimeTextAltTotal) {
				timeTextAlt.intValue = safeInt32(length + 0.5)
			} else {
				// display remaining time
				timeTextAlt.intValue = safeInt32(time - length - 0.5)
			}
		}

		timeText.intValue = safeInt32(time + 0.5)
		// the time can still be displayed even if timeSlider is disabled
		timeSlider.doubleValue = time

		if length > 0 {
			calculateHintTime()
		}

		if osd.active, time > 0 {
			var osdStr = timeFormatter.string(for: timePos) ?? ""

			if length > 0 {
				osdStr += String(format: kStringFMTTimeAppendTotal, timeFormatter.string(for: NSNumber(value: length)) ?? "")
			}
			osd.setStringValue(osdStr, owner: .time, updateTimer: false)
		}
	}

	private func gotSeekableState(_ seekable: NSNumber?) {
		timeSlider.isEnabled = seekable?.boolValue ?? false
	}

	private func gotSpeed(_ speed: NSNumber?) {
		let val = speed?.floatValue ?? 0
		speedText.floatValue = val

		osd.setStringValue(String(format: kMPXStringOSDSpeedHint, val), owner: .other, updateTimer: true)
	}

	private func gotSubDelay(_ sd: NSNumber?) {
		let val = sd?.floatValue ?? 0
		subDelayText.floatValue = val

		osd.setStringValue(String(format: kMPXStringOSDSubDelayHint, val), owner: .other, updateTimer: true)
	}

	private func gotAudioDelay(_ ad: NSNumber?) {
		let val = ad?.floatValue ?? 0
		audioDelayText.floatValue = val

		osd.setStringValue(String(format: kMPXStringOSDAudioDelayHint, val), owner: .other, updateTimer: true)
	}

	private func resetSubtitleMenu() {
		subListMenu.removeAllItems()

		// add a separator
		var mItem = NSMenuItem.separator()
		mItem.isEnabled = false
		mItem.tag = -2
		mItem.state = .off
		subListMenu.addItem(mItem)

		// add the "hide subtitles" menu item
		mItem = NSMenuItem()
		mItem.isEnabled = true
		mItem.target = self
		mItem.action = #selector(setSubWithID(_:))
		mItem.title = kMPXStringDisable
		mItem.tag = -1
		mItem.state = .off
		subListMenu.addItem(mItem)
	}

	private func gotSubInfo(_ subs: [Any]?, changed changeKind: UInt) {
		if changeKind == NSKeyValueChange.setting.rawValue {
			resetSubtitleMenu()
		}

		if let subs, !subs.isEmpty {
			var idx = subListMenu.numberOfItems - 2
			var mItem: NSMenuItem?

			// add all subtitle names to the menu
			for case let str as String in subs {
				let item = NSMenuItem()
				item.isEnabled = true
				item.target = self
				item.action = #selector(setSubWithID(_:))
				item.title = str
				item.tag = idx
				item.state = .off
				subListMenu.insertItem(item, at: idx)
				mItem = item
				idx += 1
			}

			if changeKind == NSKeyValueChange.setting.rawValue {
				// this place is only called when playback has just started and subs are loading, so it is safe
				// this branch is not entered when subs are cleared
				let currentSubID = playerController.mediaInfo()?.playingInfo.currentSubID?.intValue ?? 0
				subListMenu.item(withTag: currentSubID)?.state = .on
			} else {
				// this is called here when a sub is loaded midway through
				// activate this loaded sub by default
				setSubWithID(mItem)

				// this is a workaround, because if a subtitle is loaded while paused
				// since it cannot be loaded while staying paused, playback will start automatically
				// this would cause mplayer's state and MPX's state to become inconsistent; here we check MPX's state, and if it was loaded while paused, toggle it
				// the underlying command issued is pause -1, which has no side effect while playing -- it just resets MPX's state.
				if playerController.playerState() == Int32(kMPCPausedState) {
					togglePlayPause(nil)
				}
			}

			menuSwitchSub.isEnabled = true
			menuSubScaleInc.isEnabled = true
			menuSubScaleDec.isEnabled = true
			menuSubDelayInc.isEnabled = true
			menuSubDelayDec.isEnabled = true

			subDelayText.isEnabled = true

		} else if changeKind == NSKeyValueChange.setting.rawValue {
			menuSwitchSub.isEnabled = false
			menuSubScaleInc.isEnabled = false
			menuSubScaleDec.isEnabled = false
			menuSubDelayInc.isEnabled = false
			menuSubDelayDec.isEnabled = false

			subDelayText.isEnabled = false
		}
	}

	private func gotCachingPercent(_ caching: NSNumber?) {
		let win = window
		let percent = caching?.floatValue ?? 0

		if osd.active, percent > 0.01 {
			if !(win?.isVisible ?? false) {
				win?.makeKeyAndOrderFront(self)
			}

			osd.setStringValue(String(format: kMPXStringOSDCachingPercent, percent * 100),
							   owner: .other, updateTimer: true)
		}
	}

	private func resetAudioMenu() {
		audioListMenu.removeAllItems()
	}

	private func gotAudioInfo(_ ais: [Any]?) {
		audioListMenu.removeAllItems()

		if let ais, !ais.isEmpty {
			for case let info as AudioInfo in ais {
				let mItem = NSMenuItem()
				mItem.isEnabled = true
				mItem.target = self
				mItem.action = #selector(setAudioWithID(_:))
				mItem.title = info.description
				mItem.tag = Int(info.ID)
				mItem.state = .off
				audioListMenu.addItem(mItem)
			}

			audioListMenu.item(at: 0)?.state = .on

			menuSwitchAudio.isEnabled = true
		} else {
			menuSwitchAudio.isEnabled = false
		}
	}

	private func resetVideoMenu() {
		videoListMenu.removeAllItems()
	}

	private func gotVideoInfo(_ vis: [Any]?) {
		videoListMenu.removeAllItems()

		if let vis, !vis.isEmpty {
			for case let info as VideoInfo in vis {
				let mItem = NSMenuItem()
				mItem.isEnabled = true
				mItem.target = self
				mItem.action = #selector(setVideoWithID(_:))
				mItem.title = info.description
				mItem.tag = Int(info.ID)
				mItem.state = .off
				videoListMenu.addItem(mItem)
			}

			videoListMenu.item(at: 0)?.state = .on

			menuSwitchVideo.isEnabled = true
		} else {
			menuSwitchVideo.isEnabled = false
		}
	}

	private func resetChapterListMenu() {
		chapterListMenu.removeAllItems()
	}

	private func gotChapterInfo(_ cis: [Any]?) {
		chapterListMenu.removeAllItems()

		if let cis, !cis.isEmpty {
			for case let info as ChapterItem in cis {
				let mItem = NSMenuItem()
				mItem.isEnabled = true
				mItem.target = self
				mItem.action = #selector(setChapterWithTime(_:))
				mItem.title = info.description
				mItem.tag = info.start
				mItem.state = .off
				mItem.representedObject = info.name

				chapterListMenu.addItem(mItem)
			}

			menuChapterList.isEnabled = true
		} else {
			menuChapterList.isEnabled = false
		}
	}

	////////////////////////////////////////////////draw myself//////////////////////////////////////////////////
	override func draw(_ dirtyRect: NSRect) {
		let rc = bounds
		var pt = NSPoint.zero

		//////////////////// main background
		let fillPath = NSBezierPath(roundedRect: rc, xRadius: CONTROL_CORNER_RADIUS, yRadius: CONTROL_CORNER_RADIUS)
		fillGradient?.draw(in: fillPath, angle: 270)

		//////////////////// top line
		backGroundColor?.set()
		let hilightPath = NSBezierPath()

		pt.x = rc.size.width - CONTROL_CORNER_RADIUS
		pt.y = rc.size.height
		hilightPath.move(to: pt)

		pt.x = CONTROL_CORNER_RADIUS
		hilightPath.line(to: pt)

		hilightPath.stroke()

		//////////////////// round corner line
		backGroundColor2?.set()

		let roundPath = NSBezierPath()
		pt.x = rc.size.width
		pt.y = rc.size.height - CONTROL_CORNER_RADIUS
		roundPath.move(to: pt)

		pt.x = rc.size.width - CONTROL_CORNER_RADIUS
		roundPath.appendArc(withCenter: pt, radius: CONTROL_CORNER_RADIUS, startAngle: 0, endAngle: 90)
		pt.x = CONTROL_CORNER_RADIUS
		pt.y = rc.size.height
		roundPath.move(to: pt)

		pt.y = rc.size.height - CONTROL_CORNER_RADIUS
		roundPath.appendArc(withCenter: pt, radius: CONTROL_CORNER_RADIUS, startAngle: 90, endAngle: 180)
		roundPath.stroke()
	}

	private func calculateHintTime() {
		let pt = convert(window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? .zero, from: nil)
		let frm = timeSlider.frame

		var timeDisp = ((pt.x - frm.origin.x) * CGFloat(timeSlider.maxValue)) / frm.size.width

		let fnPressed = (NSEvent.modifierFlags == kSCMSwitchTimeHintKeyModifierMask)
		if fnPressed != ud.bool(forKey: kUDKeySwitchTimeHintPressOnAbusolute) {
			// if Fn is not pressed, show the time difference
			// otherwise show the absolute time
			timeDisp -= CGFloat(timeSlider.floatValue)
		}
		hintTime.intValue = safeInt32(Double(timeDisp + ((timeDisp > 0) ? 0.5 : -0.5)))
	}

	@objc func updateHintTime() {
		// get the mouse position within ControlUI
		var pt = convert(window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? .zero, from: nil)
		let frm = timeSlider.frame

		// if the media is not seekable, timeSlider is disabled
		// but if the length of the media is available, we should display the hintTime, whether it is seekable or not
		if NSPointInRect(pt, frm), timeSlider.maxValue > 0 {
			// if the mouse is within timeSlider
			// update the time
			calculateHintTime()

			let wd = hintTime.bounds.size.width
			pt.x -= (wd / 2)
			pt.x = min(pt.x, bounds.size.width - wd)
			pt.y = frm.origin.y + frm.size.height - 4

			hintTime.setFrameOrigin(pt)

			hintTime.animator().alphaValue = 1
		} else {
			hintTime.animator().alphaValue = 0
		}
	}

	override func mouseDragged(with event: NSEvent) {
		var selfFrame = frame
		let contentBound = window?.contentView?.bounds ?? .zero

		selfFrame.origin.x += event.deltaX
		selfFrame.origin.y -= event.deltaY

		selfFrame.origin.x = max(contentBound.origin.x,
								 min(selfFrame.origin.x, contentBound.origin.x + contentBound.size.width - selfFrame.size.width))
		selfFrame.origin.y = max(contentBound.origin.y,
								 min(selfFrame.origin.y, contentBound.origin.y + contentBound.size.height - selfFrame.size.height))

		setFrameOrigin(selfFrame.origin)
	}

	@objc private func windowHasResized(_ notification: Notification?) {
		hintTime.animator().alphaValue = 0

		// this is to make the font size match the window size
		osd.setStringValue(nil, owner: osd.owner, updateTimer: false)
	}
}
