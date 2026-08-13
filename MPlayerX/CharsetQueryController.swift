/*
 * MPlayerX - CharsetQueryController.swift
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

// Menu entries for the encoding picker, in the same order/grouping as the
// Objective-C original's -[NSMenu(CharsetListAppend) appendCharsetList]
// (CocoaAppendix.m). That category method is left untouched -- PrefController
// (not yet ported) still uses it for its own charset picker -- so this list
// is a deliberate duplicate, not a shared source. Retire the duplication when
// PrefController's stage of the rewrite lands.
private enum CharsetMenuEntry {
	case separator
	case item(title: String, tag: CFStringEncoding)
}

// Tag values are the raw CFStringEncoding values straight out of CFString.h /
// CFStringEncodingExt.h (each comment names the original kCFStringEncodingXxx
// constant) rather than referring to the constants by name. Swift only
// imports those constants by way of two differently-named, differently-cased
// enums (CFStringBuiltInEncodings for the handful declared in CFString.h,
// CFStringEncodings -- plural -- for the rest in CFStringEncodingExt.h), and
// getting 30-some case names right by guessing is exactly the trap HANDOFF's
// stage-B notes warn about (see lesson 8) -- the numeric values are unambiguous
// and don't depend on how a given SDK's ClangImporter happens to case them.
private let charsetMenuEntries: [CharsetMenuEntry] = [
	.item(title: NSLocalizedString("Unicode (UTF-8)", comment: "Text Enc"), tag: 0x08000100),               // kCFStringEncodingUTF8
	.item(title: NSLocalizedString("Unicode (UTF-16BE)", comment: "Text Enc"), tag: 0x10000100),             // kCFStringEncodingUTF16BE
	.item(title: NSLocalizedString("Unicode (UTF-16LE)", comment: "Text Enc"), tag: 0x14000100),             // kCFStringEncodingUTF16LE
	.item(title: NSLocalizedString("Unicode (UTF-32BE)", comment: "Text Enc"), tag: 0x18000100),             // kCFStringEncodingUTF32BE
	.item(title: NSLocalizedString("Unicode (UTF-32LE)", comment: "Text Enc"), tag: 0x1c000100),             // kCFStringEncodingUTF32LE
	.separator,
	.item(title: NSLocalizedString("Arabic (ISO 8859-6)", comment: "Text Enc"), tag: 0x0206),                // kCFStringEncodingISOLatinArabic
	.item(title: NSLocalizedString("Arabic (Windows-1256)", comment: "Text Enc"), tag: 0x0506),              // kCFStringEncodingWindowsArabic
	.item(title: NSLocalizedString("Arabic (Mac)", comment: "Text Enc"), tag: 4),                            // kCFStringEncodingMacArabic
	.separator,
	.item(title: NSLocalizedString("Baltic (ISO 8859-4)", comment: "Text Enc"), tag: 0x0204),                // kCFStringEncodingISOLatin4
	.item(title: NSLocalizedString("Baltic (ISO 8859-13)", comment: "Text Enc"), tag: 0x020D),               // kCFStringEncodingISOLatin7
	.item(title: NSLocalizedString("Baltic (Windows-1257)", comment: "Text Enc"), tag: 0x0507),              // kCFStringEncodingWindowsBalticRim
	.separator,
	.item(title: NSLocalizedString("Celtic (ISO 8859-14)", comment: "Text Enc"), tag: 0x020E),               // kCFStringEncodingISOLatin8
	.item(title: NSLocalizedString("Celtic (Mac)", comment: "Text Enc"), tag: 39),                           // kCFStringEncodingMacCeltic
	.separator,
	.item(title: NSLocalizedString("Central Europe (ISO 8859-2)", comment: "Text Enc"), tag: 0x0202),        // kCFStringEncodingISOLatin2
	.item(title: NSLocalizedString("Central Europe (ISO 8859-16)", comment: "Text Enc"), tag: 0x0210),       // kCFStringEncodingISOLatin10
	.item(title: NSLocalizedString("Central Europe (Windows-1250)", comment: "Text Enc"), tag: 0x0501),      // kCFStringEncodingWindowsLatin2
	.item(title: NSLocalizedString("Central Europe (Mac)", comment: "Text Enc"), tag: 29),                   // kCFStringEncodingMacCentralEurRoman
	.separator,
	.item(title: NSLocalizedString("Chinese Simplified (GB18030)", comment: "Text Enc"), tag: 0x0632),       // kCFStringEncodingGB_18030_2000
	.item(title: NSLocalizedString("Chinese Simplified (ISO 2022)", comment: "Text Enc"), tag: 0x0830),      // kCFStringEncodingISO_2022_CN
	.item(title: NSLocalizedString("Chinese Simplified (EUC)", comment: "Text Enc"), tag: 0x0930),           // kCFStringEncodingEUC_CN
	.item(title: NSLocalizedString("Chinese Simplified (Windows-936)", comment: "Text Enc"), tag: 0x0421),   // kCFStringEncodingDOSChineseSimplif
	.item(title: NSLocalizedString("Chinese Simplified (Mac)", comment: "Text Enc"), tag: 25),               // kCFStringEncodingMacChineseSimp
	.separator,
	.item(title: NSLocalizedString("Chinese Traditional (Big5)", comment: "Text Enc"), tag: 0x0A03),         // kCFStringEncodingBig5
	.item(title: NSLocalizedString("Chinese Traditional (Big5 HKSCS)", comment: "Text Enc"), tag: 0x0A06),   // kCFStringEncodingBig5_HKSCS_1999
	.item(title: NSLocalizedString("Chinese Traditional (EUC)", comment: "Text Enc"), tag: 0x0931),          // kCFStringEncodingEUC_TW
	.item(title: NSLocalizedString("Chinese Traditional (Windows-950)", comment: "Text Enc"), tag: 0x0423),  // kCFStringEncodingDOSChineseTrad
	.item(title: NSLocalizedString("Chinese Traditional (Mac)", comment: "Text Enc"), tag: 2),               // kCFStringEncodingMacChineseTrad
	.separator,
	.item(title: NSLocalizedString("Cyrillic (ISO 8859-5)", comment: "Text Enc"), tag: 0x0205),              // kCFStringEncodingISOLatinCyrillic
	.item(title: NSLocalizedString("Cyrillic (Windows-1251)", comment: "Text Enc"), tag: 0x0502),            // kCFStringEncodingWindowsCyrillic
	.item(title: NSLocalizedString("Cyrillic (Mac)", comment: "Text Enc"), tag: 7),                          // kCFStringEncodingMacCyrillic
	.item(title: NSLocalizedString("Cyrillic (KOI8-R)", comment: "Text Enc"), tag: 0x0A02),                  // kCFStringEncodingKOI8_R
	.item(title: NSLocalizedString("Cyrillic (KOI8-U)", comment: "Text Enc"), tag: 0x0A08),                  // kCFStringEncodingKOI8_U
	.separator,
	.item(title: NSLocalizedString("Greek (ISO 8859-7)", comment: "Text Enc"), tag: 0x0207),                 // kCFStringEncodingISOLatinGreek
	.item(title: NSLocalizedString("Greek (Windows-1253)", comment: "Text Enc"), tag: 0x0503),               // kCFStringEncodingWindowsGreek
	.item(title: NSLocalizedString("Greek (Mac)", comment: "Text Enc"), tag: 6),                             // kCFStringEncodingMacGreek
	.separator,
	.item(title: NSLocalizedString("Hebrew (ISO 8859-8)", comment: "Text Enc"), tag: 0x0208),                // kCFStringEncodingISOLatinHebrew
	.item(title: NSLocalizedString("Hebrew (Windows-1255)", comment: "Text Enc"), tag: 0x0505),              // kCFStringEncodingWindowsHebrew
	.item(title: NSLocalizedString("Hebrew (Mac)", comment: "Text Enc"), tag: 5),                            // kCFStringEncodingMacHebrew
	.separator,
	.item(title: NSLocalizedString("Japanese (Shift-JIS)", comment: "Text Enc"), tag: 0x0A01),               // kCFStringEncodingShiftJIS
	.item(title: NSLocalizedString("Japanese (ISO 2022)", comment: "Text Enc"), tag: 0x0820),                // kCFStringEncodingISO_2022_JP
	.item(title: NSLocalizedString("Japanese (EUC)", comment: "Text Enc"), tag: 0x0920),                     // kCFStringEncodingEUC_JP
	.item(title: NSLocalizedString("Japanese (Windows-932)", comment: "Text Enc"), tag: 0x0420),             // kCFStringEncodingDOSJapanese
	.item(title: NSLocalizedString("Japanese (Mac)", comment: "Text Enc"), tag: 1),                          // kCFStringEncodingMacJapanese
	.separator,
	.item(title: NSLocalizedString("Korean (ISO 2022)", comment: "Text Enc"), tag: 0x0840),                  // kCFStringEncodingISO_2022_KR
	.item(title: NSLocalizedString("Korean (EUC)", comment: "Text Enc"), tag: 0x0940),                       // kCFStringEncodingEUC_KR
	.item(title: NSLocalizedString("Korean (Windows-949)", comment: "Text Enc"), tag: 0x0422),               // kCFStringEncodingDOSKorean
	.item(title: NSLocalizedString("Korean (Mac)", comment: "Text Enc"), tag: 3),                            // kCFStringEncodingMacKorean
	.separator,
	.item(title: NSLocalizedString("South Europe (ISO 8859-3)", comment: "Text Enc"), tag: 0x0203),          // kCFStringEncodingISOLatin3
	.separator,
	.item(title: NSLocalizedString("Thai (ISO 8859-11)", comment: "Text Enc"), tag: 0x020B),                 // kCFStringEncodingISOLatinThai
	.item(title: NSLocalizedString("Thai (Windows-874/TIS-620)", comment: "Text Enc"), tag: 0x041D),         // kCFStringEncodingDOSThai
	.item(title: NSLocalizedString("Thai (Mac)", comment: "Text Enc"), tag: 21),                             // kCFStringEncodingMacThai
	.separator,
	.item(title: NSLocalizedString("Turkish (ISO 8859-9)", comment: "Text Enc"), tag: 0x0209),               // kCFStringEncodingISOLatin5
	.item(title: NSLocalizedString("Turkish (Windows-1254)", comment: "Text Enc"), tag: 0x0504),             // kCFStringEncodingWindowsLatin5
	.item(title: NSLocalizedString("Turkish (Mac)", comment: "Text Enc"), tag: 35),                          // kCFStringEncodingMacTurkish
	.separator,
	.item(title: NSLocalizedString("Vietnamese (Windows-1258)", comment: "Text Enc"), tag: 0x0508),          // kCFStringEncodingWindowsVietnamese
	.item(title: NSLocalizedString("Vietnamese (Mac)", comment: "Text Enc"), tag: 30),                       // kCFStringEncodingMacVietnamese
	.separator,
	.item(title: NSLocalizedString("Western Europe (ISO 8859-1)", comment: "Text Enc"), tag: 0x0201),        // kCFStringEncodingISOLatin1
	.item(title: NSLocalizedString("Western Europe (ISO 8859-15)", comment: "Text Enc"), tag: 0x020F),       // kCFStringEncodingISOLatin9
	.item(title: NSLocalizedString("Western Europe (Windows-1252)", comment: "Text Enc"), tag: 0x0500),      // kCFStringEncodingWindowsLatin1
	.item(title: NSLocalizedString("Western Europe (Mac)", comment: "Text Enc"), tag: 0),                    // kCFStringEncodingMacRoman
]

private let charsetMenuTags: Set<CFStringEncoding> = {
	var tags = Set<CFStringEncoding>()
	for entry in charsetMenuEntries {
		if case .item(_, let tag) = entry {
			tags.insert(tag)
		}
	}
	return tags
}()

private final class CharsetQueryModel: ObservableObject {
	@Published var hintText: String = ""
	// Matches NSPopUpButton's own default: a freshly populated popup with no
	// explicit selection auto-selects its first item.
	@Published var selectedTag: CFStringEncoding = {
		if case .item(_, let tag) = charsetMenuEntries[0] { return tag }
		return kCFStringEncodingInvalidId
	}()
}

private struct CharsetQueryView: View {
	@ObservedObject var model: CharsetQueryModel
	let onConfirm: () -> Void
	let onCancel: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(model.hintText)
				.font(.system(size: 11))
				.fixedSize(horizontal: false, vertical: true)
			Divider()
			HStack {
				Text(NSLocalizedString("Choose a proper encoding method:", comment: "SubEncoding"))
					.font(.system(size: 11))
				Spacer()
				Picker("", selection: $model.selectedTag) {
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
				.frame(width: 206)
			}
			HStack {
				Spacer()
				Button(NSLocalizedString("Cancel", comment: "SubEncoding"), action: onCancel)
					.keyboardShortcut(.cancelAction)
				Button(NSLocalizedString("OK", comment: "SubEncoding"), action: onConfirm)
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding(16)
	}
}

@objc(CharsetQueryController)
class CharsetQueryController: NSObject {

	// Equivalent of the Objective-C original's +initialize, which registered
	// these the moment the class was loaded. Swift's class-level `initialize()`
	// override is unreliable across runtime/ObjC-interop changes, so a
	// lazily-evaluated static (guaranteed by Swift to run exactly once,
	// thread-safe) triggered from init() stands in for it instead.
	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [
			kUDKeyTextSubtitleCharsetConfidenceThresh: 0.8,
			kUDKeyTextSubtitleCharsetManual: true,
			kUDKeyTextSubtitleCharsetFallback: Int(kCFStringEncodingInvalidId),
		])
	}()

	private var window: NSPanel?
	private let model = CharsetQueryModel()

	override init() {
		super.init()
		_ = CharsetQueryController.registerDefaultsOnce
	}

	private func buildWindowIfNeeded() {
		guard window == nil else { return }

		// Same fixed content size and style (titled/miniaturizable/utility,
		// deliberately not closable -- Cancel/OK are the only way out) as the
		// original SubEncoding.xib's NSPanel.
		let contentRect = NSRect(x: 0, y: 0, width: 436, height: 116)
		let panel = NSPanel(contentRect: contentRect,
							 styleMask: [.titled, .miniaturizable, .utilityWindow],
							 backing: .buffered,
							 defer: false)
		panel.title = NSLocalizedString("Subtitle Encoding", comment: "SubEncoding")
		panel.isReleasedWhenClosed = false
		panel.setFrameAutosaveName("SubtitleEncoding")
		panel.minSize = contentRect.size
		panel.maxSize = contentRect.size

		let view = CharsetQueryView(model: model,
									 onConfirm: { [weak self] in self?.confirmed() },
									 onCancel: { [weak self] in self?.canceled() })
		panel.contentView = NSHostingView(rootView: view)

		window = panel
	}

	@objc(askForSubEncodingForFile:charsetName:confidence:)
	func askForSubEncoding(forFile path: String, charsetName: String?, confidence: Float) -> CFStringEncoding {
		buildWindowIfNeeded()

		model.hintText = String(format: NSLocalizedString("Detected file:\t%@\nEncoding:\t\t%@\nconfidence:\t%2.1f%%", comment: "SubEncoding"),
								 (path as NSString).lastPathComponent, charsetName ?? "", confidence * 100.0)

		if let charsetName {
			let ce = CFStringConvertIANACharSetNameToEncoding(charsetName as CFString)
			if ce != kCFStringEncodingInvalidId, charsetMenuTags.contains(ce) {
				model.selectedTag = ce
			}
		}

		let response = NSApp.runModal(for: window!)
		return CFStringEncoding(response.rawValue)
	}

	private func confirmed() {
		NSApp.stopModal(withCode: NSApplication.ModalResponse(Int(model.selectedTag)))
		window?.orderOut(nil)
	}

	private func canceled() {
		NSApp.stopModal(withCode: NSApplication.ModalResponse(Int(kCFStringEncodingInvalidId)))
		window?.orderOut(nil)
	}
}
