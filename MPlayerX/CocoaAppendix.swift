/*
 * MPlayerX - CocoaAppendix.swift
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

// Was CocoaAppendix.h/.m: the app-wide logging helpers plus a handful of
// AppKit categories, now extensions.
//
// The localized strings are spelled out as NSLocalizedString calls with the
// same keys and comments the LocalizedStrings.h macros had, so genstrings
// still produces the same Localizable.strings.
import Cocoa
import CoreText

let kMPCStringMPlayerX = "MPlayerX"

let kMPXSysVersionLion: Int32 = 0x1070

private var logEnable = false

/// Was the variadic MPLog(); Swift call sites interpolate instead, so this
/// non-variadic form is the only one left.
func MPLogString(_ str: String) {
	if logEnable { NSLog("%@", str) }
}

func MPSetLogEnable(_ enable: Bool) {
	logEnable = enable
}

/// The original called Gestalt(gestaltSystemVersion), which has been
/// deprecated since 10.8 and saturates below 10.10 anyway. The encoding only
/// has to keep the comparisons against kMPXSysVersionLion at the two call
/// sites meaningful; on the 11.0 deployment target both are now always true,
/// so the pre-Lion branches they guard are dead code waiting to be removed.
func MPXGetSysVersion() -> Int32 {
	let v = ProcessInfo.processInfo.operatingSystemVersion
	return Int32(v.majorVersion) << 8 | Int32(min(v.minorVersion, 15)) << 4
}

extension NSColor {
	/// RGB plus *inverted* alpha, packed the way the subtitle color options want it.
	@objc var hexValue: UInt32 {
		guard let col = usingColorSpace(.genericRGB) else { return 0 }

		return (UInt32(255 * col.redComponent) << 24) +
			   (UInt32(255 * col.greenComponent) << 16) +
			   (UInt32(255 * col.blueComponent) << 8) +
			    UInt32(255 * (1 - col.alphaComponent))
	}
}

extension NSString {
	/// Parses a hexadecimal string, with or without a 0x prefix; any invalid
	/// character makes the whole value 0, as in the original.
	@objc var hexValue: UInt32 {
		var res: UInt32 = 0
		var chars = Substring(self as String)

		if chars.hasPrefix("0x") || chars.hasPrefix("0X") { chars = chars.dropFirst(2) }

		for c in chars {
			guard let digit = c.hexDigitValue, c.isHexDigit else { return 0 }
			res = (res << 4) &+ UInt32(digit)
		}
		return res
	}
}

extension FileManager {
	@objc(UserPath:WithSuffix:)
	static func userPath(_ dir: FileManager.SearchPathDirectory, withSuffix suffix: String) -> String? {
		try? FileManager.default.url(for: dir, in: .userDomainMask, appropriateFor: nil, create: true)
			.appendingPathComponent(suffix).path
	}
}

extension NSEvent {
	@objc(makeKeyDownEvent:modifierFlags:)
	static func makeKeyDownEvent(_ str: String, modifierFlags flags: UInt) -> NSEvent? {
		NSEvent.keyEvent(with: .keyDown,
						 location: .zero,
						 modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
						 timestamp: 0,
						 windowNumber: 0,
						 context: nil,
						 characters: str,
						 charactersIgnoringModifiers: str,
						 isARepeat: false,
						 keyCode: 0)
	}
}

extension NSObject {
	/// The original built the panel with NSGetAlertPanel, which Swift cannot
	/// call; NSAlert is the supported equivalent and keeps the same two
	/// localized strings.
	@objc func showAlertPanelModal(_ str: String) {
		let alert = NSAlert()
		alert.messageText = NSLocalizedString("Error", comment: "")
		alert.informativeText = str
		alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
		alert.runModal()
	}
}

extension NSMenu {

	private enum CharsetEntry {
		case separator
		case charset(String, CFStringEncoding)
	}

	private static let charsetList: [CharsetEntry] = [
		.charset(NSLocalizedString("Unicode (UTF-8)", comment: "Text Enc"), CFStringBuiltInEncodings.UTF8.rawValue),
		.charset(NSLocalizedString("Unicode (UTF-16BE)", comment: "Text Enc"), CFStringBuiltInEncodings.UTF16BE.rawValue),
		.charset(NSLocalizedString("Unicode (UTF-16LE)", comment: "Text Enc"), CFStringBuiltInEncodings.UTF16LE.rawValue),
		.charset(NSLocalizedString("Unicode (UTF-32BE)", comment: "Text Enc"), CFStringBuiltInEncodings.UTF32BE.rawValue),
		.charset(NSLocalizedString("Unicode (UTF-32LE)", comment: "Text Enc"), CFStringBuiltInEncodings.UTF32LE.rawValue),
		.separator,
		.charset(NSLocalizedString("Arabic (ISO 8859-6)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatinArabic.rawValue)),
		.charset(NSLocalizedString("Arabic (Windows-1256)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)),
		.charset(NSLocalizedString("Arabic (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macArabic.rawValue)),
		.separator,
		.charset(NSLocalizedString("Baltic (ISO 8859-4)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatin4.rawValue)),
		.charset(NSLocalizedString("Baltic (ISO 8859-13)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatin7.rawValue)),
		.charset(NSLocalizedString("Baltic (Windows-1257)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.windowsBalticRim.rawValue)),
		.separator,
		.charset(NSLocalizedString("Celtic (ISO 8859-14)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatin8.rawValue)),
		.charset(NSLocalizedString("Celtic (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macCeltic.rawValue)),
		.separator,
		.charset(NSLocalizedString("Central Europe (ISO 8859-2)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatin2.rawValue)),
		.charset(NSLocalizedString("Central Europe (ISO 8859-16)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatin10.rawValue)),
		.charset(NSLocalizedString("Central Europe (Windows-1250)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.windowsLatin2.rawValue)),
		.charset(NSLocalizedString("Central Europe (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macCentralEurRoman.rawValue)),
		.separator,
		.charset(NSLocalizedString("Chinese Simplified (GB18030)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)),
		.charset(NSLocalizedString("Chinese Simplified (ISO 2022)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.ISO_2022_CN.rawValue)),
		.charset(NSLocalizedString("Chinese Simplified (EUC)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.EUC_CN.rawValue)),
		.charset(NSLocalizedString("Chinese Simplified (Windows-936)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.dosChineseSimplif.rawValue)),
		.charset(NSLocalizedString("Chinese Simplified (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macChineseSimp.rawValue)),
		.separator,
		.charset(NSLocalizedString("Chinese Traditional (Big5)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.big5.rawValue)),
		.charset(NSLocalizedString("Chinese Traditional (Big5 HKSCS)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)),
		.charset(NSLocalizedString("Chinese Traditional (EUC)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.EUC_TW.rawValue)),
		.charset(NSLocalizedString("Chinese Traditional (Windows-950)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.dosChineseTrad.rawValue)),
		.charset(NSLocalizedString("Chinese Traditional (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macChineseTrad.rawValue)),
		.separator,
		.charset(NSLocalizedString("Cyrillic (ISO 8859-5)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatinCyrillic.rawValue)),
		.charset(NSLocalizedString("Cyrillic (Windows-1251)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue)),
		.charset(NSLocalizedString("Cyrillic (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macCyrillic.rawValue)),
		.charset(NSLocalizedString("Cyrillic (KOI8-R)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.KOI8_R.rawValue)),
		.charset(NSLocalizedString("Cyrillic (KOI8-U)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.KOI8_U.rawValue)),
		.separator,
		.charset(NSLocalizedString("Greek (ISO 8859-7)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatinGreek.rawValue)),
		.charset(NSLocalizedString("Greek (Windows-1253)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.windowsGreek.rawValue)),
		.charset(NSLocalizedString("Greek (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macGreek.rawValue)),
		.separator,
		.charset(NSLocalizedString("Hebrew (ISO 8859-8)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatinHebrew.rawValue)),
		.charset(NSLocalizedString("Hebrew (Windows-1255)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.windowsHebrew.rawValue)),
		.charset(NSLocalizedString("Hebrew (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macHebrew.rawValue)),
		.separator,
		.charset(NSLocalizedString("Japanese (Shift-JIS)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)),
		.charset(NSLocalizedString("Japanese (ISO 2022)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.ISO_2022_JP.rawValue)),
		.charset(NSLocalizedString("Japanese (EUC)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.EUC_JP.rawValue)),
		.charset(NSLocalizedString("Japanese (Windows-932)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)),
		.charset(NSLocalizedString("Japanese (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macJapanese.rawValue)),
		.separator,
		.charset(NSLocalizedString("Korean (ISO 2022)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.ISO_2022_KR.rawValue)),
		.charset(NSLocalizedString("Korean (EUC)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)),
		.charset(NSLocalizedString("Korean (Windows-949)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.dosKorean.rawValue)),
		.charset(NSLocalizedString("Korean (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macKorean.rawValue)),
		.separator,
		.charset(NSLocalizedString("South Europe (ISO 8859-3)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatin3.rawValue)),
		.separator,
		.charset(NSLocalizedString("Thai (ISO 8859-11)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatinThai.rawValue)),
		.charset(NSLocalizedString("Thai (Windows-874/TIS-620)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.dosThai.rawValue)),
		.charset(NSLocalizedString("Thai (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macThai.rawValue)),
		.separator,
		.charset(NSLocalizedString("Turkish (ISO 8859-9)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatin5.rawValue)),
		.charset(NSLocalizedString("Turkish (Windows-1254)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue)),
		.charset(NSLocalizedString("Turkish (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macTurkish.rawValue)),
		.separator,
		.charset(NSLocalizedString("Vietnamese (Windows-1258)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.windowsVietnamese.rawValue)),
		.charset(NSLocalizedString("Vietnamese (Mac)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.macVietnamese.rawValue)),
		.separator,
		.charset(NSLocalizedString("Western Europe (ISO 8859-1)", comment: "Text Enc"), CFStringBuiltInEncodings.isoLatin1.rawValue),
		.charset(NSLocalizedString("Western Europe (ISO 8859-15)", comment: "Text Enc"), CFStringEncoding(CFStringEncodings.isoLatin9.rawValue)),
		.charset(NSLocalizedString("Western Europe (Windows-1252)", comment: "Text Enc"), CFStringBuiltInEncodings.windowsLatin1.rawValue),
		.charset(NSLocalizedString("Western Europe (Mac)", comment: "Text Enc"), CFStringBuiltInEncodings.macRoman.rawValue),
	]

	@objc func appendCharsetList() {
		for entry in NSMenu.charsetList {
			switch entry {
			case .separator:
				addItem(.separator())
			case .charset(let title, let encoding):
				let item = NSMenuItem()
				item.title = title
				item.tag = Int(encoding)
				item.isEnabled = true
				addItem(item)
			}
		}
	}

	@objc(getFontItemFromURL:) func getFontItem(from url: CFURL) -> NSMenuItem? {
		// get descs from url
		guard let fonts = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
			  // get the first desc
			  let fontDesc = fonts.first,
			  // get family name (localized), and the url
			  let familyName = CTFontDescriptorCopyLocalizedAttribute(fontDesc, kCTFontFamilyNameAttribute, nil) as? String,
			  let fontURL = CTFontDescriptorCopyAttribute(fontDesc, kCTFontURLAttribute) as? URL else { return nil }

		let item = NSMenuItem()
		item.title = familyName
		// set url as rep
		item.representedObject = fontURL.path
		return item
	}

	@objc(getFontItemFromFamilyName:) func getFontItem(fromFamilyName name: CFString) -> NSMenuItem? {
		// the .name font should be hidden
		guard CFStringGetCharacterAtIndex(name, 0) != UInt16(UnicodeScalar(".").value) else { return nil }

		// create desc from attribute
		let attr = [kCTFontFamilyNameAttribute: name] as CFDictionary
		let fontDesc = CTFontDescriptorCreateWithAttributes(attr)

		// get family name (localized), url and font format
		guard let familyName = CTFontDescriptorCopyLocalizedAttribute(fontDesc, kCTFontFamilyNameAttribute, nil) as? String,
			  let fontURL = CTFontDescriptorCopyAttribute(fontDesc, kCTFontURLAttribute) as? URL,
			  let format = CTFontDescriptorCopyAttribute(fontDesc, kCTFontFormatAttribute) as? NSNumber else { return nil }

		// only accept ttf and ttc
		let accepted: Set<UInt32> = [UInt32(CTFontFormat.openTypePostScript.rawValue),
									 UInt32(CTFontFormat.openTypeTrueType.rawValue),
									 UInt32(CTFontFormat.trueType.rawValue)]
		guard accepted.contains(format.uint32Value) else { return nil }

		let item = NSMenuItem()
		let menuFont = CTFontCreateWithFontDescriptor(fontDesc, 14, nil)
		item.attributedTitle = NSAttributedString(string: familyName,
												  attributes: [.font: menuFont])
		item.representedObject = fontURL.path
		return item
	}
}
