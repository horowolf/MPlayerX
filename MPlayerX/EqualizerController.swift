/*
 * MPlayerX - EqualizerController.swift
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
import SwiftUI

// A narrow protocol standing in for `PlayerController` (not yet ported to
// Swift) -- see OpenURLController's OpenURLFileLoading for why the full
// header can't go in the bridging header (import cycle through the
// generated MPlayerX-Swift.h). `amps` is untyped on purpose: the original
// passes either an array of NSNumber (saved settings) or the live NSSlider
// views themselves, both of which respond to -floatValue, all the way down
// to CoreController's mplayer filter string built from [amp floatValue].
@objc protocol EqualizerPlayerAccess: AnyObject {
	func setEqualizer(_ amps: [Any]?)
}

// These four were a private #define block local to EqualizerController.m,
// not shared with any other file, so they're plain private Swift constants.
private let kAutoSaveEQSettingsLifeNone: Int = 0 /**< reset as soon as playback starts */
private let kAutoSaveEQSettingsLifeAPN: Int = 1 /**< reset when it isn't APN */
private let kAutoSaveEQSettingsLifeUserDefaults: Int = 3 /**< never reset */
private let kEQValueDefault: Float = 0.0

private let kFrequencyLabels = ["30", "60", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

// Wraps an already-constructed, already-configured AppKit view so SwiftUI
// only handles its layout, not its lifecycle -- same reasoning as
// OpenURLController's ExistingView (the sliders need to exist and be
// addressable by the controller before SwiftUI necessarily lays out).
private struct ExistingView<V: NSView>: NSViewRepresentable {
	let view: V
	func makeNSView(context: Context) -> V { view }
	func updateNSView(_ nsView: V, context: Context) {}
}

private struct EQBand: Identifiable {
	let id: Int
	let label: String
	let slider: NSSlider
}

private struct EqualizerBandColumn: View {
	let band: EQBand

	var body: some View {
		VStack(spacing: 6) {
			ExistingView(view: band.slider)
				.frame(width: 25, height: 220)
			Text(band.label)
				.font(.system(size: 10))
				.foregroundColor(.white)
		}
	}
}

private struct EqualizerView: View {
	let bands: [EQBand]
	let resetButton: NSButton

	var body: some View {
		VStack(spacing: 20) {
			HStack(alignment: .top, spacing: 12) {
				VStack {
					Text("12dB")
					Spacer()
					Text("0dB")
					Spacer()
					Text("-12dB")
				}
				.font(.system(size: 10))
				.foregroundColor(.white)
				.frame(width: 40, height: 220, alignment: .trailing)

				ForEach(bands) { band in
					EqualizerBandColumn(band: band)
				}
			}

			ExistingView(view: resetButton)
				.frame(width: 74, height: 19)
		}
		.padding(20)
	}
}

@objc(EqualizerController)
class EqualizerController: NSObject {

	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [kUDKeyAutoSaveEQSettings: kAutoSaveEQSettingsLifeAPN])
	}()

	@IBOutlet weak var playerController: EqualizerPlayerAccess?
	@IBOutlet weak var menuEQPanel: NSMenuItem?

	private let ud = UserDefaults.standard
	private var window: NSPanel?
	private var hasLoadedUI = false
	private var bars: [NSSlider] = []

	override init() {
		super.init()
		_ = EqualizerController.registerDefaultsOnce
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override func awakeFromNib() {
		super.awakeFromNib()

		menuEQPanel?.keyEquivalent = kSCMEqualizerPanelKeyEquivalent

		if ud.integer(forKey: kUDKeyAutoSaveEQSettings) != kAutoSaveEQSettingsLifeUserDefaults {
			// if settings aren't saved permanently, then delete them
			ud.removeObject(forKey: kUDKeyEQSettings)
		}

		// load EQ settings
		// the UI hasn't loaded at this point, so no need to set anything on the UI
		// in the future, if the Controller loads the UI right at startup, care must be taken here to keep the UI in sync
		playerController?.setEqualizer(ud.array(forKey: kUDKeyEQSettings))

		let center = NotificationCenter.default
		center.addObserver(self, selector: #selector(playBackFinalized(_:)),
							name: .mpcPlayFinalized, object: playerController)
		center.addObserver(self, selector: #selector(playBackStopped(_:)),
							name: .mpcPlayStopped, object: playerController)
	}

	private static func makeSlider() -> NSSlider {
		let slider = NSSlider()
		let cell = BGHUDSliderCell()
		cell.minValue = -10
		cell.maxValue = 10
		cell.numberOfTickMarks = 11
		// NSSlider.TickMarkPosition only has .below/.above; .below is the
		// same raw value as the xib's "left" (NSTickMarkPositionLeading) for
		// a vertical slider.
		cell.tickMarkPosition = .below
		cell.sliderType = .linear
		slider.cell = cell
		slider.isVertical = true
		return slider
	}

	private static func makeResetButton() -> NSButton {
		let button = NSButton()
		button.cell = BGHUDButtonCell()
		button.bezelStyle = .roundRect
		button.title = NSLocalizedString("Reset", comment: "Equalizer & Video Tuner Panel")
		return button
	}

	private func buildWindow() {
		bars = kFrequencyLabels.map { _ in Self.makeSlider() }
		for slider in bars {
			slider.target = self
			slider.action = #selector(setEqualizerAction(_:))
		}

		let resetButton = Self.makeResetButton()
		resetButton.target = self
		resetButton.action = #selector(resetEqualizerAction(_:))

		// Same fixed content size and style (titled/closable/miniaturizable/
		// utility/nonactivating/HUD, hides when the app deactivates) as the
		// original Equalizer.xib's NSPanel.
		let contentRect = NSRect(x: 0, y: 0, width: 493, height: 312)
		let panel = NSPanel(contentRect: contentRect,
							 styleMask: [.titled, .closable, .miniaturizable, .utilityWindow, .nonactivatingPanel, .hudWindow],
							 backing: .buffered,
							 defer: false)
		panel.title = NSLocalizedString("Equalizer", comment: "Equalizer Panel")
		panel.isReleasedWhenClosed = false
		panel.hidesOnDeactivate = true
		panel.setFrameAutosaveName("Equalizer")
		panel.minSize = contentRect.size
		panel.maxSize = contentRect.size

		let bands = kFrequencyLabels.enumerated().map { idx, label in
			EQBand(id: idx, label: label, slider: bars[idx])
		}
		panel.contentView = NSHostingView(rootView: EqualizerView(bands: bands, resetButton: resetButton))

		window = panel
	}

	@IBAction @objc(showUI:)
	func showUI(_ sender: Any) {
		if !hasLoadedUI {
			hasLoadedUI = true
			buildWindow()

			// per Apple's documentation, array returns nil rather than null when there's no such key
			// so the check here is safe
			let settings = ud.array(forKey: kUDKeyEQSettings)

			for (idx, bar) in bars.enumerated() {
				if let settings, idx < settings.count, let value = settings[idx] as? NSNumber {
					bar.floatValue = value.floatValue
				} else {
					bar.floatValue = kEQValueDefault
				}
			}

			// set the window's z coordinate
			window?.level = .mainMenu
		}

		guard let window else { return }

		if window.isVisible {
			window.orderOut(self)
		} else {
			window.orderFront(self)
		}
	}

	private func saveParameters(_ bars: [NSSlider]) {
		let settings = bars.map { NSNumber(value: $0.floatValue) }
		ud.set(settings, forKey: kUDKeyEQSettings)
	}

	@objc private func setEqualizerAction(_ sender: Any) {
		playerController?.setEqualizer(bars)
		saveParameters(bars)
	}

	@objc private func resetEqualizerAction(_ sender: Any) {
		performReset()
	}

	private func performReset() {
		playerController?.setEqualizer(nil)

		for bar in bars {
			bar.floatValue = kEQValueDefault
		}

		saveParameters(bars)
	}

	@objc private func playBackStopped(_ notif: Notification) {
		if ud.integer(forKey: kUDKeyAutoSaveEQSettings) == kAutoSaveEQSettingsLifeNone {
			// playback stopped, but we don't know whether it's APN
			// so only reset when the setting is always-reset
			performReset()
		}
	}

	@objc private func playBackFinalized(_ notif: Notification) {
		if ud.integer(forKey: kUDKeyAutoSaveEQSettings) == kAutoSaveEQSettingsLifeAPN {
			// when resetting the option for non-APN
			// because with APN there won't be a Finalized notification
			// so as long as we get this notification, we can reset
			performReset()
		}
	}
}
