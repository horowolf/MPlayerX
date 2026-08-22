/*
 * MPlayerX - SubConverter.swift
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

// Was SubConverter.h/.m. The delegate protocol itself (SubConverterDelegate)
// stays in coredef.h, which also declares SUBFILE_NAMERULE.
import Foundation

private let kWorkDirSubDir = "Subs"

/// The kCFStringEncoding* constants are a CFIndex-based enum in Swift, while
/// the conversion calls take a CFStringEncoding.
private func cfEncoding(_ encoding: CFStringEncodings) -> CFStringEncoding {
	CFStringEncoding(encoding.rawValue)
}

@objc(SubConverter)
class SubConverter: NSObject {

	@objc weak var delegate: SubConverterDelegate?

	private let textSubFileExts: Set<String> = ["utf", "utf8", "srt", "ass", "smi", "txt",
											    "ssa", "smil", "jss", "rt"]
	private var workDirectory: String?

	private let detector = UniversalDetector()
	/// Stands in for the original's @synchronized(detector): subtitle detection
	/// can be driven from more than one thread, and UniversalDetector carries
	/// parse state between -analyzeContentsOfFile: and -MIMECharset.
	private let detectorLock = NSRecursiveLock()

	override init() {
		super.init()
		detector.reset()
	}

	@objc func clearWorkDirectory() {
		guard let workDirectory = workDirectory else { return }

		try? FileManager.default.removeItem(atPath: (workDirectory as NSString).appendingPathComponent(kWorkDirSubDir))
	}

	@objc(setWorkDirectory:) func setWorkDirectory(_ wd: String?) {
		clearWorkDirectory()
		workDirectory = wd
	}

	/// Runs the detector over one file and lets the delegate override the
	/// result, which is how the "ask me about the charset" preference works.
	private func detectCharset(ofFile path: String) -> String? {
		detectorLock.lock()
		defer {
			detector.reset()
			detectorLock.unlock()
		}

		detector.analyzeContents(ofFile: path)
		var cpStr = detector.mimeCharset()

		if let delegate = delegate,
		   let cpPrefer = delegate.subConverter(self, detectedFile: path, ofCharsetName: cpStr,
											    confidence: detector.confidence()),
		   cpPrefer != cpStr {
			cpStr = cpPrefer
		}
		return cpStr
	}

	@objc(getCPOfTextSubtitle:) func getCPOfTextSubtitle(_ path: String?) -> String? {
		var isDir: ObjCBool = true

		guard let path = path,
			  FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue,
			  textSubFileExts.contains((path as NSString).pathExtension.lowercased()) else { return nil }

		return detectCharset(ofFile: path)
	}

	/// Returns the group of files converted to UTF-8 encoding based on the file
	/// names and encoding info in subEncDict; clearWorkDirectory must be called
	/// to clean them up.
	func convertTextSubsAndEncodings(_ subEncDict: [String: String]) -> [String] {
		guard let workDirectory = workDirectory else { return [] }

		let subDir = (workDirectory as NSString).appendingPathComponent(kWorkDirSubDir)
		let fm = FileManager.default
		var isDir: ObjCBool = false

		if fm.fileExists(atPath: subDir, isDirectory: &isDir) && !isDir.boolValue {
			// If it exists but is not a directory, remove the file first
			try? fm.removeItem(atPath: subDir)
		}

		if !isDir.boolValue {
			// If the directory did not exist originally, or a file existed there
			// instead, the directory needs to be (re)created
			guard (try? fm.createDirectory(atPath: subDir, withIntermediateDirectories: true)) != nil else {
				return []
			}
		}

		var newSubs: [String] = []

		for (subPathOld, enc) in subEncDict {
			// Convert the encoding string to the CF format first
			var ce = CFStringConvertIANACharSetNameToEncoding(enc as CFString)
			guard ce != kCFStringEncodingInvalidId else { continue }

			// First get the file path under workDir based on the original file name
			var subPathNew = (subDir as NSString).appendingPathComponent(
				(subPathOld as NSString).lastPathComponent.replacingOccurrences(of: ",", with: "_"))

			// Since name collisions are possible, find a file name that doesn't already exist
			var idx = 0
			var ext: String?
			var prefix: String?
			isDir = true

			while fm.fileExists(atPath: subPathNew, isDirectory: &isDir) && !isDir.boolValue {
				if ext == nil { ext = (subPathNew as NSString).pathExtension }
				if prefix == nil { prefix = (subPathNew as NSString).deletingPathExtension }

				subPathNew = "\(prefix!).mpx.\(idx).\(ext!)"
				idx += 1
			}

			// CP949 apparently always falls back to EUC_KR; map it back to
			// CP949 (kCFStringEncodingDOSKorean) here
			if ce == cfEncoding(.macKorean) || ce == cfEncoding(.EUC_KR) {
				ce = cfEncoding(.dosKorean)
			}

			// Transcode if it's valid
			var ne = CFStringConvertEncodingToNSStringEncoding(ce)
			var subFileOld = try? String(contentsOfFile: subPathOld, encoding: String.Encoding(rawValue: ne))

			if subFileOld == nil && ce == cfEncoding(.big5) {
				// If opening failed, the specified encoding might be problematic.
				// If it's Big5, try HKSCS as well
				ne = CFStringConvertEncodingToNSStringEncoding(cfEncoding(.big5_HKSCS_1999))
				subFileOld = try? String(contentsOfFile: subPathOld, encoding: String.Encoding(rawValue: ne))
			}

			// Since UCD can also guess wrong, the caller falls back to just
			// passing the charset to mplayer when nothing could be written here
			if let subFileOld = subFileOld,
			   (try? subFileOld.write(toFile: subPathNew, atomically: false, encoding: .utf8)) != nil {
				newSubs.append(subPathNew)
			}
		}
		return newSubs
	}

	func getCPFromMoviePath(_ moviePath: String, nameRule: SUBFILE_NAMERULE,
							alsoFindVobSub vobPath: inout String?) -> [String: String] {
		var subEncDict: [String: String] = [:]
		vobPath = nil

		// Directory path
		let directoryPath = (moviePath as NSString).deletingLastPathComponent
		// Name of the file being played
		let movieName = ((moviePath as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()

		guard let enumerator = FileManager.default.enumerator(atPath: directoryPath) else { return subEncDict }

		// Enumerate the directory containing the file being played
		for case let path as String in enumerator {
			// the lower case of the sub path
			let caseName = (path as NSString).deletingPathExtension.lowercased()
			let fileType = enumerator.fileAttributes?[.type] as? FileAttributeType

			if fileType == .typeDirectory {
				// Don't descend into subdirectories
				enumerator.skipDescendants()
				continue
			}
			guard fileType == .typeRegular else { continue }

			switch nameRule {
			case kSubFileNameRuleExactMatch:
				if movieName != caseName { continue } // exact match
			case kSubFileNameRuleAny:
				break // any sub file is OK
			case kSubFileNameRuleContain:
				if caseName.range(of: movieName) == nil { continue } // contain the movieName
			default:
				continue
			}

			let subPath = (directoryPath as NSString).appendingPathComponent(path)
			let ext = (path as NSString).pathExtension.lowercased()

			if textSubFileExts.contains(ext) {
				// If it's a text subtitle file
				if let cpStr = detectCharset(ofFile: subPath) {
					subEncDict[subPath] = cpStr
				}
			} else if ext == "sub" {
				// If it's a vobsub and we're set to look for vobsub
				vobPath = subPath
			}
		}
		return subEncDict
	}
}
