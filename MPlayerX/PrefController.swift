/*
 * MPlayerX - PrefController.swift
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
import CoreText

// Narrow protocols standing in for PlayerController/RootLayerView/ControlUIView
// (none ported to Swift yet) -- see OpenURLController's OpenURLFileLoading for
// why their full headers can't go in the bridging header (import cycle
// through the generated MPlayerX-Swift.h).
@objc protocol PrefPlayerAccess: AnyObject {
	func setMultiThreadMode(_ mt: Bool)
}

@objc protocol PrefDispViewAccess: AnyObject {
	func setPlayerWindowLevel()
}

@objc protocol PrefControlUIAccess: AnyObject {
	func refreshAutoHideTimer()
	func refreshBackgroundAlpha()
	func showUp()
	func refreshOSDSetting()
	func toggleLetterBox(_ sender: Any?)
}

// The exact transformer Cocoa bindings used for the colorWell "value"
// bindings in the original Pref.xib (`NSValueTransformerName">NSUnarchiveFromData`),
// looked up by its registered name rather than referencing the now-deprecated
// `.unarchiveFromDataTransformerName` static (same transformer object either
// way -- this just avoids a deprecation warning on the reference itself).
// Using the system-registered transformer, instead of hand-rolling NSArchiver/
// NSKeyedArchiver calls, guarantees byte-for-byte compatibility with colors
// already saved to a real user's defaults by the ObjC original (which wrote
// them with `+[NSArchiver archivedDataWithRootObject:]` in PlayerController.m/
// OsdText.m's +initialize).
private let colorArchiveTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: "NSUnarchiveFromData"))!

private func colorBinding(_ data: Binding<Data>) -> Binding<Color> {
	Binding<Color>(
		get: {
			if let nsColor = colorArchiveTransformer.transformedValue(data.wrappedValue) as? NSColor {
				return Color(nsColor)
			}
			return .white
		},
		set: { newColor in
			if let newData = colorArchiveTransformer.reverseTransformedValue(NSColor(newColor)) as? Data {
				data.wrappedValue = newData
			}
		}
	)
}

// NumberFormatter.minimum/maximum operate in the *bound value's* space, not
// the displayed text -- for a percent-style formatter that's the underlying
// fraction (0.1...1.0), matching how the original xib's numberFormatter
// elements declare their own minimum/maximum (e.g. SubScale's is
// minimum="0.1" with numberStyle="percent", not minimum="10").
private func percentFormatter(min: Double, max: Double? = nil) -> NumberFormatter {
	let f = NumberFormatter()
	f.numberStyle = .percent
	f.minimum = NSNumber(value: min)
	if let max { f.maximum = NSNumber(value: max) }
	f.maximumFractionDigits = 0
	return f
}

private func secondsFormatter(min: Double) -> NumberFormatter {
	let f = NumberFormatter()
	f.numberStyle = .decimal
	f.minimum = NSNumber(value: min)
	f.maximumFractionDigits = 1
	f.positiveSuffix = " s"
	return f
}

private func plainIntFormatter() -> NumberFormatter {
	let f = NumberFormatter()
	f.numberStyle = .none
	f.allowsFloats = false
	return f
}

private func checkboxRow(_ title: String, isOn: Binding<Bool>) -> some View {
	// Toggle's string label is laid out on one line and truncates. One of
	// these labels is deliberately two lines ("When entering into full screen
	// mode, \nadjust the letterbox's height..."), and showed as "When entering
	// into full screen mode,..." with the rest cut off. Handing the label over
	// as a Text that may grow vertically keeps it whole and leaves every
	// single-line label laid out exactly as before.
	Toggle(isOn: isOn) {
		Text(title).fixedSize(horizontal: false, vertical: true)
	}
	.toggleStyle(.checkbox)
}

private func explanationText(_ text: String) -> some View {
	Text(text)
		.font(.system(size: 10))
		.foregroundColor(Color(white: 0.25))
		.fixedSize(horizontal: false, vertical: true)
}

// Wraps an already-constructed, already-configured AppKit view so SwiftUI
// only handles its layout, not its lifecycle -- same reasoning as
// OpenURLController/EqualizerController's ExistingView. Used here for the
// font popup, which is populated via CocoaAppendix's CoreText-backed NSMenu
// category methods rather than anything SwiftUI-native.
private struct ExistingView<V: NSView>: NSViewRepresentable {
	let view: V
	func makeNSView(context: Context) -> V { view }
	func updateNSView(_ nsView: V, context: Context) {}
}

// Side-effect callbacks matching the original's IBActions that do more than
// just write a UserDefaults value (that part is handled by @AppStorage/the
// custom Bindings below already) -- calls into the not-yet-ported
// PlayerController/RootLayerView/ControlUIView via the narrow protocols above.
private struct PrefActions {
	var multiThreadChanged: () -> Void = {}
	var onTopModeChanged: () -> Void = {}
	var controlUIAppearanceChanged: () -> Void = {}
	var osdSetChanged: () -> Void = {}
	var letterBoxModeChanged: () -> Void = {}
}

private struct GeneralPrefView: View {
	@AppStorage(kUDKeySwitchTimeHintPressOnAbusolute) private var timeHintAbs: Bool = false
	@AppStorage(kUDKeyTimeTextAltTotal) private var timeTextAltTotal: Bool = false
	@AppStorage(kUDKeyCtrlUIAutoHideTime) private var ctrlAutoHideTime: Double = 3.0
	@AppStorage(kUDKeyCtrlUIBackGroundAlpha) private var ctrlBackgroundAlpha: Double = 0.9
	@AppStorage(kUDKeyOnTopMode) private var onTopMode: Int = 2
	@AppStorage(kUDKeyAutoPlayNext) private var autoPlayNext: Bool = true
	@AppStorage(kUDKeyQuitOnClose) private var quitOnClose: Bool = false
	@AppStorage(kUDKeyPlayWhenOpened) private var playWhenOpened: Bool = true
	@AppStorage(kUDKeyAutoResume) private var autoResume: Bool = true
	@AppStorage(kUDKeyEnableOpenRecentMenu) private var enableOpenRecentMenu: Bool = true
	@AppStorage(kUDKeyShowOSD) private var showOSD: Bool = true
	@AppStorage(kUDKeyOSDAutoHideTime) private var osdAutoHideTime: Double = 5.0
	@AppStorage(kUDKeyOSDFrontColor) private var osdFrontColorData: Data = Data()

	let actions: PrefActions

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			GroupBox(label: Text(NSLocalizedString("Player Control", comment: "Pref General"))) {
				VStack(alignment: .leading, spacing: 10) {
					HStack {
						Text(NSLocalizedString("Hide in", comment: "Pref General"))
						TextField("", value: $ctrlAutoHideTime, formatter: secondsFormatter(min: 1))
							.frame(width: 50)
							.onChange(of: ctrlAutoHideTime) { _ in actions.controlUIAppearanceChanged() }
						Text(NSLocalizedString("Transparency", comment: "Pref General"))
						Slider(value: $ctrlBackgroundAlpha, in: 0.1...1)
							.frame(width: 120)
							.onChange(of: ctrlBackgroundAlpha) { _ in actions.controlUIAppearanceChanged() }
						Text(String(format: "%.2f", ctrlBackgroundAlpha))
							.font(.system(size: 10))
							.frame(width: 36, alignment: .leading)
					}
					Divider()
					HStack {
						Text(NSLocalizedString("Show", comment: "Pref General"))
						Picker("", selection: $timeHintAbs) {
							Text(NSLocalizedString("absolute time position", comment: "Pref General")).tag(true)
							Text(NSLocalizedString("relative time to current", comment: "Pref General")).tag(false)
						}
						.labelsHidden()
						.frame(width: 230)
						Text(NSLocalizedString("when hovering over the timeline", comment: "Pref General"))
					}
					HStack {
						Text(NSLocalizedString("Show", comment: "Pref General"))
						Picker("", selection: $timeTextAltTotal) {
							Text(NSLocalizedString("remaining time", comment: "Pref General")).tag(false)
							Text(NSLocalizedString("total time", comment: "Pref General")).tag(true)
						}
						.labelsHidden()
						.frame(width: 230)
						Text(NSLocalizedString("on the right of control bar", comment: "Pref General"))
					}
				}
				.padding(8)
			}

			HStack {
				Text(NSLocalizedString("Keep window on top:", comment: "Pref General"))
				Picker("", selection: $onTopMode) {
					Text(NSLocalizedString("Never", comment: "Pref General")).tag(0)
					Text(NSLocalizedString("Always", comment: "Pref General")).tag(1)
					Text(NSLocalizedString("While playing", comment: "Pref General")).tag(2)
				}
				.labelsHidden()
				.frame(width: 160)
				.onChange(of: onTopMode) { _ in actions.onTopModeChanged() }
			}

			checkboxRow(NSLocalizedString("Find and play next file automatically", comment: "Pref General"), isOn: $autoPlayNext)
				.help(NSLocalizedString("If there are digits in the file name, MPlayerX will increase the rightmost digit-part, to find the next file in the same directory.\nAnd you don't have to worry about the 0 padding", comment: "Pref General"))
			checkboxRow(NSLocalizedString("Quit when window closed", comment: "Pref General"), isOn: $quitOnClose)
			checkboxRow(NSLocalizedString("Start to play when media opened", comment: "Pref General"), isOn: $playWhenOpened)
			checkboxRow(NSLocalizedString("Resume playing from last stopped place", comment: "Pref General"), isOn: $autoResume)
			checkboxRow(NSLocalizedString("Enable \"Open Recent\" menu", comment: "Pref General"), isOn: $enableOpenRecentMenu)

			GroupBox(label: Text(NSLocalizedString("OSD", comment: "Pref General"))) {
				HStack {
					checkboxRow(NSLocalizedString("Show OSD", comment: "Pref General"), isOn: $showOSD)
						.onChange(of: showOSD) { _ in actions.osdSetChanged() }
					Text(NSLocalizedString("Hide in", comment: "Pref General"))
					TextField("", value: $osdAutoHideTime, formatter: secondsFormatter(min: 0.1))
						.frame(width: 50)
						.onChange(of: osdAutoHideTime) { _ in actions.osdSetChanged() }
					Text(NSLocalizedString("Font Color", comment: "Pref General"))
					ColorPicker("", selection: colorBinding($osdFrontColorData))
						.labelsHidden()
						.onChange(of: osdFrontColorData) { _ in actions.osdSetChanged() }
				}
				.padding(8)
			}

			Spacer(minLength: 0)
		}
		.padding(20)
		.frame(width: 560, alignment: .topLeading)
	}
}

private struct VideoPrefView: View {
	@AppStorage(kUDKeyForceIndex) private var forceIndex: Bool = false
	@AppStorage(kUDKeyThreadNum) private var numberOfThreads: Int = 4
	@AppStorage(kUDKeyImgEnhanceMethod) private var imgEnhMethod: Int = 0
	@AppStorage(kUDKeyDeIntMethod) private var deIntMethod: Int = 0
	@AppStorage(kUDKeyStartByFullScreen) private var startByFullScreen: Bool = false
	@AppStorage(kUDKeyAlwaysHideDockInFullScrn) private var alwaysHideDock: Bool = false
	@AppStorage(kUDKeyFullScreenKeepOther) private var fullScreenKeepOther: Bool = true
	@AppStorage(kUDKeyAutoSaveVTSettings) private var autoSaveVTSettings: Int = 1
	@AppStorage(kUDKeyAlwaysUseSecondaryScreen) private var alwaysUseSecondaryScreen: Bool = false

	let actions: PrefActions

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			checkboxRow(NSLocalizedString("Force index rebuilding", comment: "Pref Video"), isOn: $forceIndex)

			GroupBox(label: Text(NSLocalizedString("Performance & Quality", comment: "Pref Video"))) {
				VStack(alignment: .leading, spacing: 10) {
					HStack {
						Text(NSLocalizedString("Number of threads", comment: "Pref Video"))
						TextField("", value: $numberOfThreads, formatter: plainIntFormatter())
							.frame(width: 50)
							.onChange(of: numberOfThreads) { _ in actions.multiThreadChanged() }
					}
					HStack {
						Text(NSLocalizedString("Image Enhancement", comment: "Pref Video"))
						Picker("", selection: $imgEnhMethod) {
							Text(NSLocalizedString("None", comment: "Pref Video")).tag(0)
							Text(NSLocalizedString("Normal", comment: "Pref Video")).tag(129)
							Text(NSLocalizedString("Advanced", comment: "Pref Video & PrefToolBarLabel")).tag(130)
						}
						.pickerStyle(.segmented)
						.frame(width: 220)
					}
					HStack {
						Text(NSLocalizedString("Deinterlace method", comment: "Pref Video"))
						Picker("", selection: $deIntMethod) {
							Text(NSLocalizedString("None", comment: "Pref Video")).tag(0)
							Text(NSLocalizedString("FFMpeg", comment: "Pref Video")).tag(65)
							Text(NSLocalizedString("LPF5", comment: "Pref Video")).tag(66)
						}
						.pickerStyle(.segmented)
						.frame(width: 220)
						.help(NSLocalizedString("FFMpeg: FFMpeg  deinterlacing filter that deinterlaces the given block by filtering every second line with a (-1  4  2  4 -1) filter.\n\nLPF5: Vertically applied FIR lowpass deinterlacing filter that deinterlaces the given block by filtering all lines with a (-1 2 6 2 -1) filter.", comment: "Pref Video"))
					}
				}
				.padding(8)
			}

			checkboxRow(NSLocalizedString("Enter fullscreen when playback starts", comment: "Pref Video"), isOn: $startByFullScreen)
			explanationText(NSLocalizedString("With this setting ON, MPlayerX will recalculate the index to make the video seekable, useful on some broken files. But this may delay playback start by several seconds", comment: "Pref Video"))
			checkboxRow(NSLocalizedString("Always hide Dock in fullscreen mode", comment: "Pref Video"), isOn: $alwaysHideDock)
			checkboxRow(NSLocalizedString("When entered fullscreen, DO NOT blank out other screens", comment: "Pref Video"), isOn: $fullScreenKeepOther)

			Text(NSLocalizedString("How to keep the settings in the \"Video Tuner\" ?", comment: "Pref Video"))
			Picker("", selection: $autoSaveVTSettings) {
				Text(NSLocalizedString("Do not keep, always reset the settings when the playback stops", comment: "Pref Audio & Pref Video")).tag(0)
				Text(NSLocalizedString("Reset the settings when there is no next one to play", comment: "Pref Audio & Pref Video")).tag(1)
				Text(NSLocalizedString("Reset the settings when the application quits", comment: "Pref Audio & Pref Video")).tag(2)
				Text(NSLocalizedString("Never reset, save it as my preferences", comment: "Pref Audio & Pref Video")).tag(3)
			}
			.labelsHidden()

			checkboxRow(NSLocalizedString("Always try to use secondary screen", comment: "Pref Video"), isOn: $alwaysUseSecondaryScreen)

			Spacer(minLength: 0)
		}
		.padding(20)
		.frame(width: 560, alignment: .topLeading)
	}
}

private struct AudioPrefView: View {
	@AppStorage(kUDKeyAutoDetectSPDIF) private var autoDetectSPDIF: Bool = false
	@AppStorage(kUDKeyDTSPassThrough) private var dtsPassThrough: Bool = false
	@AppStorage(kUDKeyAC3PassThrough) private var ac3PassThrough: Bool = false
	@AppStorage(kUDKeyMixToStereoMode) private var mixToStereo: Bool = true
	@AppStorage(kUDKeyAutoSaveEQSettings) private var autoSaveEQSettings: Int = 1

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			GroupBox(label: Text(NSLocalizedString("Output", comment: "Pref Audio"))) {
				VStack(alignment: .leading, spacing: 10) {
					checkboxRow(NSLocalizedString("Detect SPDIF digital output automatically", comment: "Pref Audio"), isOn: $autoDetectSPDIF)
					HStack {
						Text(NSLocalizedString("Pass through:", comment: "Pref Audio"))
						checkboxRow(NSLocalizedString("DTS", comment: "Pref Audio"), isOn: $dtsPassThrough)
							.disabled(autoDetectSPDIF)
						checkboxRow(NSLocalizedString("AC3", comment: "Pref Audio"), isOn: $ac3PassThrough)
							.disabled(autoDetectSPDIF)
					}
				}
				.padding(8)
			}

			checkboxRow(NSLocalizedString("Remix DTS 5.1 to Stereo", comment: "Pref Audio"), isOn: $mixToStereo)
			explanationText(NSLocalizedString("If you use the built-in 2.0 speakers or minijack, please turn this on", comment: "Pref Audio"))

			Text(NSLocalizedString("How to keep the settings in the \"Equalizer\" ?", comment: "Pref Audio"))
			Picker("", selection: $autoSaveEQSettings) {
				Text(NSLocalizedString("Do not keep, always reset the settings when the playback stops", comment: "Pref Audio & Pref Video")).tag(0)
				Text(NSLocalizedString("Reset the settings when there is no next one to play", comment: "Pref Audio & Pref Video")).tag(1)
				Text(NSLocalizedString("Reset the settings when the application quits", comment: "Pref Audio & Pref Video")).tag(2)
				Text(NSLocalizedString("Never reset, save it as my preferences", comment: "Pref Audio & Pref Video")).tag(3)
			}
			.labelsHidden()

			Spacer(minLength: 0)
		}
		.padding(20)
		.frame(width: 560, alignment: .topLeading)
	}
}

private struct SubtitlePrefView: View {
	@AppStorage(kUDKeySubScale) private var subScale: Double = 1.0
	@AppStorage(kUDKeySubFontColor) private var subFontColorData: Data = Data()
	@AppStorage(kUDKeySubFontBorderColor) private var subFontBorderColorData: Data = Data()
	@AppStorage(kUDKeyUseEmbeddedFonts) private var useEmbeddedFonts: Bool = true
	@AppStorage(kUDKeySubAlign) private var subAlign: Int = 0
	@AppStorage(kUDKeySubFileNameRule) private var subFileNameRule: Int = 1
	@AppStorage(kUDKeyNoDispSub) private var noDispSub: Bool = false
	@AppStorage(kUDKeyOverlapSub) private var overlapSub: Bool = true
	@AppStorage(kUDKeyLetterBoxMode) private var letterBoxMode: Int = 0
	@AppStorage(kUDKeyLetterBoxHeight) private var letterBoxHeight: Double = 0.1
	@AppStorage(kUDKeyLBAutoHeightInFullScrn) private var lbAutoHeight: Bool = false
	@AppStorage(kUDKeyTextSubtitleCharsetConfidenceThresh) private var confidenceThresh: Double = 0.8

	let charsetSelection: Binding<CFStringEncoding>
	let fontPopup: NSPopUpButton
	let actions: PrefActions

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			GroupBox(label: Text(NSLocalizedString("Font Style", comment: "Pref Subtitle"))) {
				VStack(alignment: .leading, spacing: 10) {
					HStack {
						Text(NSLocalizedString("Size:", comment: "Pref Subtitle"))
						TextField("", value: $subScale, formatter: percentFormatter(min: 0.1))
							.frame(width: 60)
						Text(NSLocalizedString("Font Color:", comment: "Pref Subtitle"))
						ColorPicker("", selection: colorBinding($subFontColorData)).labelsHidden()
						Text(NSLocalizedString("Border Color:", comment: "Pref Subtitle"))
						ColorPicker("", selection: colorBinding($subFontBorderColorData)).labelsHidden()
					}
					checkboxRow(NSLocalizedString("Use embedded font if possible", comment: "Pref Subtitle"), isOn: $useEmbeddedFonts)
					HStack {
						Text(NSLocalizedString("Alignment:", comment: "Pref Subtitle"))
						Picker("", selection: $subAlign) {
							Text(NSLocalizedString("Default (use the value in sub file)", comment: "Pref Subtitle")).tag(0)
							Text(NSLocalizedString("Bottom - Left", comment: "Pref Subtitle")).tag(1)
							Text(NSLocalizedString("Bottom - Middle", comment: "Pref Subtitle")).tag(2)
							Text(NSLocalizedString("Bottom - Right", comment: "Pref Subtitle")).tag(3)
							Text(NSLocalizedString("Top - Left", comment: "Pref Subtitle")).tag(5)
							Text(NSLocalizedString("Top - Middle", comment: "Pref Subtitle")).tag(6)
							Text(NSLocalizedString("Top - Right", comment: "Pref Subtitle")).tag(7)
						}
						.labelsHidden()
						.frame(width: 270)
					}
					HStack {
						Text(NSLocalizedString("Font:", comment: "Pref Subtitle"))
						ExistingView(view: fontPopup)
							.frame(width: 290, height: 26)
					}
					explanationText(NSLocalizedString("Font fallback is not supported yet.\nSo this option may risk monolingual support.", comment: "Pref Subtitle"))
				}
				.padding(8)
			}

			HStack {
				Text(NSLocalizedString("Load subtitle, if the sub file name", comment: "Pref Subtitle"))
				Picker("", selection: $subFileNameRule) {
					Text(NSLocalizedString("matches the video file name exactly", comment: "Pref Subtitle")).tag(0)
					Text(NSLocalizedString("contains the video file name", comment: "Pref Subtitle")).tag(1)
					Text(NSLocalizedString("is any name", comment: "Pref Subtitle")).tag(2)
				}
				.labelsHidden()
				.frame(width: 270)
			}

			checkboxRow(NSLocalizedString("Load but don't display subtitle when playback starts", comment: "Pref Subtitle"), isOn: $noDispSub)
			checkboxRow(NSLocalizedString("Allow overlapping subtitles", comment: "Pref Subtitle"), isOn: $overlapSub)

			GroupBox(label: Text(NSLocalizedString("Letterbox", comment: "Pref Subtitle"))) {
				VStack(alignment: .leading, spacing: 10) {
					HStack {
						Picker("", selection: $letterBoxMode) {
							Text(NSLocalizedString("No letterbox", comment: "Pref Subtitle")).tag(0)
							Text(NSLocalizedString("Bottom only", comment: "Pref Subtitle")).tag(1)
							Text(NSLocalizedString("Top only", comment: "Pref Subtitle")).tag(2)
							Text(NSLocalizedString("Top + Bottom", comment: "Pref Subtitle")).tag(3)
						}
						.labelsHidden()
						.frame(width: 170)
						.onChange(of: letterBoxMode) { newValue in
							if newValue != kPMLetterBoxModeNotDisplay {
								UserDefaults.standard.set(newValue, forKey: kUDKeyLetterBoxModeAlt)
							}
							actions.letterBoxModeChanged()
						}
						Text(NSLocalizedString("height:", comment: "Pref Subtitle"))
						TextField("", value: $letterBoxHeight, formatter: percentFormatter(min: 0, max: 1))
							.frame(width: 50)
						Text(NSLocalizedString("of movie's height", comment: "Pref Subtitle"))
					}
					checkboxRow(NSLocalizedString("When entering into full screen mode, \nadjust the letterbox's height to fit to the screen's height", comment: "Pref Subtitle"), isOn: $lbAutoHeight)
					explanationText(NSLocalizedString("With this option ON, MPlayerX will make subtitle not to overlay the frame as much as it could.\nHowever, this option will enlarge the rendering frame to the screen size, sometimes, espcially for some HD content, lagging may be brought to the playback.", comment: "Pref Subtitle"))
				}
				.padding(8)
			}

			GroupBox(label: Text(NSLocalizedString("Text Encoding Detection", comment: "Pref Subtitle"))) {
				VStack(alignment: .leading, spacing: 10) {
					HStack {
						Text(NSLocalizedString("If confidence ≤", comment: "Pref Subtitle"))
						TextField("", value: $confidenceThresh, formatter: percentFormatter(min: 0.1, max: 1))
							.frame(width: 50)
						Text(NSLocalizedString("set encoding by", comment: "Pref Subtitle"))
						Picker("", selection: charsetSelection) {
							Text(NSLocalizedString("Ask me", comment: "preference")).tag(CFStringEncoding(kCFStringEncodingInvalidId))
							ForEach(Array(charsetMenuEntries.enumerated()), id: \.offset) { _, entry in
								switch entry {
								case .separator:
									Divider()
								case .item(let title, let tag):
									Text(title).tag(tag)
								}
							}
						}
						.labelsHidden()
						.pickerStyle(.menu)
						.frame(width: 220)
					}
					explanationText(NSLocalizedString("Setting confidence threshold to 100% disables auto detection of the text encoding, but it is not recommended.", comment: "Pref Subtitle"))
				}
				.padding(8)
			}

			Spacer(minLength: 0)
		}
		.padding(20)
		.frame(width: 560, alignment: .topLeading)
	}
}

private struct NetworkPrefView: View {
	@AppStorage(kUDKeyPreferIPV6) private var preferIPV6: Bool = true
	@AppStorage(kUDKeyCacheSize) private var cacheSize: Int = 10000
	@AppStorage(kUDKeyFFMpegHandleStream) private var ffmpegHandleStream: Bool = true
	@AppStorage(kUDKeyRtspOverHttp) private var rtspOverHttp: Bool = true

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			checkboxRow(NSLocalizedString("Prefer IPV6", comment: "Pref Network"), isOn: $preferIPV6)
			HStack {
				Text(NSLocalizedString("Cache size for stream:", comment: "Pref Network"))
				TextField("", value: $cacheSize, formatter: plainIntFormatter())
					.frame(width: 70)
					.onChange(of: cacheSize) { newValue in
						if newValue < 0 { cacheSize = 0 }
					}
				Text(NSLocalizedString("kBytes", comment: "Pref Network"))
					.font(.system(size: 10))
			}
			checkboxRow(NSLocalizedString("Use ffmpeg to handle the stream", comment: "Pref Network"), isOn: $ffmpegHandleStream)
			checkboxRow(NSLocalizedString("Transfer RTSP stream over HTTP protocol", comment: "Pref Network"), isOn: $rtspOverHttp)

			Spacer(minLength: 0)
		}
		.padding(20)
		.frame(width: 560, alignment: .topLeading)
	}
}

private struct AdvancedPrefView: View {
	@AppStorage(kUDKeyExtraOptions) private var extraOptions: String = ""
	@AppStorage(kUDKeyDisableHScrollSeek) private var disableHScroll: Bool = true
	@AppStorage(kUDKeyDisableVScrollVol) private var disableVScroll: Bool = false

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack {
				Text(NSLocalizedString("Extra options", comment: "Pref Advanced"))
				TextField("", text: $extraOptions)
					.frame(maxWidth: .infinity)
			}
			explanationText(NSLocalizedString("The extra options will be passed to mplayer directly.\nMake sure you are really a mplayer professional before you modify this, otherwise please leave it blank.", comment: "Pref Advanced"))
			checkboxRow(NSLocalizedString("Disable horizontal mouse scrolling to seek", comment: "Pref Advanced"), isOn: $disableHScroll)
			checkboxRow(NSLocalizedString("Disable vertical mouse scrolling to change volume", comment: "Pref Advanced"), isOn: $disableVScroll)

			Spacer(minLength: 0)
		}
		.padding(20)
		.frame(width: 560, alignment: .topLeading)
	}
}

private let prefTBIGeneral = NSToolbarItem.Identifier("TBIGeneral")
private let prefTBIVideo = NSToolbarItem.Identifier("TBIVideo")
private let prefTBIAudio = NSToolbarItem.Identifier("TBIAudio")
private let prefTBISubtitle = NSToolbarItem.Identifier("TBISubtitle")
private let prefTBINetwork = NSToolbarItem.Identifier("TBINetwork")
private let prefTBIAdvanced = NSToolbarItem.Identifier("TBIAdvanced")

@objc(PrefController)
class PrefController: NSObject, NSToolbarDelegate {

	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [kUDKeySelectedPrefView: 0])
	}()

	@IBOutlet weak var playerController: PrefPlayerAccess?
	@IBOutlet weak var dispView: PrefDispViewAccess?
	@IBOutlet weak var controlUI: PrefControlUIAccess?

	private let ud = UserDefaults.standard
	private var window: NSWindow?
	private var hasLoadedUI = false
	private var prefViews: [NSView] = []

	override init() {
		super.init()
		_ = PrefController.registerDefaultsOnce
	}

	// Combines two UserDefaults keys (a manual-override flag plus a fallback
	// encoding) into the single selected value the charset picker shows --
	// mirrors the original's subEncodingSchemeChanged: exactly, just as a
	// Binding's setter instead of an IBAction. Not expressible as a single
	// @AppStorage property, so it's built here and passed down instead of
	// living directly on SubtitlePrefView like the other bound fields.
	private var charsetSelection: Binding<CFStringEncoding> {
		Binding<CFStringEncoding>(
			get: { [ud] in
				if ud.bool(forKey: kUDKeyTextSubtitleCharsetManual) {
					return CFStringEncoding(kCFStringEncodingInvalidId)
				}
				return CFStringEncoding(ud.integer(forKey: kUDKeyTextSubtitleCharsetFallback))
			},
			set: { [ud] newTag in
				if newTag == kCFStringEncodingInvalidId {
					ud.set(true, forKey: kUDKeyTextSubtitleCharsetManual)
				} else {
					ud.set(false, forKey: kUDKeyTextSubtitleCharsetManual)
					ud.set(Int(newTag), forKey: kUDKeyTextSubtitleCharsetFallback)
				}
			}
		)
	}

	// Built as a real NSPopUpButton (not a SwiftUI Picker) because populating
	// it re-uses CocoaAppendix's existing CoreText-backed NSMenu category
	// methods (getFontItemFromURL:/getFontItemFromFamilyName:) rather than
	// re-deriving font family enumeration + descriptor lookups natively in
	// Swift -- see ExistingView's doc comment.
	private func buildFontPopup() -> NSPopUpButton {
		let popup = NSPopUpButton()
		let menu = NSMenu()
		popup.menu = menu

		var defaultItem: NSMenuItem?
		let defaultURL = URL(fileURLWithPath: Bundle.main.resourcePath ?? "")
			.appendingPathComponent(kMPCDefaultSubFontPath)
		if let item = menu.getFontItem(from: defaultURL as CFURL) {
			item.representedObject = kMPCDefaultSubFontPath
			menu.addItem(item)
			menu.addItem(.separator())
			defaultItem = item
		}

		let families = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
		for name in families {
			if let item = menu.getFontItem(fromFamilyName: name as CFString) {
				menu.addItem(item)
			}
		}

		let subFontPath = ud.string(forKey: kUDKeySubFontPath)
		if subFontPath == kMPCDefaultSubFontPath {
			if let defaultItem { popup.select(defaultItem) }
		} else if let idx = menu.items.firstIndex(where: { ($0.representedObject as? String) == subFontPath }) {
			popup.selectItem(at: idx)
		} else if let defaultItem {
			popup.select(defaultItem)
			ud.set(kMPCDefaultSubFontPath, forKey: kUDKeySubFontPath)
		}

		popup.target = self
		popup.action = #selector(fontSelectedAction(_:))

		return popup
	}

	@objc private func fontSelectedAction(_ sender: NSPopUpButton) {
		if let path = sender.selectedItem?.representedObject as? String {
			ud.set(path, forKey: kUDKeySubFontPath)
		}
	}

	private func buildWindow() {
		let fontPopup = buildFontPopup()

		let actions = PrefActions(
			multiThreadChanged: { [weak self] in
				guard let self else { return }
				self.playerController?.setMultiThreadMode(self.ud.bool(forKey: kUDKeyEnableMultiThread))
			},
			onTopModeChanged: { [weak self] in self?.dispView?.setPlayerWindowLevel() },
			controlUIAppearanceChanged: { [weak self] in
				self?.controlUI?.refreshAutoHideTimer()
				self?.controlUI?.refreshBackgroundAlpha()
				self?.controlUI?.showUp()
			},
			osdSetChanged: { [weak self] in self?.controlUI?.refreshOSDSetting() },
			letterBoxModeChanged: { [weak self] in self?.controlUI?.toggleLetterBox(nil) }
		)

		// Fixed per-pane sizes approximating the original xib's own customView
		// heights (General 428, Video 397, Audio 231, Subtitle 604, Network
		// 154, Advanced 194 -- all width 560); SwiftUI's own layout doesn't
		// match those pixel-for-pixel, so this is a starting point for the
		// next GUI pass to tune, not an exact reproduction.
		let generalView = NSHostingView(rootView: GeneralPrefView(actions: actions))
		generalView.frame = NSRect(x: 0, y: 0, width: 560, height: 428)

		let videoView = NSHostingView(rootView: VideoPrefView(actions: actions))
		videoView.frame = NSRect(x: 0, y: 0, width: 560, height: 397)

		let audioView = NSHostingView(rootView: AudioPrefView())
		audioView.frame = NSRect(x: 0, y: 0, width: 560, height: 231)

		let subtitleView = NSHostingView(rootView: SubtitlePrefView(charsetSelection: charsetSelection, fontPopup: fontPopup, actions: actions))
		subtitleView.frame = NSRect(x: 0, y: 0, width: 560, height: 604)

		let networkView = NSHostingView(rootView: NetworkPrefView())
		networkView.frame = NSRect(x: 0, y: 0, width: 560, height: 154)

		let advancedView = NSHostingView(rootView: AdvancedPrefView())
		advancedView.frame = NSRect(x: 0, y: 0, width: 560, height: 194)

		prefViews = [generalView, videoView, audioView, subtitleView, networkView, advancedView]

		// Same style (titled/closable/miniaturizable, no .resizable -- sizing
		// is driven entirely by switchViews(_:), not by the user dragging an
		// edge) and starting contentRect as the original Pref.xib's window.
		let contentRect = NSRect(x: 0, y: 0, width: 413, height: 228)
		let win = NSWindow(contentRect: contentRect,
							styleMask: [.titled, .closable, .miniaturizable, .unifiedTitleAndToolbar],
							backing: .buffered,
							defer: false)
		win.title = NSLocalizedString("Preferences", comment: "Pref")
		win.isReleasedWhenClosed = false
		win.hidesOnDeactivate = true
		win.setFrameAutosaveName("Preferences")

		let toolbar = NSToolbar(identifier: "PrefToolbar")
		toolbar.delegate = self
		toolbar.allowsUserCustomization = false
		toolbar.showsBaselineSeparator = false
		toolbar.displayMode = .iconAndLabel
		toolbar.sizeMode = .regular
		win.toolbar = toolbar

		window = win
	}

	@IBAction @objc(showUI:)
	func showUI(_ sender: Any) {
		if !hasLoadedUI {
			hasLoadedUI = true
			buildWindow()

			let savedIdx = ud.integer(forKey: kUDKeySelectedPrefView)
			if let items = window?.toolbar?.items, savedIdx >= 0, savedIdx < items.count {
				switchViews(items[savedIdx])
			}

			window?.level = .mainMenu
			NSColorPanel.shared.showsAlpha = true
		}

		window?.makeKeyAndOrderFront(nil)
	}

	@objc private func switchViews(_ sender: NSToolbarItem) {
		let idx = sender.tag
		guard idx >= 0, idx < prefViews.count, let window else { return }

		let viewToShow = prefViews[idx]
		guard window.contentView !== viewToShow else { return }

		window.toolbar?.selectedItemIdentifier = sender.itemIdentifier

		var rc = window.frameRect(forContentRect: viewToShow.bounds)
		let winFrame = window.frame
		rc.origin = winFrame.origin
		rc.origin.y -= (rc.size.height - winFrame.size.height)

		window.contentView = viewToShow
		window.setFrame(rc, display: true, animate: true)
		window.title = sender.label

		ud.set(idx, forKey: kUDKeySelectedPrefView)
	}

	// MARK: - NSToolbarDelegate

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		[prefTBIGeneral, prefTBIVideo, prefTBIAudio, prefTBISubtitle, prefTBINetwork, prefTBIAdvanced]
	}

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarAllowedItemIdentifiers(toolbar)
	}

	func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarAllowedItemIdentifiers(toolbar)
	}

	func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
		let item = NSToolbarItem(itemIdentifier: itemIdentifier)

		switch itemIdentifier {
		case prefTBIGeneral:
			item.label = NSLocalizedString("General", comment: "PrefToolBarLabel")
			item.image = NSImage(named: NSImage.preferencesGeneralName)
			item.tag = 0
		case prefTBIVideo:
			item.label = NSLocalizedString("Video", comment: "PrefToolBarLabel")
			item.image = NSImage(named: "toolbar_video")
			item.tag = 1
		case prefTBIAudio:
			item.label = NSLocalizedString("Audio", comment: "PrefToolBarLabel")
			item.image = NSImage(named: "toolbar_audio")
			item.tag = 2
		case prefTBISubtitle:
			item.label = NSLocalizedString("Subtitle", comment: "PrefToolBarLabel")
			item.image = NSImage(named: NSImage.fontPanelName)
			item.tag = 3
		case prefTBINetwork:
			item.label = NSLocalizedString("Network", comment: "PrefToolBarLabel")
			item.image = NSImage(named: NSImage.networkName)
			item.tag = 4
		case prefTBIAdvanced:
			item.label = NSLocalizedString("Advanced", comment: "Pref Video & PrefToolBarLabel")
			item.image = NSImage(named: NSImage.advancedName)
			item.tag = 5
		default:
			return nil
		}

		item.target = self
		item.action = #selector(switchViews(_:))
		item.autovalidates = false

		return item
	}
}
