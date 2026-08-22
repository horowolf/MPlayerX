/*
 * MPlayerX - VideoTunerController.swift
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
import QuartzCore
import CoreImage

private let kCIStepBase: Double = 100_000.0

private let kAutoSaveVTSettingsLifeUserDefaults = 3 /**< never reset */
private let kAutoSaveVTSettingsLifeAPN = 1 /**< reset when it isn't APN */
private let kAutoSaveVTSettingsLifeNone = 0 /**< reset as soon as playback starts */

private let kCILayerBrightnessKeyPath = "filters.colorFilter.inputBrightness"
private let kCILayerSaturationKeyPath = "filters.colorFilter.inputSaturation"
private let kCILayerContrastKeyPath = "filters.colorFilter.inputContrast"
private let kCILayerNoiseLevelKeyPath = "filters.nrFilter.inputNoiseLevel"
private let kCILayerSharpnessKeyPath = "filters.nrFilter.inputSharpness"
private let kCILayerGammaKeyPath = "filters.gammaFilter.inputPower"
private let kCILayerHueAngleKeyPath = "filters.hueFilter.inputAngle"

private let kCILayerBrightnessEnabledKeyPath = "filters.colorFilter.enabled"
private let kCILayerNoiseLevelEnabledKeyPath = "filters.nrFilter.enabled"
private let kCILayerGammaEnabledKeyPath = "filters.gammaFilter.enabled"
private let kCILayerHueAngleEnabledKeyPath = "filters.hueFilter.enabled"

// Maps each value keyPath to its filter's shared "enabled" keyPath (the
// three color-related keys below all share the same colorFilter.enabled
// switch, same as the original enableStrDict).
private let enableStrDict: [String: String] = [
	kCILayerBrightnessKeyPath: kCILayerBrightnessEnabledKeyPath,
	kCILayerSaturationKeyPath: kCILayerBrightnessEnabledKeyPath,
	kCILayerContrastKeyPath: kCILayerBrightnessEnabledKeyPath,
	kCILayerNoiseLevelKeyPath: kCILayerNoiseLevelEnabledKeyPath,
	kCILayerSharpnessKeyPath: kCILayerNoiseLevelEnabledKeyPath,
	kCILayerGammaKeyPath: kCILayerGammaEnabledKeyPath,
	kCILayerHueAngleKeyPath: kCILayerHueAngleEnabledKeyPath,
]

private struct FilterSpec {
	let keyPath: String
	let label: String
	let min: Double
	let max: Double
	let defaultValue: Double
	let decImage: String
	let incImage: String
	let isHue: Bool
}

// Order matches the original VideoTuner.xib's vertical layout: Brightness,
// Saturation, Contrast, Gamma, Hue above the separator; NR, Sharpness below it.
private let filterSpecs: [FilterSpec] = [
	FilterSpec(keyPath: kCILayerBrightnessKeyPath,
			   label: NSLocalizedString("Brightness:", comment: "Video Tuner Panel"),
			   min: -0.75, max: 0.75, defaultValue: 0.0,
			   decImage: "brightness-min", incImage: "brightness-max", isHue: false),
	FilterSpec(keyPath: kCILayerSaturationKeyPath,
			   label: NSLocalizedString("Saturation:", comment: "Video Tuner Panel"),
			   min: 0, max: 2, defaultValue: 1.0,
			   decImage: "saturation-min", incImage: "saturation-max", isHue: false),
	FilterSpec(keyPath: kCILayerContrastKeyPath,
			   label: NSLocalizedString("Contrast:", comment: "Video Tuner Panel"),
			   min: 0.25, max: 4, defaultValue: 1.0,
			   decImage: "contrast-min", incImage: "contrast-max", isHue: false),
	FilterSpec(keyPath: kCILayerGammaKeyPath,
			   label: NSLocalizedString("Gamma:", comment: "Video Tuner Panel"),
			   min: 0.1, max: 3, defaultValue: 1.0,
			   decImage: "gamma-min", incImage: "gamma-max", isHue: false),
	FilterSpec(keyPath: kCILayerHueAngleKeyPath,
			   label: NSLocalizedString("Hue:", comment: "Video Tuner Panel"),
			   min: -3.14, max: 3.14, defaultValue: 0.0,
			   decImage: "hue-minus", incImage: "hue-plus", isHue: true),
	FilterSpec(keyPath: kCILayerNoiseLevelKeyPath,
			   label: NSLocalizedString("NR:", comment: "Video Tuner Panel"),
			   min: 0, max: 0.1, defaultValue: 0.0,
			   decImage: "noisereduction-min", incImage: "noisereduction-max", isHue: false),
	FilterSpec(keyPath: kCILayerSharpnessKeyPath,
			   label: NSLocalizedString("Sharpness:", comment: "Video Tuner Panel"),
			   min: 0, max: 2, defaultValue: 0.0,
			   decImage: "sharpen-min", incImage: "sharpen-max", isHue: false),
]

// Wraps an already-constructed, already-configured AppKit view so SwiftUI
// only handles its layout, not its lifecycle -- same reasoning as
// OpenURLController/EqualizerController's ExistingView.
private struct ExistingView<V: NSView>: NSViewRepresentable {
	let view: V
	func makeNSView(context: Context) -> V { view }
	func updateNSView(_ nsView: V, context: Context) {}
}

private struct TunerRow: Identifiable {
	let id: String
	let label: String
	let dec: NSButton
	let slider: NSSlider
	let inc: NSButton
}

private struct FilterRowView: View {
	let row: TunerRow

	var body: some View {
		HStack(spacing: 8) {
			Text(row.label)
				.font(.system(size: 11))
				.foregroundColor(.white)
				.frame(width: 64, alignment: .trailing)
			ExistingView(view: row.dec)
				.frame(width: 23, height: 23)
			ExistingView(view: row.slider)
				.frame(width: 240, height: 17)
			ExistingView(view: row.inc)
				.frame(width: 23, height: 23)
		}
	}
}

private struct VideoTunerView: View {
	let topRows: [TunerRow]
	let bottomRows: [TunerRow]
	let resetButton: NSButton

	var body: some View {
		VStack(spacing: 10) {
			ForEach(topRows) { FilterRowView(row: $0) }
			Divider()
			ForEach(bottomRows) { FilterRowView(row: $0) }
			ExistingView(view: resetButton)
				.frame(width: 72, height: 19)
		}
		.padding(20)
	}
}

@objc(VideoTunerController)
class VideoTunerController: NSObject {

	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [
			kUDKeyVideoTunerStepValue: 0.01,
			kUDKeyAutoSaveVTSettings: kAutoSaveVTSettingsLifeAPN,
		])
	}()

	@IBOutlet weak var menuVTPanel: NSMenuItem?
	// Only ever used as the `object:` filter for NSNotificationCenter
	// observers -- nothing calls a method on it -- so it stays untyped
	// rather than needing a protocol.
	@IBOutlet weak var playerController: AnyObject?

	private let ud = UserDefaults.standard
	private var layer: CALayer?
	private var window: NSPanel?
	private var hasLoadedUI = false
	private var rowsByKeyPath: [String: TunerRow] = [:]

	override init() {
		super.init()
		_ = VideoTunerController.registerDefaultsOnce
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override func awakeFromNib() {
		super.awakeFromNib()

		menuVTPanel?.keyEquivalent = kSCMVideoTunerPanelKeyEquivalent

		if ud.integer(forKey: kUDKeyAutoSaveVTSettings) != kAutoSaveVTSettingsLifeUserDefaults {
			ud.removeObject(forKey: kUDKeyVTSettings)
		}

		loadParameters()

		let center = NotificationCenter.default
		center.addObserver(self, selector: #selector(playBackFinalized(_:)),
							name: .mpcPlayFinalized, object: playerController)
		center.addObserver(self, selector: #selector(playBackStopped(_:)),
							name: .mpcPlayStopped, object: playerController)
	}

	private func makeFilterChains() -> [CIFilter] {
		// These four CI filter names/keys are standard, always-available system
		// filters (unchecked in the original ObjC too).
		let colorFilter = CIFilter(name: "CIColorControls")!
		colorFilter.name = "colorFilter"
		colorFilter.isEnabled = false

		let nrFilter = CIFilter(name: "CINoiseReduction")!
		nrFilter.name = "nrFilter"
		nrFilter.isEnabled = false

		let gammaFilter = CIFilter(name: "CIGammaAdjust")!
		gammaFilter.name = "gammaFilter"
		gammaFilter.isEnabled = false

		let hueFilter = CIFilter(name: "CIHueAdjust")!
		hueFilter.name = "hueFilter"
		hueFilter.isEnabled = false

		if let dict = ud.dictionary(forKey: kUDKeyVTSettings) {
			colorFilter.setValue(dict[kCILayerBrightnessKeyPath], forKey: "inputBrightness")
			colorFilter.setValue(dict[kCILayerSaturationKeyPath], forKey: "inputSaturation")
			colorFilter.setValue(dict[kCILayerContrastKeyPath], forKey: "inputContrast")
			nrFilter.setValue(dict[kCILayerNoiseLevelKeyPath], forKey: "inputNoiseLevel")
			nrFilter.setValue(dict[kCILayerSharpnessKeyPath], forKey: "inputSharpness")
			gammaFilter.setValue(dict[kCILayerGammaKeyPath], forKey: "inputPower")
			hueFilter.setValue(dict[kCILayerHueAngleKeyPath], forKey: "inputAngle")
		} else {
			colorFilter.setValue(0.0, forKey: "inputBrightness")
			colorFilter.setValue(1.0, forKey: "inputSaturation")
			colorFilter.setValue(1.0, forKey: "inputContrast")
			nrFilter.setValue(0.0, forKey: "inputNoiseLevel")
			nrFilter.setValue(0.0, forKey: "inputSharpness")
			gammaFilter.setValue(1.0, forKey: "inputPower")
			hueFilter.setValue(0.0, forKey: "inputAngle")
		}

		return [gammaFilter, hueFilter, colorFilter, nrFilter]
	}

	private func loadParameters() {
		guard let layer else { return }

		if let dict = ud.dictionary(forKey: kUDKeyVTSettings) {
			if layer.filters == nil {
				layer.filters = makeFilterChains()
			}
			for (keyPath, value) in dict {
				layer.setValue(value, forKeyPath: keyPath)
			}
		} else {
			layer.filters = nil
		}
	}

	private func saveParameters() {
		guard let layer else { return }

		guard layer.filters != nil else {
			ud.removeObject(forKey: kUDKeyVTSettings)
			return
		}

		var settings: [String: Any] = [:]

		for (keyPath, enaStr) in enableStrDict {
			if let val = layer.value(forKeyPath: enaStr) {
				settings[enaStr] = val
				if let val2 = layer.value(forKeyPath: keyPath) {
					settings[keyPath] = val2
				}
			} else {
				settings[enaStr] = false
			}
		}

		ud.set(settings, forKey: kUDKeyVTSettings)
	}

	private static func makeSlider(spec: FilterSpec) -> NSSlider {
		let slider = NSSlider()
		slider.cell = spec.isHue ? HueSliderCell() : BGHUDSliderCell()
		slider.controlSize = .small
		slider.minValue = spec.min
		slider.maxValue = spec.max
		slider.numberOfTickMarks = 3
		slider.tickMarkPosition = .below
		slider.sliderType = .linear
		slider.cell?.representedObject = spec.keyPath
		_ = slider.sendAction(on: [.leftMouseDown, .leftMouseDragged])
		return slider
	}

	private static func makeStepButton(image: String) -> NSButton {
		let button = NSButton()
		button.bezelStyle = .regularSquare
		button.image = NSImage(named: image)
		button.imagePosition = .imageOnly
		button.imageScaling = .scaleProportionallyDown
		return button
	}

	private static func makeResetButton() -> NSButton {
		let button = NSButton()
		button.cell = BGHUDButtonCell()
		button.bezelStyle = .roundRect
		button.title = NSLocalizedString("Reset", comment: "Video Tuner Panel")
		return button
	}

	private func makeRow(spec: FilterSpec, stepRatio: Double) -> TunerRow {
		let slider = Self.makeSlider(spec: spec)
		slider.target = self
		slider.action = #selector(setFilterParametersAction(_:))

		let step = (spec.max - spec.min) * stepRatio

		let decButton = Self.makeStepButton(image: spec.decImage)
		decButton.tag = Int(-step * kCIStepBase)
		decButton.cell?.representedObject = slider
		decButton.target = self
		decButton.action = #selector(stepFilterParametersAction(_:))

		let incButton = Self.makeStepButton(image: spec.incImage)
		incButton.tag = Int(step * kCIStepBase)
		incButton.cell?.representedObject = slider
		incButton.target = self
		incButton.action = #selector(stepFilterParametersAction(_:))

		return TunerRow(id: spec.keyPath, label: spec.label, dec: decButton, slider: slider, inc: incButton)
	}

	private func buildWindow() {
		let stepRatio = ud.double(forKey: kUDKeyVideoTunerStepValue)

		let rows = filterSpecs.map { makeRow(spec: $0, stepRatio: stepRatio) }
		rowsByKeyPath = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

		let resetButton = Self.makeResetButton()
		resetButton.target = self
		resetButton.action = #selector(resetFiltersAction(_:))

		// Fixed content size close to the original VideoTuner.xib's 408x284
		// contentRect; the layout here is built from filterSpecs rather than
		// fixed frames, so it isn't pixel-identical.
		let contentRect = NSRect(x: 0, y: 0, width: 414, height: 300)
		let panel = NSPanel(contentRect: contentRect,
							 styleMask: [.titled, .closable, .miniaturizable, .utilityWindow, .nonactivatingPanel, .hudWindow],
							 backing: .buffered,
							 defer: false)
		panel.title = NSLocalizedString("Video Tuner", comment: "Video Tuner Panel")
		panel.isReleasedWhenClosed = false
		panel.hidesOnDeactivate = true
		panel.setFrameAutosaveName("VideoTuner")
		panel.minSize = contentRect.size
		panel.maxSize = contentRect.size
		panel.level = .mainMenu

		let topRows = Array(rows.prefix(5))
		let bottomRows = Array(rows.suffix(2))
		panel.contentView = NSHostingView(rootView: VideoTunerView(topRows: topRows, bottomRows: bottomRows, resetButton: resetButton))

		window = panel
	}

	private func loadInitialSliderValues() {
		let dict = ud.dictionary(forKey: kUDKeyVTSettings)

		for spec in filterSpecs {
			guard let slider = rowsByKeyPath[spec.keyPath]?.slider else { continue }

			if let layer, layer.filters != nil {
				slider.doubleValue = (layer.value(forKeyPath: spec.keyPath) as? NSNumber)?.doubleValue ?? spec.defaultValue
			} else if let dict {
				slider.doubleValue = (dict[spec.keyPath] as? NSNumber)?.doubleValue ?? spec.defaultValue
			} else {
				slider.doubleValue = spec.defaultValue
			}
		}
	}

	@IBAction @objc(showUI:)
	func showUI(_ sender: Any) {
		if !hasLoadedUI {
			hasLoadedUI = true
			buildWindow()
			loadInitialSliderValues()
		}

		guard let window else { return }

		if window.isVisible {
			window.orderOut(self)
		} else {
			window.orderFront(self)
		}
	}

	private func resetFilters() {
		layer?.filters = nil

		ud.removeObject(forKey: kUDKeyVTSettings)

		if hasLoadedUI {
			for spec in filterSpecs {
				rowsByKeyPath[spec.keyPath]?.slider.doubleValue = spec.defaultValue
			}
		}
	}

	@objc private func resetFiltersAction(_ sender: Any) {
		resetFilters()
	}

	@objc private func setFilterParametersAction(_ sender: NSSlider) {
		guard let layer else { return }

		if layer.filters == nil {
			layer.filters = makeFilterChains()
		}

		guard let keyPath = sender.cell?.representedObject as? String,
			  let enaStr = enableStrDict[keyPath] else { return }

		if !((layer.value(forKeyPath: enaStr) as? Bool) ?? false) {
			layer.setValue(true, forKeyPath: enaStr)
		}

		layer.setValue(sender.doubleValue, forKeyPath: keyPath)

		saveParameters()
	}

	@objc private func stepFilterParametersAction(_ sender: NSButton) {
		guard let slider = sender.cell?.representedObject as? NSSlider else { return }

		slider.floatValue = slider.floatValue + Float(sender.tag) / Float(kCIStepBase)

		setFilterParametersAction(slider)
	}

	@objc(setLayer:)
	func setLayer(_ l: CALayer?) {
		layer?.filters = nil
		layer = l
		loadParameters()
	}

	@objc private func playBackStopped(_ notif: Notification) {
		if ud.integer(forKey: kUDKeyAutoSaveVTSettings) == kAutoSaveVTSettingsLifeNone {
			resetFilters()
		}
	}

	@objc private func playBackFinalized(_ notif: Notification) {
		if ud.integer(forKey: kUDKeyAutoSaveVTSettings) == kAutoSaveVTSettingsLifeAPN {
			resetFilters()
		}
	}
}
