/*
 * MPlayerX - MovieInfo.swift
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

// kMovieInfoKVO{SubInfo,AudioInfo,VideoInfo,ChapterInfo} existed only to name
// the properties below for manual will/didChangeValueForKey: notifications;
// since their values were always exactly the property name, external callers
// (CoreController.m) were switched to the literal key-path strings directly
// instead of re-exposing these as Swift constants across the ObjC boundary.

@objc(MovieInfo)
class MovieInfo: NSObject {
	private static let demuxValueDefault = "unknown"

	@objc var demuxer: String = MovieInfo.demuxValueDefault
	@objc var length: NSNumber = 0
	@objc var seekable: NSNumber = 0

	@objc var playingInfo = PlayingInfo()

	@objc var metaData = NSMutableDictionary()

	@objc var chapterInfo = NSMutableArray()

	@objc var videoInfo = NSMutableArray()
	@objc var audioInfo = NSMutableArray()
	@objc var subInfo = NSMutableArray()

	@objc(audioInfoForID:)
	func audioInfo(forID audioID: NSNumber?) -> AudioInfo? {
		guard let audioID = audioID else { return nil }
		let intID = audioID.int32Value
		return audioInfo.first { ($0 as? AudioInfo)?.ID == intID } as? AudioInfo
	}

	@objc(videoInfoForID:)
	func videoInfo(forID videoID: NSNumber?) -> VideoInfo? {
		guard let videoID = videoID else { return nil }
		let intID = videoID.int32Value
		return videoInfo.first { ($0 as? VideoInfo)?.ID == intID } as? VideoInfo
	}

	@objc(resetWithParameterManager:)
	func reset(with pm: ParameterManager?) {
		if let pm = pm {
			playingInfo.reset(with: pm)
		}

		metaData.removeAllObjects()

		// These two don't need KVO for now
		willChangeValue(forKey: "videoInfo")
		videoInfo.removeAllObjects()
		didChangeValue(forKey: "videoInfo")

		willChangeValue(forKey: "audioInfo")
		audioInfo.removeAllObjects()
		didChangeValue(forKey: "audioInfo")

		// A relatively simple way to implement KVO; otherwise removing items one by one would be rather inefficient
		willChangeValue(forKey: "subInfo")
		subInfo.removeAllObjects()
		didChangeValue(forKey: "subInfo")

		willChangeValue(forKey: "chapterInfo")
		chapterInfo.removeAllObjects()
		didChangeValue(forKey: "chapterInfo")

		seekable = 0
		demuxer = MovieInfo.demuxValueDefault
		length = 0
	}
}
