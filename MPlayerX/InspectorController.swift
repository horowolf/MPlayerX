/*
 * MPlayerX - InspectorController.swift
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
// generated MPlayerX-Swift.h).
@objc protocol InspectorPlayerAccess: AnyObject {
	func mediaInfo() -> MovieInfo?
	func playerState() -> Int32
	var lastPlayedPath: URL? { get }
}

private let kMPXStringInfoNoInfo = NSLocalizedString("No Info", comment: "Inspector Info")
private let kMPXStringInfoTrackInfoVideo = NSLocalizedString("Video:%d", comment: "Inspector Info")
private let kMPXStringInfoTrackInfoAudio = NSLocalizedString("Audio:%d", comment: "Inspector Info")
private let kMPXStringInfoTrackInfoSubtitle = NSLocalizedString("Subtitle:%d", comment: "Inspector Info")
private let kMPXStringInfoTrackTrackText = NSLocalizedString(" tracks", comment: "Inspector Info")
private let kMPXStringInfoVideoInfoNoBPS = NSLocalizedString("%@, %d×%d, %.1ffps\n", comment: "OSD hint media info")
private let kMPXStringInfoAudioInfoNoBPS = NSLocalizedString("%@, %.1fkHz %dbit, %d channels", comment: "OSD hint media info")
private let kMPXStringInfoVideoInfo = NSLocalizedString("%@, %.1fkbps, %d×%d, %.1ffps\n", comment: "OSD hint media info")
private let kMPXStringInfoAudioInfo = NSLocalizedString("%@, %.1fkbps, %.1fkHz %dbit, %d channels", comment: "OSD hint media info")

// Mirrors the original's kLoadMIMask* bitmask (0 = "clear").
private struct MediaInfoMask: OptionSet {
	let rawValue: Int
	static let fileName = MediaInfoMask(rawValue: 1 << 0)
	static let source = MediaInfoMask(rawValue: 1 << 1)
	static let demuxer = MediaInfoMask(rawValue: 1 << 2)
	static let trackInfo = MediaInfoMask(rawValue: 1 << 3)
	static let format = MediaInfoMask(rawValue: 1 << 4)
	static let all: MediaInfoMask = [.fileName, .source, .demuxer, .trackInfo, .format]
}

private func hexValue(of string: String?) -> UInt32 {
	guard let string else { return 0 }
	return (string as NSString).hexValue
}

private final class InspectorModel: ObservableObject {
	@Published var filename: String = kMPXStringInfoNoInfo
	@Published var sourceInfo: String = ""
	@Published var demuxerInfo: String = ""
	@Published var trackInfo: String = ""
	@Published var formatInfo: String = ""
	@Published var showInfo: Bool = false
}

private struct InspectorInfoRow: View {
	let label: String
	let value: String

	var body: some View {
		HStack(alignment: .top, spacing: 6) {
			Text(label)
				.font(.system(size: 10))
				.foregroundColor(.white)
				.frame(width: 70, alignment: .trailing)
			Text(value)
				.font(.system(size: 10))
				.foregroundColor(Color(white: 0.75))
			Spacer(minLength: 0)
		}
	}
}

private struct InspectorView: View {
	@ObservedObject var model: InspectorModel

	var body: some View {
		VStack(alignment: .center, spacing: 16) {
			Text(model.filename)
				.font(.system(size: 13))
				.foregroundColor(Color(white: 0.75))
				.multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: false)

			if model.showInfo {
				VStack(alignment: .leading, spacing: 8) {
					InspectorInfoRow(label: NSLocalizedString("Source:", comment: "Inspector Info"), value: model.sourceInfo)
					InspectorInfoRow(label: NSLocalizedString("Demuxer:", comment: "Inspector Info"), value: model.demuxerInfo)
					InspectorInfoRow(label: NSLocalizedString("Track Info:", comment: "Inspector Info"), value: model.trackInfo)
					InspectorInfoRow(label: NSLocalizedString("Format:", comment: "Inspector Info"), value: model.formatInfo)
				}
			}

			Spacer(minLength: 0)
		}
		.padding(20)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
	}
}

@objc(InspectorController)
class InspectorController: NSObject {

	@IBOutlet weak var playerController: InspectorPlayerAccess?

	private let model = InspectorModel()
	private var window: NSPanel?
	private var hasLoadedUI = false

	// Fixed panel width and the height with the info block collapsed; the
	// info block itself (labels + values) adds `infoContainerHeight` more,
	// matching the original Inspector.xib's contentRect (430x220) and its
	// infoContainer subview's height (128) -- 220 - 128 = 92.
	private let contentWidth: CGFloat = 430
	private let compactHeight: CGFloat = 92
	private let infoContainerHeight: CGFloat = 128

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	private func buildWindow() {
		let contentRect = NSRect(x: 0, y: 0, width: contentWidth, height: compactHeight)
		let panel = NSPanel(contentRect: contentRect,
							 styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel, .hudWindow],
							 backing: .buffered,
							 defer: false)
		panel.title = NSLocalizedString("Inspector", comment: "Inspector Info")
		panel.isReleasedWhenClosed = false

		// Deliberately not using setFrameAutosaveName/isRestorable here: this
		// panel isn't user-resizable (no .resizable in styleMask) -- its
		// height is entirely driven by setExpanded(), toggling between
		// compactHeight and compactHeight + infoContainerHeight. AppKit's
		// frame autosave/window-restoration persist and reapply whatever
		// height happened to be in effect at save time, including a
		// mid-animation or otherwise transient one, and reapply it lazily
		// (observably later than window construction, sometimes only once
		// the panel is actually ordered on screen) -- there is no reliable
		// point at which to "fix" a restored frame before it's shown. Since
		// the correct height is always fully determined by
		// setExpanded()/model.showInfo anyway, there's nothing worth
		// persisting: let the panel just use the OS's default placement
		// every time instead of fighting AppKit's restore timing.
		panel.isRestorable = false
		panel.center()

		panel.contentView = NSHostingView(rootView: InspectorView(model: model))

		window = panel
	}

	@IBAction @objc(toggleUI:)
	func toggleUI(_ sender: Any) {
		if !hasLoadedUI {
			hasLoadedUI = true
			buildWindow()

			window?.level = .mainMenu

			loadMediaInfo(mask: .all)

			// from now on, listen to playerController's Notifications
			let center = NotificationCenter.default
			center.addObserver(self, selector: #selector(playInfoUpdated(_:)),
								name: .mpcPlayInfoUpdated, object: playerController)
			center.addObserver(self, selector: #selector(playBackStarted(_:)),
								name: .mpcPlayStarted, object: playerController)
			center.addObserver(self, selector: #selector(playBackStopped(_:)),
								name: .mpcPlayStopped, object: playerController)
		}

		guard let window else { return }

		if window.isVisible {
			window.orderOut(self)
		} else {
			window.orderFront(self)
		}
	}

	@objc private func playInfoUpdated(_ notif: Notification) {
		guard let keyPath = notif.userInfo?[kMPCPlayInfoUpdatedKeyPathKey] as? String else { return }

		if keyPath == kKVOPropertyKeyPathSubInfo || keyPath == kKVOPropertyKeyPathAudioInfo || keyPath == kKVOPropertyKeyPathVideoInfo {
			loadMediaInfo(mask: .trackInfo)
		} else if keyPath == kKVOPropertyKeyPathAudioInfoID || keyPath == kKVOPropertyKeyPathVideoInfoID {
			loadMediaInfo(mask: .format)
		}
	}

	@objc private func playBackStarted(_ notif: Notification) {
		loadMediaInfo(mask: [.fileName, .source, .demuxer])
	}

	@objc private func playBackStopped(_ notif: Notification) {
		loadMediaInfo(mask: [])
	}

	private func loadMediaInfo(mask: MediaInfoMask) {
		guard hasLoadedUI else { return }

		let mi = playerController?.mediaInfo()
		let state = playerController?.playerState() ?? kMPCStoppedState

		if state != kMPCStoppedState, let mi, !mask.isEmpty {
			let path = playerController?.lastPlayedPath

			if mask.contains(.fileName) {
				model.filename = path?.lastPathComponent ?? ""
			}

			if mask.contains(.source) {
				if let path {
					model.sourceInfo = path.isFileURL ? path.path : path.absoluteString
				} else {
					model.sourceInfo = ""
				}
			}

			if mask.contains(.demuxer) {
				model.demuxerInfo = mi.demuxer.uppercased()
			}

			if mask.contains(.trackInfo) {
				var tracks: [String] = []

				let videoCount = mi.videoInfo.count
				if videoCount > 0 { tracks.append(String(format: kMPXStringInfoTrackInfoVideo, Int32(videoCount))) }

				let audioCount = mi.audioInfo.count
				if audioCount > 0 { tracks.append(String(format: kMPXStringInfoTrackInfoAudio, Int32(audioCount))) }

				let subCount = mi.subInfo.count
				if subCount > 0 { tracks.append(String(format: kMPXStringInfoTrackInfoSubtitle, Int32(subCount))) }

				model.trackInfo = tracks.joined(separator: ", ") + kMPXStringInfoTrackTrackText
			}

			if mask.contains(.format) {
				var dispStr = ""

				if let vi = mi.videoInfo(forID: mi.playingInfo.currentVideoID) {
					var format = vi.format ?? ""
					// This is a hack: mplayer will not always output the string
					// form for the video format property, so map the known
					// hex codes we've seen it emit instead.
					switch hexValue(of: format) {
					case 0x10000001: format = "MPEG-1"
					case 0x10000002: format = "MPEG-2"
					case 0x10000005: format = "H264"
					default: break
					}
					format = format.uppercased()

					if vi.bitRate < 1 {
						dispStr += String(format: kMPXStringInfoVideoInfoNoBPS, format, vi.width, vi.height, vi.fps)
					} else {
						dispStr += String(format: kMPXStringInfoVideoInfo, format, Float(vi.bitRate) / 1000.0, vi.width, vi.height, vi.fps)
					}
				}

				if let ai = mi.audioInfo(forID: mi.playingInfo.currentAudioID) {
					var format = ai.format ?? ""
					// Same hack as above, for the audio format property.
					switch hexValue(of: format) {
					case 0x2000: format = "AC-3"
					case 0x2001: format = "DTS"
					case 0x55: format = "MPEG-3"
					case 0x50: format = "MPEG-1/2"
					case 0x1, 0x6, 0x7: format = "PCM"
					case 0x161, 0x162, 0x163: format = "WMA"
					case 0xF1AC: format = "FLAC"
					case 0x566F: format = "VORBIS"
					default: break
					}
					format = format.uppercased()

					if ai.bitRate < 1 {
						dispStr += String(format: kMPXStringInfoAudioInfoNoBPS, format, Float(ai.sampleRate) / 1000.0, ai.sampleSize, ai.channels)
					} else {
						dispStr += String(format: kMPXStringInfoAudioInfo, format, Float(ai.bitRate) / 1000.0, Float(ai.sampleRate) / 1000.0, ai.sampleSize, ai.channels)
					}
				}

				model.formatInfo = dispStr
			}

			model.showInfo = true
			setExpanded(true)
		} else {
			model.filename = kMPXStringInfoNoInfo

			model.showInfo = false
			setExpanded(false)
		}
	}

	// Sets the panel to its absolute target height for the given state,
	// instead of nudging the current frame by +/- infoContainerHeight. The
	// previous relative version (`rc.size.height += infoContainerHeight`)
	// assumed every expand/collapse call was paired with exactly one
	// matching call in the opposite direction; any call that ran while the
	// window was already in the target state (e.g. a duplicate KVO
	// notification re-triggering the `!model.showInfo` branch) would keep
	// adding/subtracting infoContainerHeight and the panel would drift to
	// the wrong size, compounding with every stray call instead of just
	// being a no-op. Computing the height directly from `expanded` makes
	// repeated calls idempotent -- calling this redundantly is harmless,
	// and it self-corrects even if some earlier call left the window at an
	// unexpected height.
	private func setExpanded(_ expanded: Bool) {
		guard let window else { return }

		let targetHeight = expanded ? (compactHeight + infoContainerHeight) : compactHeight
		var rc = window.frame
		guard rc.size.height != targetHeight else { return }

		let top = rc.origin.y + rc.size.height
		rc.size.width = contentWidth
		rc.size.height = targetHeight
		rc.origin.y = top - targetHeight

		window.setFrame(rc, display: true, animate: true)
	}
}
