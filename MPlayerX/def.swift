/*
 * MPlayerX - def.swift
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

// Was def.h/.m. kMPCChapterTimeBase, which used to be a C macro duplicated in
// ChapterItem.swift, now has a single Swift definition here.

import Cocoa

let kMPCChapterTimeBase = 1000

let kMPCDefaultSubFontPath = "wqy-microhei.ttc"

// These were `extern NSString * const kMPXMediaKey*Notification`, which the
// Objective-C importer surfaced to Swift as NSNotification.Name members. They
// are declared that way directly now, so the call sites keep their spelling
// and the posted names keep their string values.
extension NSNotification.Name {
	static let mpxMediaKeyPlayPause = NSNotification.Name("MPXMediaKeyPlayPause")
	static let mpxMediaKeyForward = NSNotification.Name("MPXMediaKeyForward")
	static let mpxMediaKeyBackward = NSNotification.Name("MPXMediaKeyBackward")
}
