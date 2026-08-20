/*
 * MPlayerX - CoreController.swift
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

private let kPollingTimeForTimePos: TimeInterval = 1

private let kMITypeNoProc = 0
private let kMITypeFlatValue = 1
private let kMITypeSubArray = 2
private let kMITypeSubAppend = 3
private let kMITypeStateChanged = 4
private let kMITypeVideoGotInfo = 5
private let kMITypeAudioGotInfo = 6
private let kMITypeAudioGotID = 7
private let kMITypeVideoGotID = 8
private let kMITypeChapterInfo = 9

private let kCmdStringFMTFloat = "%@ %@ %f\n"
private let kCmdStringFMTInteger = "%@ %@ %d\n"
private let kCmdStringFMTTimeSeek = "%@ %@ %f %d\n"

// mplayer command/property strings used only from this file (CoreController.m
// was their only user; PlayerController.m never referenced these). Formerly
// coredef_private.h/.m -- moved here now that both former users are Swift,
// following the project's established pattern of not re-exposing symbols
// across the ObjC boundary once nothing ObjC-side needs them any more
// (see PlayerController.swift's own small string constants).
private let kMPCPauseCmd = "pause 1\n"
private let kMPCPlayCmd = "pause -1\n"
private let kMPCFrameStepCmd = "frame_step\n"
private let kMPCSubSelectCmd = "sub_select\n"
private let kMPCSeekCmd = "seek"
private let kMPCAssMargin = "ass_margin"
private let kMPCAfAddCmd = "af_add"
private let kMPCAfDelCmd = "af_del"

private let kMPCGetPropertyPreFix = "get_property"
private let kMPCSetPropertyPreFix = "set_property"
private let kMPCSetPropertyPreFixPauseKeepForce = "pausing_keep_force set_property"
private let kMPCPausingKeepForce = "pausing_keep_force"
private let kMPCPausingKeep = "pausing_keep"
private let kMPCSetPropertyPreFixPauseKeep = "pausing_keep set_property"

private let kMPCTimePos = "time_pos"
private let kMPCOsdLevel = "osdlevel"
private let kMPCSpeed = "speed"
private let kMPCChapter = "chapter"
private let kMPCPercentPos = "percent_pos"
private let kMPCVolume = "volume"
private let kMPCAudioBalance = "balance"
private let kMPCMute = "mute"
private let kMPCAudioDelay = "audio_delay"
private let kMPCSwitchAudio = "switch_audio"
private let kMPCSub = "sub"
private let kMPCSubDelay = "sub_delay"
private let kMPCSubPos = "sub_pos"
private let kMPCSubScale = "sub_scale"
private let kMPCSubLoad = "sub_load"
private let kMPCSwitchVideo = "switch_video"
private let kMPCEqualizer = "equalizer"
private let kMPCPan = "pan"

private let kMPCLengthID = "LENGTH"
private let kMPCSeekableID = "SEEKABLE"
private let kMPCSubInfosID = "MPXSUBNAMES"
private let kMPCSubInfoAppendID = "MPXSUBFILEADD"
private let kMPCCachingPercentID = "CACHING"
private let kMPCPlayBackStartedID = "PBST"
private let kMPCAudioInfoID = "AUDIOINFO"
private let kMPCVideoInfoID = "VIDEOINFO"
private let kMPCAudioIDs = "AUDIO_IDS"
private let kMPCVideoIDs = "VIDEO_IDS"
private let kMPCDemuxerID = "DEMUXER"
private let kMPCChapterInfoID = "CHAPTERSINFO"

private let kKVOPropertyKeyPathStateSwift = "state"

private func realVolume(_ x: Float) -> Float { 0.01 * x * x }

// These two dictionary values were `NSString * const` globals declared (and
// used) only inside CoreController.m/PlayerController.m; both are Swift now,
// so the values just live here as plain internal constants instead of
// crossing the ObjC boundary. See PlayerControllerConstants.h for the
// notification/key constants that DO still need to be ObjC-visible (because
// RootLayerView.m / ControlUIView.m reference them as bare identifiers).
let kMPCPlayStoppedByForceKey = "kMPCPlayStoppedByForceKey"
let kMPCPlayStoppedTimeKey = "kMPCPlayStoppedTimeKey"

// The Distant Object surface that the mplayer child process's vo_corevideo
// drives lives in CoreControllerVOProto.m, not here. It has to: every method
// in mplayer's own copy of @protocol MPlayerOSXVOProto qualifies its scalar
// arguments with `bycopy`, and clang bakes that qualifier into the emitted
// method type encoding ("i32@0:8Oi16Oi20Oi24Oi28", note the `O` prefixes).
// NSConnection compares the incoming invocation's signature against the
// server object's method signature byte for byte, and Swift has no way to
// spell `bycopy`, so a Swift @objc implementation is rejected on arrival with
// "Object does not implement or has different method signature for selector".
// The same file also owns `conformsToProtocol:` and the @protocol declaration
// itself: mplayer's `[proxy conformsToProtocol:@protocol(MPlayerOSXVOProto)]`
// makes DO look the protocol up in this process by name, and a Swift
// `@objc protocol` gets a mangled runtime name
// (_TtP8MPlayerXP33_..17MPlayerOSXVOProto_), so the lookup would find nothing
// and the handshake would fail before any frame was ever sent.
//
// Everything below the ObjC forwarding layer stays here, reached through the
// vo*-prefixed @objc methods further down.

@objc(CoreController)
class CoreController: NSObject, LogAnalyzerDelegate, PlayerCoreDelegate {
	@objc private(set) var state: Int32 = kMPCStoppedState

	private var _mpPathPair: NSDictionary?
	// Custom setter matches the ObjC original's validation: an incoming
	// dictionary only replaces the stored one when it actually has both
	// arch keys; otherwise the assignment is silently dropped (not nil'd).
	@objc var mpPathPair: NSDictionary? {
		get { _mpPathPair }
		set {
			if let dict = newValue {
				if dict[kI386Key] != nil && dict[kX86_64Key] != nil {
					_mpPathPair = dict
				}
			} else {
				_mpPathPair = nil
			}
		}
	}

	@objc let movieInfo = MovieInfo()
	@objc var pm = ParameterManager()
	@objc let la: LogAnalyzer!

	@objc weak var dispDelegate: CoreDisplayDelegate?
	@objc weak var delegate: CoreControllerDelegate?

	private let playerCore = PlayerCore()
	private let subConv = SubConverter()

	// render things
	private var imageData: UnsafeMutableRawPointer?
	private var imageSize = 0
	private var imageBufferCount = 0
	private let sharedBufferName: String
	// Assigned once at the end of init(), after `self` is fully formed and can
	// be passed to Thread(target:selector:object:); never reassigned or nil'd
	// afterwards, so force-unwrapping at every other use site is safe.
	private var renderThread: Thread!
	// The DO service connection created on the render thread. The ObjC original
	// retained it explicitly; keeping it in a property does the same job and
	// makes the lifetime independent of how ARC decides to schedule the release
	// of a local in renderRoutine() (whose run loop never returns).
	private var renderConn: NSObject?

	private var pollingTimer: Timer?

	private let keyPathDict: [String: String]
	private let typeDict: [String: Int]

	override init() {
		keyPathDict = [
			kMPCTimePos: kKVOPropertyKeyPathCurrentTime as String,
			kMPCLengthID: kKVOPropertyKeyPathLength as String,
			kMPCSeekableID: kKVOPropertyKeyPathSeekable as String,
			kMPCSubInfosID: kKVOPropertyKeyPathSubInfo as String,
			kMPCSubInfoAppendID: kKVOPropertyKeyPathSubInfo as String,
			kMPCCachingPercentID: kKVOPropertyKeyPathCachingPercent as String,
			kMPCPlayBackStartedID: kKVOPropertyKeyPathStateSwift,
			kMPCVideoInfoID: kKVOPropertyKeyPathVideoInfo as String,
			kMPCAudioInfoID: kKVOPropertyKeyPathAudioInfo as String,
			kMPCAudioIDs: kKVOPropertyKeyPathAudioInfo as String,
			kMPCVideoIDs: kKVOPropertyKeyPathVideoInfo as String,
			kMPCDemuxerID: kKVOPropertyKeyPathDemuxer as String,
			kMPCChapterInfoID: kKVOPropertyKeyPathChapterInfo as String,
		]
		typeDict = [
			kMPCTimePos: kMITypeFlatValue,
			kMPCLengthID: kMITypeFlatValue,
			kMPCSeekableID: kMITypeFlatValue,
			kMPCSubInfosID: kMITypeSubArray,
			kMPCSubInfoAppendID: kMITypeSubAppend,
			kMPCCachingPercentID: kMITypeFlatValue,
			kMPCPlayBackStartedID: kMITypeStateChanged,
			kMPCVideoInfoID: kMITypeVideoGotInfo,
			kMPCAudioInfoID: kMITypeAudioGotInfo,
			kMPCAudioIDs: kMITypeAudioGotID,
			kMPCVideoIDs: kMITypeVideoGotID,
			kMPCDemuxerID: kMITypeFlatValue,
			kMPCChapterInfoID: kMITypeChapterInfo,
		]

		state = kMPCStoppedState

		let la = LogAnalyzer()
		self.la = la

		// Names the POSIX shared-memory segment (and, with it, the DO service
		// mplayer connects back to). The ObjC original used self's own pointer
		// value, purely to be unique per instance; `self` isn't usable this
		// early in init, so pid + a random word gives the same guarantee.
		//
		// It has to stay SHORT: shm_open() on macOS caps names at PSHMNAMLEN
		// (31 characters) and fails the whole segment with ENAMETOOLONG past
		// that -- which mplayer reports only as "FATAL: Cannot initialize video
		// driver", with no hint about the name. "MPlayerX_" + two hex words is
		// at most 26. (A ProcessInfo.globallyUniqueString here would be 68 and
		// silently break all video output.)
		sharedBufferName = String(format: "MPlayerX_%X_%X", getpid(), UInt32.random(in: 0 ... UInt32.max))

		super.init()

		la.delegate = self
		movieInfo.reset(with: pm)

		playerCore.delegate = self

		// Thread(target:selector:object:) needs `self`, which is only usable
		// after super.init() returns -- hence creating and starting the thread
		// here rather than earlier in init().
		let thread = Thread(target: self, selector: #selector(renderRoutine), object: nil)
		thread.threadPriority = 0.9
		renderThread = thread
		thread.start()
	}

	deinit {
		delegate = nil
		if let pollingTimer = pollingTimer {
			pollingTimer.invalidate()
		}
	}

	@objc private func renderRoutine() {
		autoreleasepool {
			let rl = RunLoop.current
			renderConn = MPXStartServiceConnection(sharedBufferName, self)

			rl.run()
		}
	}

	// MARK: communication with playerCore (PlayerCoreDelegate)

	func playerCore(_ player: Any, hasTerminated byForce: Bool) {
		// if mplayer is crashed, it may not call stop to stop display
		// and stop always happens before mplayer really exit
		// so imageData is there means stop is forgotten
		if imageData != nil {
			perform(#selector(voStop), on: renderThread, with: nil, waitUntilDone: true,
					modes: [RunLoop.Mode.default.rawValue, RunLoop.Mode.modalPanel.rawValue, RunLoop.Mode.eventTracking.rawValue])
		}

		delegate?.playbackWillStop(self)
		state = kMPCStoppedState

		pollingTimer?.invalidate()
		pollingTimer = nil
		la.stop()
		subConv.clearWorkDirectory()

		// Reset textSubs and vobSub here, so that before the next playback the user can set these two elements themselves
		// !!! But note, if playMedia is called directly during playback to start the next playback,
		// !!! since playMedia stops playback first, this would cause sub to be cleared, and in the case of a manually
		// !!! chosen sub, it would then be impossible to load it manually.
		// !!! The fix is to have CoreController correctly call performStop before playMedia.
		// Still shouldn't reset here, since that would reset all the settings made during playback.
		// Should reset right after playback starts instead.
		// pm.reset()

		// only reset things unrelated to playback
		movieInfo.reset(with: nil)

		delegate?.playbackStopped(self, info: [
			kMPCPlayStoppedByForceKey: byForce,
			kMPCPlayStoppedTimeKey: movieInfo.playingInfo.currentTime,
		])
		MPLogString("terminated:\(byForce)")
	}

	func playerCore(_ player: Any, outputAvailable outData: Data) {
		la.analyze(outData)
	}

	func playerCore(_ player: Any, errorHappened errData: Data) {
		let log = String(data: errData, encoding: .utf8) ?? ""
		MPLogString("ERR:\(log)")
	}

	// MARK: protocol for render

	// Called from CoreControllerVOProto.m; see the comment at the top of this
	// file for why the DO-facing selectors themselves have to live in ObjC.
	@objc(voStartWithWidth:height:bytes:aspect:)
	func voStart(withWidth width: Int32, height: Int32, bytes: Int32, aspect: Int32) -> Int32 {
		// Upstream mplayer's entry point. It reports bytes per pixel instead of a
		// pixel format, so the format has to be inferred. The mapping is ambiguous
		// in principle -- vo_corevideo accepts YUY2 and UYVY at two bytes, and ARGB
		// and BGRA at four -- but it advertises them in that order, so the first of
		// each pair is what a decoder actually gets handed.
		let pixelFormat: OSType
		switch bytes {
		case 2:
			pixelFormat = OSType(kYUVSPixelFormat)
		case 3:
			pixelFormat = OSType(k24RGBPixelFormat)
		default:
			pixelFormat = OSType(k32ARGBPixelFormat)
		}

		// The aspect arrives as d_width * 100 / d_height.
		return start(withWidth: UInt(width), withHeight: UInt(height), withPixelFormat: pixelFormat,
					 withAspect: Float(aspect) / 100.0, bufferCount: 1)
	}

	@objc(voStartWithWidth:height:pixelFormat:aspect:)
	func voStart(withWidth width: UInt, height: UInt, pixelFormat: OSType, aspect: Float) -> Int32 {
		// MPlayerX's own mplayer build double-buffers the shared memory.
		return start(withWidth: width, withHeight: height, withPixelFormat: pixelFormat, withAspect: aspect, bufferCount: 2)
	}

	private func start(withWidth width: UInt, withHeight height: UInt, withPixelFormat pixelFormat: OSType, withAspect aspect: Float, bufferCount: UInt) -> Int32 {
		guard let dispDelegate = dispDelegate else { return 1 }

		var fmt = DisplayFormat()
		fmt.width = width
		fmt.height = height
		fmt.pixelFormat = pixelFormat
		fmt.aspect = CGFloat(aspect)

		switch pixelFormat {
		case OSType(kYUVSPixelFormat):
			fmt.bytes = 2
		case OSType(k24RGBPixelFormat):
			fmt.bytes = 3
		default:
			fmt.bytes = 4
		}
		imageSize = Int(fmt.bytes) * Int(width) * Int(height)
		imageBufferCount = Int(bufferCount)

		// Open the shmem
		let shMemID = MPXShmOpenReadOnly(sharedBufferName)
		if shMemID == -1 {
			MPLogString("shm_open Failed!")
			return 1
		}

		// Mapping more than the writer created would fault on access, so the
		// mapping has to match the number of buffers on the other end.
		let mapped = mmap(nil, imageSize * imageBufferCount, PROT_READ, MAP_SHARED, shMemID, 0)
		// whatever succeed or fail, it should be OK of close the shm
		close(shMemID)

		if mapped == MAP_FAILED {
			imageData = nil
			MPLogString("mmap Failed")
			return 1
		}
		imageData = mapped

		var dataBuf: [UnsafeMutablePointer<CChar>?] = [
			mapped?.assumingMemoryBound(to: CChar.self),
			(bufferCount > 1) ? mapped?.advanced(by: imageSize).assumingMemoryBound(to: CChar.self) : mapped?.assumingMemoryBound(to: CChar.self),
		]

		return dataBuf.withUnsafeMutableBufferPointer { buf in
			dispDelegate.coreController(self, startWith: fmt, buffer: buf.baseAddress, total: bufferCount)
		}
	}

	@objc(voStop)
	func voStop() {
		if let dispDelegate = dispDelegate {
			dispDelegate.coreControllerStop(self)
		}
		if let imageData = imageData {
			munmap(imageData, imageSize * max(imageBufferCount, 1))
			self.imageData = nil
			imageSize = 0
			imageBufferCount = 0
		}
	}

	@objc(voRender:)
	func voRender(_ frameNum: UInt) {
		dispDelegate?.coreController(self, draw: frameNum)
	}

	// MARK: playing thing

	@objc(playMedia:)
	func playMedia(_ moviePath: String) {
		// If playback is currently in progress, force it to stop now
		if state != kMPCStoppedState {
			performStop()
		}

		// Clear subConv's work directory before playback starts
		subConv.clearWorkDirectory()

		// Call this function if you want to automatically obtain the codepage of the subtitle file
		if pm.guessSubCP {
			// To support dynamically loading subtitles in the future, the subtitle must first be set to UTF-8, even when there are no subtitles
			pm.subCP = "UTF-8"

			var vobStr: NSString?
			let subEncDict = subConv.getCPFromMoviePath(moviePath, nameRule: pm.subNameRule, alsoFindVobSub: &vobStr)

			if pm.vobSub == nil {
				// If the user hasn't set vobsub themselves, this variable is set to nil after every playback ends
				// If the user has their own vobsub, then don't set it and use the user's vobsub instead
				pm.vobSub = vobStr as String?
			}
			if let subEncDict = subEncDict, subEncDict.count > 0 {
				// If there is a subtitle file
				let subsArray = subConv.convertTextSubsAndEncodings(subEncDict)

				if let subsArray = subsArray, subsArray.count > 0 {
					pm.textSubs = subsArray
				} else if let subStr = subEncDict.values.first as? String, !subStr.isEmpty {
					// If it was successfully guessed
					pm.subCP = subStr
				}
			}
		}

		// Look for an edl file
		let edlUrl = URL(fileURLWithPath: (moviePath as NSString).deletingPathExtension)
			.deletingPathExtension().appendingPathExtension("edl")
		if let res = try? edlUrl.resourceValues(forKeys: [.nameKey]), let name = res.name {
			// if res is OK, but there is no valid NameKey
			// will set edlPath to nil, that is safe
			pm.edlPath = ((moviePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(name)
		}

		// only reset things related to playback
		movieInfo.playingInfo.reset(with: pm)

		let params = pm.arrayOfParameters(withName: (dispDelegate != nil) ? sharedBufferName : nil)
		if playerCore.playMedia(moviePath, withExec: mpPathPair?[pm.mplayerArch] as? String, withParams: params) {
			state = kMPCOpenedState
			delegate?.playbackOpened(self)

			// A Timer needs to be started here to poll the playback time and periodically send the current playback time
			let timer = Timer(timeInterval: kPollingTimeForTimePos, target: self, selector: #selector(getCurrentTime(_:)), userInfo: nil, repeats: true)
			pollingTimer = timer

			let rl = RunLoop.current
			rl.add(timer, forMode: .default)
			rl.add(timer, forMode: .modalPanel)
			rl.add(timer, forMode: .eventTracking)

			pm.reset()
		} else {
			// If opening the media file did not succeed
			pm.reset()
			delegate?.playbackError(self)
		}
	}

	@objc(setWorkDirectory:)
	func setWorkDirectory(_ wd: String?) {
		subConv.setWorkDirectory(wd)
	}

	@objc(setSubConverterDelegate:)
	func setSubConverterDelegate(_ dlgt: SubConverterDelegate?) {
		subConv.delegate = dlgt
	}

	@objc private func getCurrentTime(_ theTimer: Timer) {
		if state == kMPCPlayingState {
			// Sending this command automatically makes mplayer exit the pause state, while using the keep_pause prefix
			// would get no response at all, so the playback time is only polled when not paused
			_ = playerCore.sendStringCommand("\(kMPCGetPropertyPreFix) \(kMPCTimePos)\n")
		} else if state == kMPCPausedState {
			// Even though we're paused, updating the time like this triggers a KVO event, which is done to keep the UI updated
			movieInfo.playingInfo.willChangeValue(forKey: "currentTime")
			movieInfo.playingInfo.didChangeValue(forKey: "currentTime")
		}
	}

	@objc func performStop() {
		// Directly stop the core, because self is the core's delegate;
		// the terminate method will call the delegate, and the relevant cleanup work happens there instead, so it's not done here
		pollingTimer?.invalidate()
		pollingTimer = nil
		playerCore.terminate()
	}

	@objc func togglePause() {
		switch state {
		case kMPCPlayingState:
			_ = playerCore.sendStringCommand(kMPCPauseCmd)
			state = kMPCPausedState
		case kMPCPausedState:
			_ = playerCore.sendStringCommand(kMPCPlayCmd)
			state = kMPCPlayingState
		default:
			break
		}
	}

	@objc(frameStep:)
	func frameStep(_ frameNum: Int) {
		if state == kMPCPlayingState {
			togglePause()
		}

		if state == kMPCPausedState {
			_ = playerCore.sendStringCommand(kMPCFrameStepCmd)
		}
	}

	@objc(setSpeed:)
	func setSpeed(_ speed: Float) {
		let speed = max(speed, 0.1)
		if playerCore.sendStringCommand(String(format: kCmdStringFMTFloat, kMPCSetPropertyPreFixPauseKeepForce, kMPCSpeed, speed)) {
			movieInfo.playingInfo.speed = NSNumber(value: speed)
		}
	}

	@objc(setChapter:)
	func setChapter(_ chapter: Int32) {
		if playerCore.sendStringCommand(String(format: kCmdStringFMTInteger, kMPCSetPropertyPreFix, kMPCChapter, chapter)) {
			movieInfo.playingInfo.currentChapter = UInt8(truncatingIfNeeded: chapter)
		}
	}

	@objc(setTimePos:mode:)
	func setTimePos(_ time: Float, mode seekMode: SEEK_MODE) -> Float {
		var time = time
		var cmdStr: String

		if seekMode == kMPCSeekModeAbsolute {
			// kMPCSeekModeAbsolute : the abs time to jump
			time = max(time, 0)
			cmdStr = String(format: kCmdStringFMTFloat, kMPCSetPropertyPreFixPauseKeep, kMPCTimePos, time)
		} else {
			// kMPCSeekModeRelative : the delta time to jump
			let base = movieInfo.playingInfo.currentTime.floatValue
			let len = movieInfo.length.floatValue

			// get the absollute time
			time += base
			// avoid minus time
			time = max(time, 0)

			if len > 0 {
				// the length is valid
				time = min(time, len)
			}

			cmdStr = String(format: kCmdStringFMTTimeSeek, kMPCPausingKeep, kMPCSeekCmd, time - base, seekMode.rawValue)
		}

		if playerCore.sendStringCommand(cmdStr) {
			movieInfo.playingInfo.currentTime = NSNumber(value: time)
			return time
		}
		return -1
	}

	@objc(setVolume:)
	func setVolume(_ vol: Float) -> Float {
		let vol = min(100, max(vol, 0))
		if playerCore.sendStringCommand(String(format: kCmdStringFMTFloat, kMPCSetPropertyPreFixPauseKeepForce, kMPCVolume, realVolume(vol))) {
			movieInfo.playingInfo.volume = vol
		}
		return vol
	}

	@objc(setBalance:)
	func setBalance(_ bal: Float) {
		let bal = min(1, max(bal, -1))
		if playerCore.sendStringCommand(String(format: kCmdStringFMTFloat, kMPCSetPropertyPreFixPauseKeepForce, kMPCAudioBalance, bal)) {
			movieInfo.playingInfo.audioBalance = bal
		}
	}

	@objc(setMute:)
	func setMute(_ mute: Bool) -> Bool {
		var mute = mute
		if playerCore.sendStringCommand(String(format: kCmdStringFMTInteger, kMPCSetPropertyPreFixPauseKeepForce, kMPCMute, mute ? 1 : 0)) {
			movieInfo.playingInfo.mute = mute
		} else {
			movieInfo.playingInfo.mute = false
			mute = false
		}
		return mute
	}

	@objc(setAudioDelay:)
	func setAudioDelay(_ delay: Float) {
		var delay = delay
		if abs(delay) < 0.00001 { delay = 0.0 }

		if playerCore.sendStringCommand(String(format: kCmdStringFMTFloat, kMPCSetPropertyPreFixPauseKeepForce, kMPCAudioDelay, -1 * delay)) {
			movieInfo.playingInfo.audioDelay = NSNumber(value: delay)
		}
	}

	@objc(setAudio:)
	func setAudio(_ audioID: Int32) {
		_ = playerCore.sendStringCommand(String(format: kCmdStringFMTInteger, kMPCSetPropertyPreFixPauseKeepForce, kMPCSwitchAudio, audioID))
	}

	@objc(setVideo:)
	func setVideo(_ videoID: Int32) {
		_ = playerCore.sendStringCommand(String(format: kCmdStringFMTInteger, kMPCSetPropertyPreFixPauseKeepForce, kMPCSwitchVideo, videoID))
	}

	@objc(setSub:)
	func setSub(_ subID: Int32) {
		_ = playerCore.sendStringCommand(String(format: kCmdStringFMTInteger, kMPCSetPropertyPreFixPauseKeepForce, kMPCSub, subID))
		movieInfo.playingInfo.currentSubID = NSNumber(value: subID)
	}

	@objc(setSubDelay:)
	func setSubDelay(_ delay: Float) {
		var delay = delay
		if abs(delay) < 0.00001 { delay = 0.0 }

		if playerCore.sendStringCommand(String(format: kCmdStringFMTFloat, kMPCSetPropertyPreFixPauseKeepForce, kMPCSubDelay, -1 * delay)) {
			movieInfo.playingInfo.subDelay = NSNumber(value: delay)
		}
	}

	@objc(setSubPos:)
	func setSubPos(_ pos: Float) {
		let pos = min(100, max(pos, 0))
		if playerCore.sendStringCommand(String(format: kCmdStringFMTInteger, kMPCSetPropertyPreFixPauseKeepForce, kMPCSubPos, UInt32(pos))) {
			movieInfo.playingInfo.subPos = pos
		}
	}

	@objc(setSubScale:)
	func setSubScale(_ scale: Float) {
		let scale = max(0.1, min(scale, 100))

		if playerCore.sendStringCommand(String(format: kCmdStringFMTFloat, kMPCSetPropertyPreFixPauseKeepForce, kMPCSubScale, scale)) {
			movieInfo.playingInfo.subScale = NSNumber(value: scale)
		}
	}

	@objc(loadSubFile:)
	func loadSubFile(_ path: String) {
		if let cpStr = subConv.getCPOfTextSubtitle(path) {
			// Found the encoding
			let newPaths = subConv.convertTextSubsAndEncodings([path: cpStr])
			if let firstPath = newPaths?.first as? String {
				_ = playerCore.sendStringCommand("\(kMPCSubLoad) \"\(firstPath)\"\n")
			}
		}
	}

	@objc(setLetterBox:top:bottom:)
	func setLetterBox(_ renderSubInLB: Bool, top topRatio: Float, bottom bottomRatio: Float) {
		_ = playerCore.sendStringCommand(String(format: "%@ %@ %f %f %d\n",
												 kMPCPausingKeepForce, kMPCAssMargin, bottomRatio, topRatio, renderSubInLB ? 1 : 0))
	}

	@objc(setEqualizer:)
	func setEqualizer(_ amps: [Any]?) {
		// delete the previous filter
		_ = playerCore.sendStringCommand("\(kMPCPausingKeepForce) \(kMPCAfDelCmd) \(kMPCEqualizer)\n")

		if let amps = amps, !amps.isEmpty {
			var str = ""
			for amp in amps {
				let floatValue = (amp as? NSNumber)?.floatValue ?? Float(String(describing: amp)) ?? 0
				str += String(format: ":%.2f", floatValue)
			}
			_ = playerCore.sendStringCommand("\(kMPCPausingKeepForce) \(kMPCAfAddCmd) \(kMPCEqualizer)=\(str.dropFirst())\n")
		}
	}

	@objc(mapAudioChannelsTo:)
	func mapAudioChannelsTo(_ mode: Int) {
		if pm.dtsPass || pm.ac3Pass {
			return
		}

		// get the current audio info
		guard let ai = movieInfo.audioInfo(forID: movieInfo.playingInfo.currentAudioID) else { return }

		// must have current audio stream
		var panString: String?

		// delete the current PAN filter
		_ = playerCore.sendStringCommand("\(kMPCPausingKeepForce) \(kMPCAfDelCmd) \(kMPCPan)\n")

		switch mode {
		case Int(kMPCMonoAudioLeftOnly):
			panString = "2:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0"
		case Int(kMPCMonoAudioRightOnly):
			panString = "2:0:0:0:1:0:0:0:0:0:0:0:0:0:0:0:0"
		case Int(kMPCMonoAudioLeftExpand):
			panString = "2:1:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0"
		case Int(kMPCMonoAudioRightExpand):
			panString = "2:0:0:1:1:0:0:0:0:0:0:0:0:0:0:0:0"
		default: // kMPCMonoAudioStereo, kMPCMonoAudioNone
			let chSrc = Int(ai.channels)

			if chSrc > 2 && (pm.mixToStereo != 0 || mode == Int(kMPCMonoAudioStereo)) {
				// Only when not passing through, and forcing channels==2 or stereo, does the original filter need to be restored
				switch chSrc {
				case 3:
					panString = "2:0.6:0:0:0.6:0.4:0.4"
				case 4:
					panString = "2:0.6:0:0:0.6:0.4:0:0:0.4"
				case 5:
					panString = "2:0.5:0:0:0.5:0.2:0:0:0.2:0.3:0.3"
				case 6:
					panString = "2:0.4:0:0:0.4:0.2:0:0:0.2:0.3:0.3:0.1:0.1"
				case 7:
					panString = "2:0.4:0:0:0.4:0.2:0:0:0.2:0.3:0.3:0.1:0:0:0.1"
				case 8:
					panString = "2:0.4:0:0:0.4:0.15:0:0:0.15:0.25:0.25:0.1:0.1:0.1:0:0:0.1"
				default:
					break
				}
			}
		}
		// set the pan filter
		if let panString = panString {
			_ = playerCore.sendStringCommand("\(kMPCPausingKeepForce) \(kMPCAfAddCmd) \(kMPCPan)=\(panString)\n")
		}
	}

	// This is the LogAnalyzer's delegate method,
	// so it runs on the worker thread, since KVC and KVO are used here.
	// Is there a need to run it on the main thread?
	func logAnalyzeFinished(_ dict: [AnyHashable: Any]!) {
		guard let dict = dict else { return }

		for case let key as String in dict.keys {
			guard let keyPath = keyPathDict[key] else { continue }
			let type = typeDict[key] ?? kMITypeNoProc
			let value = dict[key]

			switch type {
			case kMITypeFlatValue:
				setValue(value, forKeyPath: keyPath)

			case kMITypeSubArray:
				// If KVO were used directly here, it would generate an Insert change, which is too inefficient
				// so KVO is fired manually instead
				if let str = value as? String {
					let res = str.components(separatedBy: ";;")
					movieInfo.playingInfo.currentSubID = NSNumber(value: Int32(res.last ?? "") ?? 0)

					movieInfo.willChangeValue(forKey: "subInfo")
					movieInfo.subInfo.setArray(res.first?.components(separatedBy: "^^") ?? [])
					movieInfo.didChangeValue(forKey: "subInfo")
				}

			case kMITypeSubAppend:
				// This will fire an insert KVO change
				if let str = value as? String {
					movieInfo.playingInfo.currentSubID = NSNumber(value: movieInfo.subInfo.count)
					movieInfo.mutableArrayValue(forKey: "subInfo").add((str as NSString).lastPathComponent)
				}

			case kMITypeStateChanged:
				// Currently this event is only triggered when playback starts, so a notification can be posted here
				// but if it becomes a general-purpose event, posting a notification will need care!!!
				let stateOld = state
				// LogAnalyzeOperation always hands back NSString values (it slices
				// them straight out of mplayer's stdout), so this has to go
				// through -intValue like the ObjC original did. Bridging it as
				// NSNumber silently fails and leaves `state` stuck at
				// kMPCOpenedState, which strands the whole UI: the play/pause
				// button never flips, and getCurrentTime: stops polling
				// get_time_pos, so the time slider never moves.
				state = (value as? NSString)?.intValue ?? state
				if ((stateOld & kMPCStateMask) == 0) && ((state & kMPCStateMask) != 0) {
					delegate?.playbackStarted(self)
				}

			case kMITypeAudioGotID:
				if let str = value as? String {
					let IDs = str.components(separatedBy: ";;")

					movieInfo.willChangeValue(forKey: "audioInfo")
					for entry in IDs {
						let idLang = entry.components(separatedBy: "^^")
						guard idLang.count >= 3 else { continue }

						let info = AudioInfo()
						info.ID = Int32(idLang[0]) ?? -2
						info.name = idLang[1]
						info.language = idLang[2]

						movieInfo.audioInfo.add(info)
					}
					movieInfo.didChangeValue(forKey: "audioInfo")
				}

			case kMITypeVideoGotID:
				if let str = value as? String {
					let IDs = str.components(separatedBy: ";;")

					movieInfo.willChangeValue(forKey: "videoInfo")
					for entry in IDs {
						let idLang = entry.components(separatedBy: "^^")
						guard idLang.count >= 3 else { continue }

						let info = VideoInfo()
						info.ID = Int32(idLang[0]) ?? -2
						info.name = idLang[1]
						info.language = idLang[2]

						movieInfo.videoInfo.add(info)
					}
					movieInfo.didChangeValue(forKey: "videoInfo")
				}

			case kMITypeVideoGotInfo, kMITypeAudioGotInfo:
				// This KVO will be called
				// 1. when playback is opened but not started, core just got the infos
				// 2. in multi-track media, this will be called when track was changed
				if let str = value as? String {
					let strArr = str.components(separatedBy: ":")
					let ID = Int32(strArr.first ?? "") ?? -2
					let obj = self.value(forKeyPath: keyPath) as? NSMutableArray
					var infoToSet: AnyObject?

					for case let info as NSObject in obj ?? [] {
						let infoID = (type == kMITypeAudioGotInfo) ? (info as? AudioInfo)?.ID : (info as? VideoInfo)?.ID
						if infoID == ID {
							infoToSet = info
							break
						}
					}

					var currentID: NSNumber?
					if let infoToSet = infoToSet {
						if type == kMITypeAudioGotInfo {
							(infoToSet as? AudioInfo)?.setInfoData(with: strArr)
						} else {
							(infoToSet as? VideoInfo)?.setInfoData(with: strArr)
						}
						currentID = NSNumber(value: ID)
					}
					let idKeyPath = (type == kMITypeAudioGotInfo) ? (kKVOPropertyKeyPathAudioInfoID as String) : (kKVOPropertyKeyPathVideoInfoID as String)
					setValue(currentID, forKeyPath: idKeyPath)
				}

			case kMITypeChapterInfo:
				if let str = value as? String {
					let chapters = str.components(separatedBy: ";;")

					movieInfo.willChangeValue(forKey: "chapterInfo")
					for entry in chapters {
						let nameTime = entry.components(separatedBy: "^^")
						guard nameTime.count >= 3 else { continue }

						let item = ChapterItem()
						item.name = nameTime[0]
						item.start = Int(nameTime[1]) ?? 0
						item.end = Int(nameTime[2]) ?? 0
						movieInfo.chapterInfo.add(item)
					}
					movieInfo.didChangeValue(forKey: "chapterInfo")
				}

			default:
				break
			}
		}
	}
}
