/*
 * MPlayerX - PlayListController.swift
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

// Unlike the other six stage-C controllers, PlayListController has no dialog
// UI of its own (no xib, no window) -- it's pure filename-pattern-matching
// logic for "play next/previous episode in this folder" plus the two IBActions
// that drive it, so there's nothing here for SwiftUI to host.

import Cocoa

// A narrow protocol standing in for `PlayerController` (not yet ported to
// Swift) -- see OpenURLController's OpenURLFileLoading for why the full
// header can't go in the bridging header (import cycle through the
// generated MPlayerX-Swift.h).
@objc protocol PlayListPlayerAccess: AnyObject {
	var lastPlayedPath: URL? { get }
	func stop()
	func loadFiles(_ files: [String], fromLocal local: Bool)
	func displayOSDMessage(_ message: String)
}

// Scans `name` from the end backwards, returning the range of every maximal
// run of ASCII digits, in right-to-left discovery order (so callers see the
// least-significant digit group first). Operates on NSString/UTF-16 indices
// throughout, matching the original's `unichar`/`characterAtIndex:`-based
// scan exactly, rather than Swift's grapheme-cluster-based String.Index --
// irrelevant for real filenames, but keeps this a faithful mechanical port
// instead of a reinterpretation.
private func findDigitParts(_ name: NSString) -> [NSRange] {
	var ret: [NSRange] = []
	var location = name.length
	var length = 0

	while location > 0 {
		location -= 1
		let ch = name.character(at: location)
		if ch >= 0x30, ch <= 0x39 {
			length += 1
		} else if length > 0 {
			ret.append(NSRange(location: location + 1, length: length))
			length = 0
		}
	}
	if length > 0 {
		ret.append(NSRange(location: 0, length: length))
	}
	return ret
}

// Top-level regular files directly inside dirPath (subdirectories are
// skipped, not recursed into), optionally filtered by lowercased extension.
private func enumerateAllFiles(at dirPath: String, exts: NSSet?) -> [String] {
	guard let enumerator = FileManager.default.enumerator(atPath: dirPath) else { return [] }

	var ret: [String] = []
	for case let file as String in enumerator {
		guard let fileType = enumerator.fileAttributes?[.type] as? FileAttributeType else { continue }

		if fileType == .typeDirectory {
			enumerator.skipDescendants()
		} else if fileType == .typeRegular {
			if let exts {
				if exts.contains((file as NSString).pathExtension.lowercased()) {
					ret.append(file)
				}
			} else {
				ret.append(file)
			}
		}
	}
	return ret
}

private func isTimesOfTen(_ num: Int) -> Bool {
	if num == 10 || num == 0 || num == -10 {
		return true
	} else if num % 10 == 0 {
		return isTimesOfTen(num / 10)
	} else {
		return false
	}
}

private func getFirstDigitPart(_ str: NSString) -> String? {
	var i = 0
	let len = str.length
	while i < len {
		let ch = str.character(at: i)
		if !(ch >= 0x30 && ch <= 0x39) { break }
		i += 1
	}
	return i != 0 ? str.substring(to: i) : nil
}

@objc(PlayListController)
class PlayListController: NSObject {

	// The ObjC original enforced a true singleton by overriding +alloc/
	// +allocWithZone:/-retain/-release so that nib-loading *and*
	// +sharedPlayListController always resolved to the same object -- Swift
	// doesn't allow overriding +alloc/+allocWithZone: at all (it's marked
	// unavailable), so that exact trick can't be ported. Instead, init()
	// records `self` as the shared instance the first time it runs. This
	// still gives both access paths the same object in practice: MainMenu.xib
	// (which wires this class's `playerController` outlet via a top-level
	// <customObject>) always finishes loading well before anything could call
	// sharedPlayListController() -- that only happens from PlayerController.m's
	// playbackStopped:, which can't fire until actual playback has occurred.
	private static var shared: PlayListController?

	@objc(sharedPlayListController)
	static func sharedInstance() -> PlayListController {
		shared ?? PlayListController()
	}

	@IBOutlet weak var playerController: PlayListPlayerAccess?

	// Atomically reads requestingNextOrPrev and resets it to NO. Must be used
	// instead of the property + a separate reset, since the reset after
	// -loadFiles: races with the async mplayer-task-termination delegate
	// callback on modern macOS (see playNext(_:)/playPrevious(_:)).
	private(set) var requestingNextOrPrev = false

	override init() {
		super.init()
		if Self.shared == nil {
			Self.shared = self
		}
	}

	@objc(consumeRequestingNextOrPrev)
	func consumeRequestingNextOrPrev() -> Bool {
		let requesting = requestingNextOrPrev
		requestingNextOrPrev = false
		return requesting
	}

	@IBAction @objc(playNext:)
	func playNext(_ sender: Any) {
		guard let lastURL = playerController?.lastPlayedPath else { return }

		guard lastURL.isFileURL else {
			playerController?.displayOSDMessage(NSLocalizedString("Local files only", comment: "Playlist OSD hint"))
			return
		}

		let playableFormats = AppController.shared()?.playableFormats
		if let nextPath = Self.searchNextMoviePath(from: lastURL.path, inFormats: playableFormats as NSSet?) {
			// requestingNextOrPrev is consumed (and reset) by PlayerController's
			// playbackStopped: once the old mplayer task's termination delegate call
			// actually arrives -- that callback isn't guaranteed to happen synchronously
			// within -stop, so resetting the flag here right after -loadFiles: returns
			// could race ahead of it and cause the window to get resized as if this were
			// a fresh open instead of a continuous-play switch.
			requestingNextOrPrev = true
			playerController?.stop()
			playerController?.loadFiles([nextPath], fromLocal: true)
		} else {
			playerController?.displayOSDMessage(NSLocalizedString("No next episode", comment: "Playlist OSD hint"))
		}
	}

	@IBAction @objc(playPrevious:)
	func playPrevious(_ sender: Any) {
		guard let lastURL = playerController?.lastPlayedPath else { return }

		guard lastURL.isFileURL else {
			playerController?.displayOSDMessage(NSLocalizedString("Local files only", comment: "Playlist OSD hint"))
			return
		}

		let playableFormats = AppController.shared()?.playableFormats
		if let nextPath = Self.searchPreviousMoviePath(from: lastURL.path, inFormats: playableFormats as NSSet?) {
			// see the comment in playNext(_:) about why the reset happens in
			// -[PlayerController playbackStopped:] instead of here
			requestingNextOrPrev = true
			playerController?.stop()
			playerController?.loadFiles([nextPath], fromLocal: true)
		} else {
			playerController?.displayOSDMessage(NSLocalizedString("No previous episode", comment: "Playlist OSD hint"))
		}
	}

	@objc(SearchNextMoviePathFrom:inFormats:)
	static func searchNextMoviePath(from path: String?, inFormats exts: NSSet?) -> String? {
		guard let path else { return nil }

		var nextPath: String?

		let movieNameNS = ((path as NSString).lastPathComponent as NSString).deletingPathExtension as NSString
		let dirPath = (path as NSString).deletingLastPathComponent
		let digitRangeArray = findDigitParts(movieNameNS)

		var lastRange = NSRange(location: NSNotFound, length: 0)
		var filesCandidates: [String]?

		outer: for digitRange0 in digitRangeArray {
			var digitRange = digitRange0

			let currentValue = Int(movieNameNS.substring(with: digitRange)) ?? 0
			let idxNext = String(currentValue + 1)

			let idxNextLen = idxNext.count
			if idxNextLen < digitRange.length {
				digitRange.location += (digitRange.length - idxNextLen)
				digitRange.length = idxNextLen
			}

			for i in 0..<3 {
				let fileNamePrefix: String

				switch i {
				case 0:
					// match with padding, e.g. 0001
					guard lastRange.length > 1 else { continue }
					let digitLast = digitRange.location + digitRange.length
					let padded = String(format: "%0\(lastRange.length)d", 1)
					fileNamePrefix = movieNameNS.substring(to: digitRange.location) + idxNext
						+ movieNameNS.substring(with: NSRange(location: digitLast, length: lastRange.location - digitLast))
						+ padded
				case 1:
					// match unpadded, e.g. 1
					guard lastRange.length > 0 else { continue }
					let digitLast = digitRange.location + digitRange.length
					fileNamePrefix = movieNameNS.substring(to: digitRange.location) + idxNext
						+ movieNameNS.substring(with: NSRange(location: digitLast, length: lastRange.location - digitLast))
						+ "1"
				default:
					// plain increment
					fileNamePrefix = movieNameNS.substring(to: digitRange.location) + idxNext
				}

				if filesCandidates == nil {
					filesCandidates = enumerateAllFiles(at: dirPath, exts: exts)
				}

				for name in filesCandidates! {
					let rng = (name as NSString).range(of: fileNamePrefix, options: [.caseInsensitive, .anchored])
					if rng.length != 0 {
						nextPath = (dirPath as NSString).appendingPathComponent(name)
						break outer
					}
				}
			}

			lastRange = digitRange
		}

		return nextPath
	}

	@objc(SearchPreviousMoviePathFrom:inFormats:)
	static func searchPreviousMoviePath(from path: String?, inFormats exts: NSSet?) -> String? {
		guard let path else { return nil }

		var nextPath: String?

		let movieNameNS = ((path as NSString).lastPathComponent as NSString).deletingPathExtension as NSString
		let dirPath = (path as NSString).deletingLastPathComponent
		let digitRangeArray = findDigitParts(movieNameNS)

		var lastRange = NSRange(location: NSNotFound, length: 0)
		var filesCandidates: [String]?

		outer: for digitRange0 in digitRangeArray {
			var digitRange = digitRange0
			let idxNow = Int(movieNameNS.substring(with: digitRange)) ?? 0

			if idxNow > 1 {
				let idxNext = String(idxNow - 1)
				var idxNextLen = idxNext.count
				// subtraction doesn't hold here, 10 - 1 = 9 or 09
				let isTen = isTimesOfTen(idxNow)
				if isTen { idxNextLen += 1 }

				// if this index's length is shorter than the previous one, that means there's padding
				if idxNextLen < digitRange.length {
					digitRange.location += (digitRange.length - idxNextLen)
					digitRange.length = idxNextLen
				}

				if lastRange.length > 0, (Int(movieNameNS.substring(with: lastRange)) ?? 0) == 1 {
					// if it's not the last field, and the previous field is 1, that means
					// we've reached the first episode of a season, need to find the last
					// episode of the previous season
					if filesCandidates == nil {
						filesCandidates = enumerateAllFiles(at: dirPath, exts: exts)
					}

					var maxNum = 0

					for i in 0..<2 {
						let idxNextTemp: String
						if i == 1 {
							// if it's a power of 10, also need to probe the possibility of 099
							guard isTen else { continue }
							idxNextTemp = "0" + idxNext
						} else {
							idxNextTemp = idxNext
						}

						let digitLast = digitRange.location + digitRange.length
						let fileNamePrefix = movieNameNS.substring(to: digitRange.location) + idxNextTemp
							+ movieNameNS.substring(with: NSRange(location: digitLast, length: lastRange.location - digitLast))

						for name in filesCandidates! {
							// search not including the digit, for now
							let rng = (name as NSString).range(of: fileNamePrefix, options: [.caseInsensitive, .anchored])
							if rng.length != 0 {
								// found the name, get the lastDigit string, and keep the max value
								let remainder = (name as NSString).substring(from: rng.length + rng.location) as NSString
								if let digitMax = getFirstDigitPart(remainder), let digitMaxVal = Int(digitMax), digitMaxVal > maxNum {
									maxNum = digitMaxVal
									nextPath = (dirPath as NSString).appendingPathComponent(name)
								}
							}
						}

						// after iterating through all files
						if nextPath != nil {
							break outer
						}
					}
				} else {
					// if it's not 1, it might be a meaningless field, or just an ordinary
					// episode, or the last field
					for i in 0..<2 {
						let idxNextTemp: String
						if i == 1 {
							guard isTen else { continue }
							idxNextTemp = "0" + idxNext
						} else {
							idxNextTemp = idxNext
						}

						let fileNamePrefix = movieNameNS.substring(to: digitRange.location) + idxNextTemp

						if filesCandidates == nil {
							filesCandidates = enumerateAllFiles(at: dirPath, exts: exts)
						}

						// fuzzy matching
						for name in filesCandidates! {
							let rng = (name as NSString).range(of: fileNamePrefix, options: [.caseInsensitive, .anchored])
							if rng.length != 0 {
								nextPath = (dirPath as NSString).appendingPathComponent(name)
								break outer
							}
						}
					}
				}
			}

			lastRange = digitRange
		}

		return nextPath
	}
}
