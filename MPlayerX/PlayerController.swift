/*
 * MPlayerX - PlayerController.swift
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
import IOKit.pwr_mgt

// These four mplayer-binary-selection constants and kMPXPowerSaveAssertion
// were `NSString * const` globals in the ObjC original, declared only in
// PlayerController.m (not the header), so nothing outside this file ever
// referenced the symbols -- only their string values matter.
private let kMPCMplayerNameMT = "mplayer-mt"
private let kMPCMplayerName = "mplayer"
private let kMPCFMTMplayerPathM32 = "binaries/m32/%@"
private let kMPCFMTMplayerPathX64 = "binaries/x86_64/%@"
private let kMPCFMTMplayerPathArm64 = "binaries/arm64/%@"
private let kMPCFFMpegProtoHead = "ffmpeg://"
private let kMPXPowerSaveAssertion = "MPlayerX is in playback."

private let kThreadsNumMax: UInt32 = 8

/** state of APN (auto play next) */
private let kMPCAutoPlayStateInvalid = 0
private let kMPCAutoPlayStateJustFound = 1
private let kMPCAutoPlayStatePlaying = 2

private func isNetworkPath(_ path: String) -> Bool {
	var buf = statfs()
	guard statfs(path, &buf) == 0 else { return false }

	let fsType = withUnsafeBytes(of: &buf.f_fstypename) { rawBuf -> String in
		String(cString: rawBuf.baseAddress!.assumingMemoryBound(to: CChar.self))
	}.lowercased()

	let networkPrefixes = ["nfs", "afp", "smb", "web", "ftp"]
	let isNetwork = networkPrefixes.contains { fsType.hasPrefix($0) }
	if isNetwork {
		MPLogString("Actually a network path:\(fsType)")
	}
	return isNetwork
}

@objc(PlayerController)
class PlayerController: NSObject, CoreControllerDelegate, SubConverterDelegate {
	private let ud = UserDefaults.standard
	private let notifCenter = NotificationCenter.default

	private let mplayer = CoreController()
	@objc private(set) var lastPlayedPath: URL?
	private var lastPlayedPathPre: URL?

	private var kvoSetuped = false
	private var autoPlayState = kMPCAutoPlayStateInvalid

	private var nonSleepHandler: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)

	@IBOutlet weak var controlUI: ControlUIView?
	@IBOutlet weak var openUrlController: OpenURLController?
	@IBOutlet weak var charsetController: CharsetQueryController?

	// Equivalent of the ObjC original's +initialize (see CharsetQueryController
	// for why this lazily-evaluated static stands in for it in Swift).
	private static let registerDefaultsOnce: Void = {
		var defaults: [String: Any] = [:]

		defaults[kUDKeyAutoPlayNext] = true
		defaults[kUDKeySubFontPath] = kMPCDefaultSubFontPath
		defaults[kUDKeyPrefer64bitMPlayer] = true
		defaults[kUDKeyEnableMultiThread] = true
		defaults[kUDKeySubScale] = Float(1.0)
		defaults[kUDKeySubScaleStepValue] = Float(0.1)
		defaults[kUDKeySubFontColor] = NSArchiver.archivedData(withRootObject: NSColor(calibratedWhite: 1.0, alpha: 1.00))
		defaults[kUDKeySubFontBorderColor] = NSArchiver.archivedData(withRootObject: NSColor(calibratedWhite: 0.0, alpha: 0.85))
		defaults[kUDKeyForceIndex] = false
		defaults[kUDKeySubFileNameRule] = UInt32(kSubFileNameRuleContain.rawValue)
		defaults[kUDKeyDTSPassThrough] = false
		defaults[kUDKeyAC3PassThrough] = false

		defaults[kUDKeyThreadNum] = UInt32(ProcessInfo.processInfo.processorCount)
		defaults[kUDKeyUseEmbeddedFonts] = true
		defaults[kUDKeyCacheSize] = UInt32(10000)
		defaults[kUDKeyCacheSizeLocalMinLimit] = UInt32(5000)
		defaults[kUDKeyCacheSizeLocalTime] = UInt32(20)
		defaults[kUDKeyPreferIPV6] = true
		defaults[kUDKeyLetterBoxMode] = UInt32(kPMLetterBoxModeNotDisplay)
		defaults[kUDKeyLetterBoxModeAlt] = UInt32(kPMLetterBoxModeBoth)
		defaults[kUDKeyLetterBoxHeight] = Float(0.1)
		defaults[kUDKeyPlayWhenOpened] = true
		defaults[kUDKeyOverlapSub] = true
		defaults[kUDKeyRtspOverHttp] = true

		defaults[kUDKeyMixToStereoMode] = UInt32(kPMMixDTS5_1ToStereo)
		defaults[kUDKeyAutoResume] = true
		defaults[kUDKeyImgEnhanceMethod] = UInt32(kPMImgEnhanceNone)
		defaults[kUDKeyDeIntMethod] = UInt32(kPMDeInterlaceNone)
		defaults[kUDKeyExtraOptions] = ""
		defaults[kUDKeySubAlign] = UInt32(kPMSubAlignDefault)
		defaults[kUDKeySubBorderWidth] = UInt32(kPMSubBorderWidthDefault)
		defaults[kUDKeyAssSubMarginV] = UInt32(kPMAssSubMarginVDefault)
		defaults[kUDKeyNoDispSub] = false
		defaults[kUDKeyAutoDetectSPDIF] = false
		defaults[kUDKeyEnableOpenRecentMenu] = true

		UserDefaults.standard.register(defaults: defaults)
	}()

	// MARK: Init/Dealloc

	override init() {
		super.init()
		_ = PlayerController.registerDefaultsOnce

		mplayer.delegate = self

		// TODO Need test
		/////////////////////////setup subconverter////////////////////
		let fm = FileManager.default
		var isDir: ObjCBool = false
		let workDir = FileManager.userPath(.applicationSupportDirectory, withSuffix: kMPCStringMPlayerX)

		if let workDir = workDir {
			if fm.fileExists(atPath: workDir, isDirectory: &isDir) && !isDir.boolValue {
				// If it exists but is not a folder
				try? fm.removeItem(atPath: workDir)
			}
			if !isDir.boolValue {
				// If this folder didn't exist before, or if a file exists there instead, the folder needs to be recreated
				if (try? fm.createDirectory(atPath: workDir, withIntermediateDirectories: true, attributes: nil)) == nil {
					mplayer.setWorkDirectory(nil)
				} else {
					mplayer.setWorkDirectory(workDir)
				}
			} else {
				mplayer.setWorkDirectory(workDir)
			}
		} else {
			mplayer.setWorkDirectory(nil)
		}
		mplayer.setSubConverterDelegate(self)

		let subFontPath = ud.string(forKey: kUDKeySubFontPath)

		if subFontPath != (kMPCDefaultSubFontPath as String) {
			// If it's not the default path
			var isDir: ObjCBool = true
			if let subFontPath = subFontPath,
			   (!fm.fileExists(atPath: subFontPath, isDirectory: &isDir)) || isDir.boolValue {
				ud.set(kMPCDefaultSubFontPath, forKey: kUDKeySubFontPath)
			}
		}

		/////////////////////////setup CoreController////////////////////
		setMultiThreadMode(ud.bool(forKey: kUDKeyEnableMultiThread))

		// Decide which arch of mplayer to use
		mplayer.pm.mplayerArch = preferredMPlayerArchKey()

		// Ask which parameters this mplayer supports
		mplayer.pm.supportedOptions = supportedOptionsOfMPlayer(atPath: mplayer.mpPathPair?[mplayer.pm.mplayerArch] as? String)

		lastPlayedPath = nil
		lastPlayedPathPre = nil

		kvoSetuped = false
		autoPlayState = kMPCAutoPlayStateInvalid
	}

	@objc func setupKVO() {
		guard !kvoSetuped else { return }

		for keyPath in kvoKeyPaths {
			mplayer.addObserver(self, forKeyPath: keyPath,
								 options: [.new, .initial], context: nil)
		}
		kvoSetuped = true
	}

	private let kvoKeyPaths: [String] = [
		kKVOPropertyKeyPathLength as String,
		kKVOPropertyKeyPathCurrentTime as String,
		kKVOPropertyKeyPathSeekable as String,
		kKVOPropertyKeyPathSpeed as String,
		kKVOPropertyKeyPathSubDelay as String,
		kKVOPropertyKeyPathAudioDelay as String,
		kKVOPropertyKeyPathSubInfo as String,
		kKVOPropertyKeyPathCachingPercent as String,
		kKVOPropertyKeyPathAudioInfo as String,
		kKVOPropertyKeyPathVideoInfo as String,
		kKVOPropertyKeyPathAudioInfoID as String,
		kKVOPropertyKeyPathVideoInfoID as String,
		kKVOPropertyKeyPathChapterInfo as String,
	]

	deinit {
		if kvoSetuped {
			for keyPath in kvoKeyPaths {
				mplayer.removeObserver(self, forKeyPath: keyPath)
			}
			kvoSetuped = false
		}

		if nonSleepHandler != IOPMAssertionID(kIOPMNullAssertionID) {
			IOPMAssertionRelease(nonSleepHandler)
			nonSleepHandler = IOPMAssertionID(kIOPMNullAssertionID)
		}
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if let object = object as? CoreController, object === mplayer {
			notifCenter.post(name: NSNotification.Name.mpcPlayInfoUpdated, object: self,
							  userInfo: [
								kMPCPlayInfoUpdatedKeyPathKey as String: keyPath ?? "",
								kMPCPlayInfoUpdatedChangeDictKey as String: change ?? [:],
							  ])
			return
		}
		super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
	}

	@objc(setDisplayDelegateForMPlayer:)
	func setDisplayDelegateForMPlayer(_ delegate: CoreDisplayDelegate?) -> Any {
		mplayer.dispDelegate = delegate
		return mplayer
	}

	@objc(playerState)
	func playerState() -> Int32 { return mplayer.state }

	private var playerCouldAcceptCommand: Bool { (mplayer.state & 0x0100) != 0 }

	@objc(couldAcceptCommand)
	func couldAcceptCommand() -> Bool { playerCouldAcceptCommand }

	@objc(mediaInfo)
	func mediaInfo() -> MovieInfo? { mplayer.movieInfo }

	@objc(setPlayDisk:)
	func setPlayDisk(_ pd: Int) { mplayer.pm.playDisk = pd }

	private func enablePowerSave(_ en: Bool) {
		if en {
			// to enable power save, release the assertion
			if nonSleepHandler != IOPMAssertionID(kIOPMNullAssertionID) {
				IOPMAssertionRelease(nonSleepHandler)
				nonSleepHandler = IOPMAssertionID(kIOPMNullAssertionID)
			}
		} else {
			// to disable power save, create the assertion
			if nonSleepHandler == IOPMAssertionID(kIOPMNullAssertionID) {
				let err = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
													   IOPMAssertionLevel(kIOPMAssertionLevelOn),
													   kMPXPowerSaveAssertion as CFString,
													   &nonSleepHandler)
				if err != kIOReturnSuccess {
					MPLogString("Can't disable powersave")
				}
			}
		}
	}

	@objc(loadFiles:fromLocal:)
	func loadFiles(_ files: [Any], fromLocal local: Bool) {
		let fm = FileManager.default

		autoreleasepool {
			for rawFile in files {
				var file: Any = rawFile

				// If it's a string, first convert it to a URL
				if let str = file as? String {
					if local {
						file = URL(fileURLWithPath: str, isDirectory: false)
					} else if let url = URL(string: str) {
						file = url
					} else {
						continue
					}
				}

				guard let url = file as? URL else { continue }

				if url.isFileURL {
					// If it's a local file
					let path = url.path
					var isDir: ObjCBool = true

					if fm.fileExists(atPath: path, isDirectory: &isDir) {
						if isDir.boolValue {
							// If it's a folder
							playMedia(url)
							break
						} else {
							// If the file exists
							let ext = (path as NSString).pathExtension.lowercased()

							if AppController.shared().playableFormats.contains(ext) {
								// If it's a supported format
								playMedia(url)
								break
							} else if AppController.shared().supportSubFormats.contains(ext) {
								// If it's a subtitle file
								if playerCouldAcceptCommand {
									// If playback is active, load the subtitle
									loadSubFile(path)
								} else {
									// If in the stopped state, the user probably wants to open a media file first
									// Need to search for a movie file based on the subtitle file name
									let autoSearchMediaFile = findFirstMediaFile(fromSubFile: path)

									if let autoSearchMediaFile = autoSearchMediaFile {
										// If found
										playMedia(autoSearchMediaFile)
									}
									// Whether or not it was found, need to break either way
									// If found, play it
									// If not found, it means no corresponding media file exists under the current filename rule
									if autoSearchMediaFile == nil {
										// If no suitable media file to play was found
										showAlertPanelModal(NSLocalizedString("Can't find a proper file to play", comment: ""))
									}
									break
								}
							} else {
								if NSEvent.modifierFlags.contains(.control) {
									// open the file while control key pressing
									// try to open the file
									playMedia(url)
									break
								} else {
									// Otherwise show a prompt
									showAlertPanelModal(NSLocalizedString("The file is not supported by MPlayerX.", comment: ""))
								}
							}
						}
					} else {
						// File doesn't exist
						showAlertPanelModal(NSLocalizedString("The file does not exist", comment: ""))
					}
				} else {
					// If it's not a local file
					playMedia(url)
					break
				}
			}
		}
	}

	private func playMedia(_ url: URL) {
		// Internal function, not that necessary to check the validity of url

		// Set the subtitle size
		mplayer.pm.subScale = ud.float(forKey: kUDKeySubScale)
		if let data = ud.object(forKey: kUDKeySubFontColor) as? Data {
			mplayer.pm.setSubFontColor(NSUnarchiver.unarchiveObject(with: data) as? NSColor)
		}
		if let data = ud.object(forKey: kUDKeySubFontBorderColor) as? Data {
			mplayer.pm.setSubFontBorderColor(NSUnarchiver.unarchiveObject(with: data) as? NSColor)
		}
		// Get the path to the subtitle font file
		let subFontPath = ud.string(forKey: kUDKeySubFontPath)

		if subFontPath == (kMPCDefaultSubFontPath as String) {
			// If it's the default path, some path prefix needs to be prepended
			mplayer.pm.subFont = Bundle.main.resourcePath.map { ($0 as NSString).appendingPathComponent(kMPCDefaultSubFontPath as String) }
		} else {
			// Otherwise set it directly
			mplayer.pm.subFont = subFontPath
		}

		mplayer.pm.forceIndex = ud.bool(forKey: kUDKeyForceIndex)
		mplayer.pm.subNameRule = SUBFILE_NAMERULE(rawValue: UInt32(ud.integer(forKey: kUDKeySubFileNameRule)))

		if ud.bool(forKey: kUDKeyAutoDetectSPDIF) {
			let digi = AODetector.default().isDigital
			mplayer.pm.dtsPass = digi
			mplayer.pm.ac3Pass = digi
		} else {
			mplayer.pm.dtsPass = ud.bool(forKey: kUDKeyDTSPassThrough)
			mplayer.pm.ac3Pass = ud.bool(forKey: kUDKeyAC3PassThrough)
		}
		mplayer.pm.useEmbeddedFonts = ud.bool(forKey: kUDKeyUseEmbeddedFonts)

		mplayer.pm.letterBoxMode = UInt32(ud.integer(forKey: kUDKeyLetterBoxMode))
		mplayer.pm.letterBoxHeight = ud.float(forKey: kUDKeyLetterBoxHeight)

		mplayer.pm.overlapSub = ud.bool(forKey: kUDKeyOverlapSub)
		mplayer.pm.mixToStereo = UInt32(ud.integer(forKey: kUDKeyMixToStereoMode))

		mplayer.pm.imgEnhance = UInt32(ud.integer(forKey: kUDKeyImgEnhanceMethod))
		mplayer.pm.deinterlace = UInt32(ud.integer(forKey: kUDKeyDeIntMethod))

		mplayer.pm.extraOptions = ud.string(forKey: kUDKeyExtraOptions)
		mplayer.pm.subAlign = UInt32(ud.integer(forKey: kUDKeySubAlign))
		mplayer.pm.subBorderWidth = UInt32(ud.integer(forKey: kUDKeySubBorderWidth))
		mplayer.pm.assSubMarginV = ud.integer(forKey: kUDKeyAssSubMarginV)

		if autoPlayState == kMPCAutoPlayStateJustFound {
			// when APN, do not pause at start
			mplayer.pm.pauseAtStart = false
		} else {
			mplayer.pm.pauseAtStart = !ud.bool(forKey: kUDKeyPlayWhenOpened)
		}

		mplayer.pm.noDispSub = ud.bool(forKey: kUDKeyNoDispSub)

		// Must retain here, otherwise there would be a problem if lastPlayedPath were passed in as the argument
		lastPlayedPathPre = url.absoluteURL

		let path: String

		if url.isFileURL {
			// local files
			path = url.path

			if isNetworkPath(path) {
				// is network path
				mplayer.pm.cache = UInt32(ud.integer(forKey: kUDKeyCacheSize))
				mplayer.pm.displayCacheLog = true
			} else {
				// local path
				// the local cache should use another value
				var cacheSize: UInt64 = 0
				let fileInfo = try? FileManager.default.attributesOfItem(atPath: path)

				if let fileInfo = fileInfo {
					// assuming one movie is 6000 seconds,
					let fileSize = (fileInfo[.size] as? NSNumber)?.uint64Value ?? 0
					cacheSize = fileSize * UInt64(ud.integer(forKey: kUDKeyCacheSizeLocalTime)) / 6000000
				}
				mplayer.pm.cache = UInt32(max(cacheSize, UInt64(ud.integer(forKey: kUDKeyCacheSizeLocalMinLimit))))
				mplayer.pm.displayCacheLog = false
			}
			mplayer.pm.rtspOverHttp = false

			// Add the file to the Recent Menu; only local files can be added
			if ud.bool(forKey: kUDKeyEnableOpenRecentMenu) {
				NSDocumentController.shared.noteNewRecentDocumentURL(url)
			}
		} else {
			// network stream
			path = url.absoluteString

			mplayer.pm.cache = UInt32(ud.integer(forKey: kUDKeyCacheSize))
			mplayer.pm.preferIPV6 = ud.bool(forKey: kUDKeyPreferIPV6)
			mplayer.pm.rtspOverHttp = ud.bool(forKey: kUDKeyRtspOverHttp)
			mplayer.pm.displayCacheLog = true

			// Add the URL to OpenURLController
			openUrlController?.addUrl(path)
		}

		var finalPath = path
		if !url.isFileURL {
			if ud.bool(forKey: kUDKeyFFMpegHandleStream) != (NSEvent.modifierFlags == .command) {
				finalPath = kMPCFFMpegProtoHead + path
			}
		}

		////////////////////////////////////////////////////////////////////
		// HACK!!! always try to use ffmpeg as the demuxer
		// EXCEPT real media
		let ext = (finalPath as NSString).pathExtension.lowercased()
		if ext == "rm" || ext == "rmvb" || ext == "ra" || ext == "ram" {
			mplayer.pm.demuxer = nil
		} else {
			mplayer.pm.demuxer = kPMValDemuxFFMpeg as String
		}
		////////////////////////////////////////////////////////////////////

		if ud.bool(forKey: kUDKeyAutoResume),
		   let stime = AppController.shared().bookmarks[lastPlayedPathPre!.absoluteString] as? NSNumber {
			// if AutoResume is ON and there was a record in the bookmarks
			// and 5s to help the users to remember where they left in the movie
			mplayer.pm.startTime = stime.floatValue - 5
		} else {
			mplayer.pm.startTime = -1
		}

		mplayer.playMedia(finalPath)

		lastPlayedPath = lastPlayedPathPre
		lastPlayedPathPre = nil

		////////////////////////////////////////////////////////////////////
		// Auto reset
		setPlayDisk(Int(kPMPlayDiskNone))
		////////////////////////////////////////////////////////////////////
	}

	private func findFirstMediaFile(fromSubFile path: String) -> URL? {
		// Need to get the latest value of nameRule first
		mplayer.pm.subNameRule = SUBFILE_NAMERULE(rawValue: UInt32(ud.integer(forKey: kUDKeySubFileNameRule)))

		// Get the latest nameRule
		let nameRule = mplayer.pm.subNameRule

		var mediaURL: URL?

		autoreleasepool {
			// Folder path
			let directoryPath = (path as NSString).deletingLastPathComponent
			// Subtitle file name
			let subName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()

			guard let directoryEnumerator = FileManager.default.enumerator(atPath: directoryPath) else { return }

			// Iterate over the directory the playback file is in
			for case let mediaFile as String in directoryEnumerator {
				let fileAttr = directoryEnumerator.fileAttributes
				let ext = (mediaFile as NSString).pathExtension.lowercased()

				if (fileAttr?[.type] as? FileAttributeType) == .typeDirectory {
					// don't recurse into subdirectories
					directoryEnumerator.skipDescendants()
				} else if (fileAttr?[.type] as? FileAttributeType) == .typeRegular,
						  AppController.shared().playableFormats.contains(ext) {
					// If it's a normal file, and it's a media file
					let mediaName = ((mediaFile as NSString).deletingPathExtension).lowercased()

					switch nameRule {
					case kSubFileNameRuleExactMatch:
						if mediaName != subName { continue } // exact match
					case kSubFileNameRuleAny:
						break // any sub file is OK
					case kSubFileNameRuleContain:
						if subName.range(of: mediaName) == nil { continue } // contain the movieName
					default:
						continue
					}
					// Reaching here means a suitable playback file was found, break out of the loop
					mediaURL = URL(fileURLWithPath: (directoryPath as NSString).appendingPathComponent(mediaFile), isDirectory: false)
					break
				}
			}
		}
		return mediaURL
	}

	@objc(setMultiThreadMode:)
	func setMultiThreadMode(_ mt: Bool) {
		let resPath = Bundle.main.resourcePath ?? ""

		let mplayerName: String
		var threadNum: UInt32

		if false /* mt */ {
			// use multi-threading
			threadNum = min(kThreadsNumMax, max(1, UInt32(ud.integer(forKey: kUDKeyThreadNum))))
			mplayerName = kMPCMplayerNameMT
		} else {
			threadNum = min(kThreadsNumMax, max(1, UInt32(ud.integer(forKey: kUDKeyThreadNum))))
			mplayerName = kMPCMplayerName
		}

		ud.set(threadNum, forKey: kUDKeyThreadNum)

		// temp hack for 1.0.10
		// the threads larger than 4 will bring out-of-sync
		// so limit it here to 4 and do not influence UI and Preference.
		if threadNum > 4 {
			threadNum = 4
		}
		mplayer.pm.threads = threadNum

		mplayer.mpPathPair = [
			kI386Key as String: (resPath as NSString).appendingPathComponent(String(format: kMPCFMTMplayerPathM32, mplayerName)),
			kX86_64Key as String: (resPath as NSString).appendingPathComponent(String(format: kMPCFMTMplayerPathX64, mplayerName)),
			kArm64Key as String: (resPath as NSString).appendingPathComponent(String(format: kMPCFMTMplayerPathArm64, mplayerName)),
		]
	}

	// MARK: cooperative actions with UI

	@objc func stop() {
		mplayer.performStop()
		// Once the window is closed, clear lastPlayPath so that even reopening the window won't play the previous file
		lastPlayedPath = nil
	}

	@objc func togglePlayPause() {
		if mplayer.state == kMPCStoppedState {
			// mplayer is not in the playing state
			if let lastPlayedPath = lastPlayedPath {
				// There is a file available to play
				playMedia(lastPlayedPath)
			}
		} else {
			// mplayer is currently playing
			mplayer.togglePause()

			if mplayer.state == kMPCPausedState {
				enablePowerSave(true)
			} else if mplayer.state == kMPCPlayingState {
				enablePowerSave(false)
			}
		}
	}

	@objc func frameStep() {
		mplayer.frameStep(1)
	}

	@objc(toggleMute)
	func toggleMute() -> Bool {
		if playerCouldAcceptCommand && !isPassingThrough() {
			return mplayer.setMute(!mplayer.movieInfo.playingInfo.mute)
		} else {
			return false
		}
	}

	@objc(setVolume:)
	func setVolume(_ vol: Float) -> Float {
		var vol = vol
		if isPassingThrough() {
			// if is passing through, do nothing
			// and return the current volume
			vol = mplayer.pm.volume
		} else {
			vol = mplayer.setVolume(vol)
			mplayer.pm.volume = vol
		}
		return vol
	}

	@objc(isPassingThrough)
	func isPassingThrough() -> Bool {
		var ret = false
		if playerCouldAcceptCommand {
			if let ai = mplayer.movieInfo.audioInfo(forID: mplayer.movieInfo.playingInfo.currentAudioID) {
				let format = (ai.format ?? "").uppercased()
				MPLogString("audio format:\(format)")
				if ((format == "0X2000" || format == "AC-3") && mplayer.pm.ac3Pass) ||
					((format == "0X2001" || format == "DTS") && mplayer.pm.dtsPass) {
					ret = true
				}
			}
		}
		return ret
	}

	@objc(seekTo:mode:)
	func seekTo(_ time: Float, mode seekMode: SEEK_MODE) -> Float {
		// playingInfo's currentTime is synced by reading the log, so it's not set directly here
		var time = time
		// `seekable != nil` is always true (movieInfo.seekable is a non-optional
		// NSNumber, defaulting to 0) -- this reproduces a pre-existing ObjC
		// quirk, not something introduced by this port: the original checked
		// `mplayer.movieInfo.seekable` as a bare pointer-truthiness test against
		// an NSNumber* property, which is likewise always true regardless of the
		// wrapped value. Not fixed here since it predates this stage and the
		// actual seek command is unconditionally sent either way today.
		if playerCouldAcceptCommand && (mplayer.movieInfo.seekable != nil) {
			if seekMode == kMPCSeekModeRelative {
				time -= mplayer.movieInfo.playingInfo.currentTime.floatValue
			}

			time = mplayer.setTimePos(time, mode: seekMode)
			mplayer.la.stop()
			return time
		}
		return -1
	}

	@objc(changeTimeBy:)
	func changeTimeBy(_ delta: Float) -> Float {
		// playingInfo's currentTime is synced by reading the log, so it's not set directly here
		// `seekable != nil` is always true (movieInfo.seekable is a non-optional
		// NSNumber, defaulting to 0) -- this reproduces a pre-existing ObjC
		// quirk, not something introduced by this port: the original checked
		// `mplayer.movieInfo.seekable` as a bare pointer-truthiness test against
		// an NSNumber* property, which is likewise always true regardless of the
		// wrapped value. Not fixed here since it predates this stage and the
		// actual seek command is unconditionally sent either way today.
		if playerCouldAcceptCommand && (mplayer.movieInfo.seekable != nil) {
			let delta = mplayer.setTimePos(delta, mode: kMPCSeekModeRelative)
			mplayer.la.stop()
			return delta
		}
		return -1
	}

	@objc(changeSpeedBy:)
	func changeSpeedBy(_ delta: Float) -> Float {
		if playerCouldAcceptCommand {
			mplayer.setSpeed(mplayer.movieInfo.playingInfo.speed.floatValue + delta)
		}
		return mplayer.movieInfo.playingInfo.speed.floatValue
	}

	@objc(changeSubDelayBy:)
	func changeSubDelayBy(_ delta: Float) -> Float {
		if playerCouldAcceptCommand {
			mplayer.setSubDelay(mplayer.movieInfo.playingInfo.subDelay.floatValue + delta)
		}
		return mplayer.movieInfo.playingInfo.subDelay.floatValue
	}

	@objc(changeAudioDelayBy:)
	func changeAudioDelayBy(_ delta: Float) -> Float {
		if playerCouldAcceptCommand {
			mplayer.setAudioDelay(mplayer.movieInfo.playingInfo.audioDelay.floatValue + delta)
		}
		return mplayer.movieInfo.playingInfo.audioDelay.floatValue
	}

	@objc(changeSubScaleBy:)
	func changeSubScaleBy(_ delta: Float) -> Float {
		if playerCouldAcceptCommand {
			mplayer.setSubScale(mplayer.movieInfo.playingInfo.subScale.floatValue + delta)
		}
		return mplayer.movieInfo.playingInfo.subScale.floatValue
	}

	@objc(changeSubPosBy:)
	func changeSubPosBy(_ delta: Float) -> Float {
		if playerCouldAcceptCommand {
			mplayer.setSubPos(mplayer.movieInfo.playingInfo.subPos + delta * 100)
		}
		return mplayer.movieInfo.playingInfo.subPos
	}

	@objc(changeAudioBalanceBy:)
	func changeAudioBalanceBy(_ delta: Float) -> Float {
		if playerCouldAcceptCommand {
			mplayer.setBalance(mplayer.movieInfo.playingInfo.audioBalance + delta)
		}
		return mplayer.movieInfo.playingInfo.audioBalance
	}

	@objc(setSpeed:)
	func setSpeed(_ spd: Float) -> Float {
		if playerCouldAcceptCommand {
			mplayer.setSpeed(spd)
		}
		return mplayer.movieInfo.playingInfo.speed.floatValue
	}

	@objc(setSubDelay:)
	func setSubDelay(_ sd: Float) -> Float {
		if playerCouldAcceptCommand {
			mplayer.setSubDelay(sd)
		}
		return mplayer.movieInfo.playingInfo.subDelay.floatValue
	}

	@objc(setAudioDelay:)
	func setAudioDelay(_ ad: Float) -> Float {
		if playerCouldAcceptCommand {
			mplayer.setAudioDelay(ad)
		}
		return mplayer.movieInfo.playingInfo.audioDelay.floatValue
	}

	@objc(setSubtitle:)
	func setSubtitle(_ subID: Int32) {
		mplayer.setSub(subID)
	}

	@objc(setAudio:)
	func setAudio(_ audioID: Int32) {
		mplayer.setAudio(audioID)
	}

	@objc(setAudioBalance:)
	func setAudioBalance(_ bal: Float) {
		mplayer.setBalance(bal)
	}

	@objc(setVideo:)
	func setVideo(_ videoID: Int32) {
		mplayer.setVideo(videoID)
	}

	@objc(loadSubFile:)
	func loadSubFile(_ subPath: String) {
		mplayer.loadSubFile(subPath)
	}

	@objc(setLetterBox:top:bottom:)
	func setLetterBox(_ renderSubInLB: Bool, top topRatio: Float, bottom bottomRatio: Float) {
		if playerCouldAcceptCommand {
			mplayer.setLetterBox(renderSubInLB, top: topRatio, bottom: bottomRatio)
		}
	}

	@objc(setEqualizer:)
	func setEqualizer(_ amps: [Any]?) {
		if playerCouldAcceptCommand {
			mplayer.setEqualizer(amps)
		}
		mplayer.pm.equalizer = amps
	}

	@objc(mapAudioChannelsTo:)
	func mapAudioChannelsTo(_ mode: Int) {
		if playerCouldAcceptCommand {
			mplayer.mapAudioChannelsTo(mode)
		}
	}

	@objc(setExternalAudioFilePath:)
	func setExternalAudioFilePath(_ path: String?) {
		mplayer.pm.audioFilePath = path
	}

	// MARK: private methods

	private func preferredMPlayerArchKey() -> String {
		// The keys are tried in order and the first one whose binary is actually
		// present in the bundle wins. Compile-time detection is enough here: the
		// app ships as a universal binary, so the arm64 slice only ever runs on
		// Apple Silicon and the x86_64 slice only on Intel (or under Rosetta,
		// where an x86_64 mplayer is the right choice anyway).
		let candidates: [String]

		#if arch(arm64)
		// Native first, then the Intel build as a Rosetta fallback.
		candidates = [kArm64Key as String, kX86_64Key as String]
		#else
		// 32bit mplayer only remains usable on macOS 10.14 and earlier.
		candidates = ud.bool(forKey: kUDKeyPrefer64bitMPlayer) ?
			[kX86_64Key as String, kI386Key as String] :
			[kI386Key as String, kX86_64Key as String]
		#endif

		let fm = FileManager.default
		let pathPair = mplayer.mpPathPair

		for key in candidates {
			if let path = pathPair?[key] as? String, fm.isExecutableFile(atPath: path) {
				return key
			}
		}

		// Nothing usable was found; return the preferred key anyway so that the
		// failure surfaces as a normal playback error instead of a silent no-op.
		return candidates[0]
	}

	private func supportedOptionsOfMPlayer(atPath path: String?) -> NSSet? {
		// MPlayerX was developed against a privately patched mplayer that
		// understood a handful of options upstream never had (-nodispclog,
		// -stpause, -subid). Passing one of those to a stock mplayer makes it
		// refuse to start, so ask the binary what it accepts and let
		// ParameterManager leave out anything it does not.
		//
		// Returning nil means "assume everything is supported", which reproduces
		// the behaviour MPlayerX had before this check existed.
		guard let path = path, FileManager.default.isExecutableFile(atPath: path) else {
			return nil
		}

		let task = Process()
		let pipe = Pipe()
		var output: Data?

		task.launchPath = path
		task.arguments = ["-list-options"]
		task.standardOutput = pipe
		task.standardError = FileHandle.nullDevice
		task.standardInput = FileHandle.nullDevice

		do {
			// .run() (rather than .launch()) surfaces a launch failure as a
			// catchable Swift Error instead of an uncatchable NSException.
			try task.run()
			output = pipe.fileHandleForReading.readDataToEndOfFile()
			task.waitUntilExit()
		} catch {
			MPLogString("could not query mplayer options: \(error)")
			return nil
		}

		guard let output = output, !output.isEmpty else {
			return nil
		}

		guard let text = String(data: output, encoding: .utf8) else {
			return nil
		}

		var opts = Set<String>()
		let ws = CharacterSet.whitespaces

		for line in text.components(separatedBy: "\n") {
			// Every option line starts with whitespace, then the option name.
			// Anything else is a banner or a table header.
			guard let first = line.unicodeScalars.first, ws.contains(first) else {
				continue
			}

			guard var name = line.trimmingCharacters(in: ws).components(separatedBy: ws).first else {
				continue
			}

			// Suboption groups are listed as "name:suboption"; keep the group name.
			name = name.components(separatedBy: ":").first ?? name
			// Options taking a list are listed with a trailing '*'.
			if name.hasSuffix("*") {
				name = String(name.dropLast())
			}

			if !name.isEmpty {
				opts.insert(name)
			}
		}

		// A parse that found almost nothing means the output was not what we
		// expected; do not start dropping options on the strength of that.
		if opts.count < 50 {
			MPLogString("unexpected -list-options output (\(opts.count) entries); not filtering")
			return nil
		}

		return opts as NSSet
	}

	// MARK: MPlayer Notifications (CoreControllerDelegate)

	func playbackOpened(_ coreController: Any!) {
		// When the mplayer in use has no -stpause, the process starts playing and
		// is paused here instead. Upstream mplayer has never had a start-paused
		// option; only MPlayerX's own build did.
		if mplayer.pm.pauseAtStart && !mplayer.pm.supportsStartPausedOption() {
			mplayer.togglePause()
		}

		// according to the apn state
		if autoPlayState == kMPCAutoPlayStateJustFound {
			autoPlayState = kMPCAutoPlayStatePlaying
		} else {
			autoPlayState = kMPCAutoPlayStateInvalid
		}

		// Use the file name to look up whether there is a previous playback record
		let stopTime = lastPlayedPathPre.flatMap { AppController.shared().bookmarks[$0.absoluteString] }
		var dict: [String: Any] = [kMPCPlayOpenedURLKey as String: lastPlayedPathPre as Any]
		if let stopTime = stopTime {
			dict[kMPCPlayLastStoppedTimeKey as String] = stopTime
		}

		// disable the powersave
		// when in auto play next, this function will be called multiple times
		// but it is OK, calling this function multiple times won't lead errors
		enablePowerSave(false)

		notifCenter.post(name: NSNotification.Name.mpcPlayOpened, object: self, userInfo: dict)
	}

	func playbackStarted(_ coreController: Any!) {
		notifCenter.post(name: NSNotification.Name.mpcPlayStarted, object: self,
						  userInfo: [kMPCPlayStartedAudioOnlyKey as String: mplayer.movieInfo.videoInfo.count == 0])

		MPLogString("vc:\(mplayer.movieInfo.videoInfo.count), ac:\(mplayer.movieInfo.audioInfo.count)")
	}

	func playbackWillStop(_ coreController: Any!) {
		notifCenter.post(name: NSNotification.Name.mpcPlayWillStop, object: self, userInfo: nil)
	}

	func playbackStopped(_ coreController: Any!, info dict: [AnyHashable: Any]!) {
		let stoppedByForce = (dict?[kMPCPlayStoppedByForceKey] as? NSNumber)?.boolValue ?? false

		notifCenter.post(name: NSNotification.Name.mpcPlayStopped, object: self, userInfo: nil)

		if !ud.bool(forKey: kUDKeyDisableLastStopBookmark) {
			// if not disable bookmark completely
			if let lastPlayedPath = lastPlayedPath {
				if stoppedByForce {
					// If it was a forced stop
					// Use the file name as the key, and record this file's playback time
					AppController.shared().bookmarks[lastPlayedPath.absoluteString] = dict?[kMPCPlayStoppedTimeKey]
				} else {
					// Stopped naturally
					// Remove the playback time recorded under this file's key
					AppController.shared().bookmarks.removeObject(forKey: lastPlayedPath.absoluteString)
				}
			}
		}

		if ud.bool(forKey: kUDKeyAutoPlayNext), let lastPlayedPath = lastPlayedPath, lastPlayedPath.isFileURL, !stoppedByForce {
			// If it wasn't a forced close
			// If it's not a local file, this is guaranteed to return nil
			let nextPath = PlayListController.searchNextMoviePath(from: lastPlayedPath.path, inFormats: AppController.shared().playableFormats as NSSet)

			if let nextPath = nextPath {
				autoPlayState = kMPCAutoPlayStateJustFound
				loadFiles([nextPath], fromLocal: true)
				return
			}
		}

		if PlayListController.sharedInstance().consumeRequestingNextOrPrev() {
			// If this is a next/prev signal issued by the playlist, then pretend it's AutoPlayNextJustFound
			// This way some necessary parameters can be preserved
			autoPlayState = kMPCAutoPlayStateJustFound
		} else {
			MPLogString("Finalize")

			autoPlayState = kMPCAutoPlayStateInvalid

			enablePowerSave(true)

			notifCenter.post(name: NSNotification.Name.mpcPlayFinalized, object: self, userInfo: nil)

			if ud.bool(forKey: kUDKeyQuitOnClose) && !stoppedByForce && ud.bool(forKey: kUDKeyCloseWindowWhenStopped) {
				NSApp.terminate(nil)
			}
		}
	}

	func playbackError(_ coreController: Any!) {
		autoPlayState = kMPCAutoPlayStateInvalid
	}

	// MARK: SubConverter Delegate methods

	func subConverter(_ subConv: Any!, detectedFile path: String!, ofCharsetName charsetName: String!, confidence: Float) -> String! {
		// When the confidence is above the threshold, directly return the passed-in charsetName
		var ret = charsetName

		if confidence <= ud.float(forKey: kUDKeyTextSubtitleCharsetConfidenceThresh) {
			// When the confidence is below the threshold
			let ce: CFStringEncoding

			if ud.bool(forKey: kUDKeyTextSubtitleCharsetManual) {
				// If it's manually specified
				ce = charsetController?.askForSubEncoding(forFile: path, charsetName: charsetName, confidence: confidence) ?? CFStringEncoding(kCFStringEncodingInvalidId)
			} else {
				// If it's an automatic fallback
				ce = CFStringEncoding(ud.integer(forKey: kUDKeyTextSubtitleCharsetFallback))
			}
			ret = CFStringConvertEncodingToIANACharSetName(ce) as String?
		}
		return ret
	}
}
