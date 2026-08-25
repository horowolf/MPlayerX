/*
 * MPlayerX - AppController.swift
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

private let kSnapshotSaveDefaultPath = "~/Pictures"

private let kMPCFMTBookmarkPath = "bookmarks.plist"
// mplayerx.org belongs to the original project, not to this fork, so the
// feedback link goes to this repository's issue tracker instead. The wiki is
// still the upstream one on purpose: it holds the original usage documentation
// and this fork has none of its own yet.
private let kMPXFeedbackURL = "https://github.com/horowolf/MPlayerX/issues"
private let kMPXWikiURL = "https://github.com/niltsh/MPlayerX/wiki"
private let kMPXSponsorURL = "https://github.com/sponsors/horowolf"
private let kMPXEAFPlaceHolder = ""

/// The ObjC original was a singleton built the 2009 way: it overrode
/// +allocWithZone:/-retain/-release so that the instance MainMenu.xib creates
/// and the one +sharedAppController hands out are literally the same object.
/// Swift cannot express that (an initializer cannot return some other
/// instance), so the rule here is "the first instance created wins": the
/// MainMenu.xib object registers itself in init(), long before anything asks
/// for sharedAppController, and the lazy branch below only exists as a
/// fallback so the getter never returns nil.
@objc(AppController)
class AppController: NSObject, NSApplicationDelegate, NSMenuItemValidation, SPMediaKeyTapDelegate {

	private static var sharedInstance: AppController?

	@objc(sharedAppController)
	static func shared() -> AppController! {
		if sharedInstance == nil {
			sharedInstance = AppController()
		}
		return sharedInstance
	}

	private let ud = UserDefaults.standard

	@objc private(set) var bookmarks: NSMutableDictionary = [:]
	@objc private(set) var supportVideoFormats: NSSet = []
	@objc private(set) var supportAudioFormats: NSSet = []
	@objc private(set) var supportSubFormats: NSSet = []
	@objc private(set) var playableFormats: NSSet = []

	private var keyTap: SPMediaKeyTap?

	@IBOutlet weak var playerController: PlayerController!
	@IBOutlet weak var openUrlController: OpenURLController!
	@IBOutlet weak var dispView: RootLayerView!
	@IBOutlet weak var openPanelAccView: NSView!
	@IBOutlet weak var externalAudioFilePath: NSTextField!

	/// Replaces the ObjC +initialize; same "runs once, before anything else
	/// touches these defaults" guarantee, using the pattern the rest of this
	/// project's Swift ports use.
	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [
			kUDKeyLogMode: false,
			kUDKeySnapshotSavePath: kSnapshotSaveDefaultPath,
			"AppleMomentumScrollSupported": "NO",
			kMediaKeyUsingBundleIdentifiersDefaultsKey: SPMediaKeyTap.defaultMediaKeyUserBundleIdentifiers() ?? [],
			kUDKeyEnableMediaKeyTap: true,
			kUDKeyDisableLastStopBookmark: false,
		])

		MPSetLogEnable(UserDefaults.standard.bool(forKey: kUDKeyLogMode))
	}()

	override init() {
		super.init()

		_ = AppController.registerDefaultsOnce

		if AppController.sharedInstance == nil {
			AppController.sharedInstance = self
		}

		let mainBundle = Bundle.main
		// build the Set of supported formats
		let docTypes = mainBundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []

		for dict in docTypes {
			let exts = (dict["CFBundleTypeExtensions"] as? [Any]) ?? []

			// for the different kinds of formats
			switch dict["CFBundleTypeName"] as? String {
			case "Audio Media":
				// if it's an audio file
				supportAudioFormats = NSSet(array: exts)
			case "Video Media":
				// if it's a video file
				supportVideoFormats = NSSet(array: exts)
			case "Subtitle":
				// if it's a subtitle file
				supportSubFormats = NSSet(array: exts)
			default:
				break
			}
		}

		playableFormats = supportVideoFormats.addingObjects(from: supportAudioFormats as! Set<AnyHashable>) as NSSet

		/////////////////////////setup bookmarks////////////////////
		// get the bookmark file name
		let lastStoppedTimePath = ((FileManager.userPath(.applicationSupportDirectory, withSuffix: kMPCStringMPlayerX) ?? "") as NSString)
			.appendingPathComponent(kMPCFMTBookmarkPath)

		// get the dict that records playback time
		bookmarks = NSMutableDictionary(contentsOfFile: lastStoppedTimePath) ?? NSMutableDictionary(capacity: 10)
	}

	override func awakeFromNib() {
		super.awakeFromNib()

		// setup url list for OpenURL Panel
		openUrlController.initURLList(bookmarks as? [String: Any])

		if ud.bool(forKey: kUDKeyDisableLastStopBookmark) {
			// disable bookmark completely
			bookmarks.removeAllObjects()
		}

		externalAudioFilePath.stringValue = kMPXEAFPlaceHolder
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(moveToTrash(_:)) {
			return playerController.lastPlayedPath != nil
		}
		return true
	}

	/////////////////////////////////////Actions//////////////////////////////////////
	@IBAction func openFile(_ sender: Any?) {
		let openPanel = NSOpenPanel()
		openPanel.canChooseFiles = true
		openPanel.canChooseDirectories = false
		openPanel.resolvesAliases = false
		// playlists aren't supported yet, so disable multiple selection
		openPanel.allowsMultipleSelection = false
		openPanel.canCreateDirectories = false
		openPanel.title = NSLocalizedString("Open Media Files", comment: "")
		openPanel.accessoryView = openPanelAccView

		guard openPanel.runModal() == .OK else { return }

		var isDir: ObjCBool = true
		if FileManager.default.fileExists(atPath: externalAudioFilePath.stringValue, isDirectory: &isDir),
		   !isDir.boolValue {
			playerController.setExternalAudioFilePath(externalAudioFilePath.stringValue)
		}
		// this could also be opening a folder like dvdmedia, so the actual file-opening action is done in the application delegate method
		let fileUrl = openPanel.urls[0].path

		if (fileUrl as NSString).pathExtension.lowercased() == "dvdmedia" {
			playerController.setPlayDisk(Int(kPMPlayDiskDVD))
			playerController.loadFiles(openPanel.urls, fromLocal: true)
			playerController.setPlayDisk(Int(kPMPlayDiskNone))
		} else {
			playerController.loadFiles(openPanel.urls, fromLocal: true)
		}
		// if an audiofile was selected, clear it
		externalAudioFilePath.stringValue = kMPXEAFPlaceHolder
	}

	@IBAction func openExternalAudioFile(_ sender: Any?) {
		let openEAF = NSOpenPanel()
		openEAF.canChooseFiles = true
		openEAF.canChooseDirectories = false
		openEAF.resolvesAliases = false
		openEAF.allowsMultipleSelection = false
		openEAF.canCreateDirectories = false
		openEAF.title = NSLocalizedString("Open Media Files", comment: "")

		// The sender is the button sitting in openPanelAccView, so its window
		// is the Open panel that the sheet has to hang off.
		guard let window = (sender as? NSView)?.window else { return }

		openEAF.beginSheetModal(for: window) { [weak self] result in
			if result == .OK {
				self?.externalAudioFilePath.stringValue = openEAF.urls[0].path
			}
		}
	}

	@IBAction func openVIDEOTS(_ sender: Any?) {
		let openPanel = NSOpenPanel()
		openPanel.canChooseFiles = false
		openPanel.canChooseDirectories = true
		openPanel.resolvesAliases = false
		// playlists aren't supported yet, so disable multiple selection
		openPanel.allowsMultipleSelection = false
		openPanel.canCreateDirectories = false
		openPanel.title = NSLocalizedString("Open VIDEO_TS", comment: "")

		if openPanel.runModal() == .OK {
			playerController.setPlayDisk(Int(kPMPlayDiskDVD))
			playerController.loadFiles(openPanel.urls, fromLocal: true)
			playerController.setPlayDisk(Int(kPMPlayDiskNone))
		}
	}

	@IBAction func gotoWikiPage(_ sender: Any?) {
		if let url = URL(string: kMPXWikiURL) {
			NSWorkspace.shared.open(url)
		}
	}

	@IBAction func writeSnapshotToFile(_ sender: Any?) {
		// get the image data
		guard let snapshot = dispView.snapshot() else { return }

		autoreleasepool {
			// get the save folder
			var savePath: String? = ud.string(forKey: kUDKeySnapshotSavePath)

			// if it's the default path, replace it with the absolute path
			if savePath == kSnapshotSaveDefaultPath {
				savePath = FileManager.userPath(.picturesDirectory, withSuffix: kMPCStringMPlayerX)
			}

			let fm = FileManager.default
			var isDir: ObjCBool = false
			if let path = savePath, fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
				// if it exists but isn't a folder
				try? fm.removeItem(atPath: path)
			}
			if !isDir.boolValue {
				// if the folder doesn't exist, or what exists there is a file, need to recreate the folder either way
				do {
					try fm.createDirectory(atPath: savePath ?? "", withIntermediateDirectories: true)
				} catch {
					savePath = nil
				}
			}

			guard var savePath else { return }

			let lastPlayed = playerController.lastPlayedPath
			let mediaPath = (lastPlayed?.isFileURL ?? false) ? (lastPlayed?.path ?? "") : (lastPlayed?.absoluteString ?? "")
			var dateTime = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
			dateTime = dateTime.replacingOccurrences(of: ":", with: ".")
			dateTime = dateTime.replacingOccurrences(of: "/", with: ".")

			// create the file name
			// replace the ":" in the file name, since ":" can't be stored as part of a file name
			let stem = ((mediaPath as NSString).lastPathComponent as NSString).deletingPathExtension
			savePath = "\(savePath)/\(stem)_\(dateTime).png"

			// get the image's Rep
			let imRep = NSBitmapImageRep(ciImage: snapshot)
			// set this Rep's storage format
			let imData = NSBitmapImageRep.representationOfImageReps(in: [imRep], using: .png, properties: [:])
			// write the file
			try? imData?.write(to: URL(fileURLWithPath: savePath), options: .atomic)
		}
	}

	@IBAction func moveToTrash(_ sender: Any?) {
		guard let path = playerController.lastPlayedPath, path.isFileURL else { return }

		playerController.stop()
		NSWorkspace.shared.recycle([path], completionHandler: nil)
	}

	/// Was a legacy PayPal "non-hosted" donation URL carrying the original
	/// author's mail address in a `business=` query parameter -- both the wrong
	/// recipient for this fork and a form that publishes someone's mail address
	/// in a link. GitHub Sponsors takes neither an address nor a currency guess.
	@IBAction func donate(_ sender: Any?) {
		if let url = URL(string: kMPXSponsorURL) {
			NSWorkspace.shared.open(url)
		}
	}

	@IBAction func gotoFeedbackPage(_ sender: Any?) {
		if let url = URL(string: kMPXFeedbackURL) {
			NSWorkspace.shared.open(url)
		}
	}

	//////////////////////////////////////Media Key Delegate//////////////////////////////////////
	func mediaKeyTap(_ keyTap: SPMediaKeyTap?, receivedMediaKeyEvent event: NSEvent) {
		assert(event.type == .systemDefined && event.subtype.rawValue == Int16(SPSystemDefinedEventMediaKeys),
			   "Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:")
		// here be dragons...
		let keyCode = Int32((event.data1 & 0xFFFF_0000) >> 16)
		let keyFlags = event.data1 & 0x0000_FFFF
		let keyIsPressed = ((keyFlags & 0xFF00) >> 8) == 0xA
		let keyRepeat = keyFlags & 0x1

		guard keyRepeat == 0 else { return }

		switch keyCode {
		case Int32(NX_KEYTYPE_PLAY):
			if !keyIsPressed {
				MPLogString("Media Key: play/pause")
				NotificationCenter.default.post(name: NSNotification.Name.mpxMediaKeyPlayPause, object: NSApp)
			}
		case Int32(NX_KEYTYPE_FAST):
			if keyIsPressed {
				MPLogString("Media Key: forward")
				NotificationCenter.default.post(name: NSNotification.Name.mpxMediaKeyForward, object: NSApp)
			}
		case Int32(NX_KEYTYPE_REWIND):
			if keyIsPressed {
				MPLogString("Media Key: backward")
				NotificationCenter.default.post(name: NSNotification.Name.mpxMediaKeyBackward, object: NSApp)
			}
		default:
			MPLogString("Media Key \(keyCode) pressed")
		}
	}

	/////////////////////////////////////Application Delegate//////////////////////////////////////
	func application(_ sender: NSApplication, openFile filename: String) -> Bool {
		var isDir: ObjCBool = false

		// check whether the file exists here, in preparation for command line arguments
		guard FileManager.default.fileExists(atPath: filename, isDirectory: &isDir) else { return false }

		if isDir.boolValue {
			playerController.setPlayDisk(Int(kPMPlayDiskDVD))
			playerController.loadFiles([filename], fromLocal: true)
			playerController.setPlayDisk(Int(kPMPlayDiskNone))
		} else {
			playerController.loadFiles([filename], fromLocal: true)
		}
		return true
	}

	func application(_ sender: NSApplication, openFiles filenames: [String]) {
		var isDir: ObjCBool = false
		var reply = NSApplication.DelegateReply.failure

		// check whether the file exists here, in preparation for command line arguments
		if let first = filenames.first,
		   FileManager.default.fileExists(atPath: first, isDirectory: &isDir) {
			if isDir.boolValue {
				playerController.setPlayDisk(Int(kPMPlayDiskDVD))
				playerController.loadFiles(filenames, fromLocal: true)
				playerController.setPlayDisk(Int(kPMPlayDiskNone))
			} else {
				playerController.loadFiles(filenames, fromLocal: true)
			}
			reply = .success
		}
		sender.reply(toOpenOrPrint: reply)
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		keyTap?.stopWatchingMediaKeys()

		playerController.stop()

		ud.synchronize()

		openUrlController.syncToBookmark(bookmarks)

		let path = ((FileManager.userPath(.applicationSupportDirectory, withSuffix: kMPCStringMPlayerX) ?? "") as NSString)
			.appendingPathComponent(kMPCFMTBookmarkPath)
		bookmarks.write(toFile: path, atomically: true)

		// don't enable listening for now
		// AODetector.default().stopListening()

		return .terminateNow
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		if ud.bool(forKey: kUDKeyEnableMediaKeyTap) {
			keyTap = SPMediaKeyTap(delegate: self)
			if SPMediaKeyTap.usesGlobalMediaKeyTap() {
				keyTap?.startWatchingMediaKeys()
			} else {
				MPLogString("MediaKey monitoring Disabled.")
			}
		}

		// start listening to the AudioDevice
		// if the app was opened by double-clicking a file, application:openFile: will be called before this method
		// which means play would need to start before startListening
		// but that's fine - even without listening, playerController calls [AODetector defaultDetector] when playing, which forces a check of whether it's digital, so there's no problem
		// this method is placed here because we don't want to delay startup time
		// don't enable listening for now
		// AODetector.default().startListening()

		if let cmdStr = ud.string(forKey: "url") {
			MPLogString("url:\(cmdStr)")

			playerController.loadFiles([cmdStr], fromLocal: false)

		} else if let cmdStr = ud.string(forKey: "file") {
			MPLogString("file:\(cmdStr)")
			_ = application(NSApp, openFile: cmdStr)
		}
	}
}
