/*
 * MPlayerX - AODetector.swift
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

// Was AODetector.h/.m. The CoreAudio property plumbing is the same sequence of
// AudioObjectGetPropertyData calls as before, just wrapped in Swift generics
// instead of the four static C helpers.
import Foundation
import CoreAudio

let kMPXDefaultAudioDeviceChanged = "MPXDefaultAudioDeviceChanged"

/// kAudioObjectPropertyElementMaster is deprecated in favour of
/// ...ElementMain, which needs macOS 12; the deployment target is 11.0 and both
/// spellings are 0.
private let kAudioObjectPropertyElementDefault: AudioObjectPropertyElement = 0

private func propertyAddress(_ selector: AudioObjectPropertySelector,
							 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
	AudioObjectPropertyAddress(mSelector: selector,
							   mScope: scope,
							   mElement: kAudioObjectPropertyElementDefault)
}

private func audioProperty<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> OSStatus {
	var address = propertyAddress(selector)
	var size = UInt32(MemoryLayout<T>.size)
	return withUnsafeMutablePointer(to: &value) {
		AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
	}
}

/// The array variants of the property calls: ask for the size, then the data.
private func audioPropertyArray<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
								   scope: AudioObjectPropertyScope, of type: T.Type) -> [T] {
	var address = propertyAddress(selector, scope: scope)
	var size: UInt32 = 0

	guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return [] }

	let count = Int(size) / MemoryLayout<T>.size
	let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
	defer { buffer.deallocate() }

	guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return [] }

	return Array(UnsafeBufferPointer(start: buffer, count: count))
}

private func audioPropertyString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
								 status: UnsafeMutablePointer<OSStatus>? = nil) -> String? {
	var address = propertyAddress(selector)
	var size = UInt32(MemoryLayout<CFString?>.size)
	var string: CFString?

	let err = withUnsafeMutablePointer(to: &string) {
		AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
	}
	status?.pointee = err

	return (err == noErr) ? (string as String?) : nil
}

private func fourCC(_ str: String) -> AudioFormatID {
	str.utf8.reduce(0) { ($0 << 8) | AudioFormatID($1) }
}

private func logFormat(_ label: String, _ f: AudioStreamBasicDescription) {
	let flags = f.mFormatFlags
	let id = f.mFormatID
	let idChars = String(bytes: [UInt8((id >> 24) & 0xff), UInt8((id >> 16) & 0xff),
								 UInt8((id >> 8) & 0xff), UInt8(id & 0xff)], encoding: .ascii) ?? "????"

	MPLogString(String(format: "%@ %7.1fHz %ubit [%@][%u][%u][%u][%u][%u] %@ %@ %@%@%@%@\n",
					   label, f.mSampleRate, f.mBitsPerChannel, idChars,
					   flags, f.mBytesPerPacket, f.mFramesPerPacket, f.mBytesPerFrame, f.mChannelsPerFrame,
					   (flags & kAudioFormatFlagIsFloat) != 0 ? "float" : "int",
					   (flags & kAudioFormatFlagIsBigEndian) != 0 ? "BE" : "LE",
					   (flags & kAudioFormatFlagIsSignedInteger) != 0 ? "S" : "U",
					   (flags & kAudioFormatFlagIsPacked) != 0 ? " packed" : "",
					   (flags & kAudioFormatFlagIsAlignedHigh) != 0 ? " aligned" : "",
					   (flags & kAudioFormatFlagIsNonInterleaved) != 0 ? " ni" : ""))
}

private func streamSupportsDigital(_ streamID: AudioStreamID) -> Bool {
	/* Retrieve all the stream formats supported by each output stream. */
	let formats = audioPropertyArray(streamID, kAudioStreamPropertyAvailablePhysicalFormats,
									 scope: kAudioObjectPropertyScopeGlobal, of: AudioStreamRangedDescription.self)
	if formats.isEmpty {
		MPLogString("Could not get number of stream formats.\n")
		return false
	}

	let digitalFormats: Set<AudioFormatID> = [fourCC("IAC3"), fourCC("iac3"),
											  kAudioFormat60958AC3, kAudioFormatAC3]
	for format in formats {
		logFormat("Supported format:", format.mFormat)

		if digitalFormats.contains(format.mFormat.mFormatID) { return true }
	}
	return false
}

private func deviceSupportsDigital(_ deviceID: AudioDeviceID) -> Bool {
	/* Retrieve all the output streams. */
	let streams = audioPropertyArray(deviceID, kAudioDevicePropertyStreams,
									 scope: kAudioDevicePropertyScopeOutput, of: AudioStreamID.self)
	if streams.isEmpty {
		MPLogString("could not get number of streams.\n")
		return false
	}
	return streams.contains { streamSupportsDigital($0) }
}

@objc(AODetector)
class AODetector: NSObject {

	@objc private(set) var defaultDevID: AudioObjectID = kAudioDeviceUnknown
	@objc var deviceName: String?
	@objc private(set) var isListening = false

	private var digital = false

	private static let sharedInstance = AODetector()

	/// Spelled +defaultDetector in Objective-C; the 2009 singleton also
	/// overrode +allocWithZone:/-retain/-release to funnel every instance back
	/// to this one, which a Swift initializer cannot do -- the initializer is
	/// private instead, so this is the only way to get one.
	@objc(defaultDetector) static func `default`() -> AODetector { sharedInstance }

	private override init() {
		super.init()

		var devID = AudioObjectID(kAudioDeviceUnknown)
		var err = audioProperty(AudioObjectID(kAudioObjectSystemObject),
								kAudioHardwarePropertyDefaultOutputDevice, into: &devID)
		guard err == noErr else {
			MPLogString(String(format: "Default Audio Device Error: [%@]\n", osStatusString(err)))
			return
		}
		defaultDevID = devID

		guard let name = audioPropertyString(defaultDevID, kAudioObjectPropertyName, status: &err) else {
			defaultDevID = kAudioDeviceUnknown
			MPLogString(String(format: "DevName Error: [%@]\n", osStatusString(err)))
			return
		}
		deviceName = name
		digital = deviceSupportsDigital(defaultDevID)
	}

	@objc var isDigital: Bool {
		if !isListening {
			digital = (defaultDevID != kAudioDeviceUnknown) ? deviceSupportsDigital(defaultDevID) : false
		}
		return digital
	}

	@objc func startListening() {
		guard !isListening else { return }

		var address = propertyAddress(kAudioDevicePropertyDeviceHasChanged)
		let err = AudioObjectAddPropertyListener(defaultDevID, &address, deviceListener,
												 Unmanaged.passUnretained(self).toOpaque())
		if err == noErr {
			isListening = true
		} else {
			MPLogString(String(format: "Listen Error: [%@]\n", osStatusString(err)))
		}
		NotificationCenter.default.post(name: .mpxDefaultAudioDeviceChanged, object: self)
	}

	@objc func stopListening() {
		guard isListening else { return }

		isListening = false
		var address = propertyAddress(kAudioDevicePropertyDeviceHasChanged)
		AudioObjectRemovePropertyListener(defaultDevID, &address, deviceListener,
										  Unmanaged.passUnretained(self).toOpaque())
	}

	fileprivate func deviceChanged() {
		digital = deviceSupportsDigital(defaultDevID)
		deviceName = audioPropertyString(defaultDevID, kAudioObjectPropertyName)

		NotificationCenter.default.post(name: .mpxDefaultAudioDeviceChanged, object: self)
	}
}

extension NSNotification.Name {
	static let mpxDefaultAudioDeviceChanged = NSNotification.Name(kMPXDefaultAudioDeviceChanged)
}

/// Renders an OSStatus the way the original's MPLog(@"[%4.4s]") did: as the
/// four characters of the code, which is how CoreAudio errors read.
private func osStatusString(_ err: OSStatus) -> String {
	let code = UInt32(bitPattern: err)
	let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
				 UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
	return String(bytes: bytes, encoding: .ascii) ?? String(err)
}

/// Must stay capture-free: it is passed to CoreAudio as a C function pointer,
/// with the detector handed over as clientData.
private let deviceListener: AudioObjectPropertyListenerProc = { _, count, addresses, clientData in
	guard let clientData = clientData else { return noErr }

	for i in 0..<Int(count) where addresses[i].mSelector == kAudioDevicePropertyDeviceHasChanged {
		MPLogString("Device Changed.\n")
		Unmanaged<AODetector>.fromOpaque(clientData).takeUnretainedValue().deviceChanged()
		break
	}
	return noErr
}
