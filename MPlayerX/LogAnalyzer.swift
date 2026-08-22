/*
 * MPlayerX - LogAnalyzer.swift
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

// Was LogAnalyzer.h/.m plus LogAnalyzeOperation.h/.m; the operation was never
// used anywhere else, so it lives here as a private class.
import Foundation

/// Parses mplayer's stdout off the main thread. Each "ANS_key=value" or
/// "MPX_key=value" line becomes a one-entry dictionary handed to the delegate
/// on the main thread.
@objc(LogAnalyzer)
class LogAnalyzer: NSObject {

	// Queue for parsing the log. This has to exist from -init on, or a plain
	// LogAnalyzer() silently leaves it nil -- and since adding an operation to
	// nil is a no-op, every line of mplayer's output would be dropped without a
	// single error: no playback state, no time updates, no track info.
	private let queue = OperationQueue()

	@objc weak var delegate: LogAnalyzerDelegate?

	@objc(initWithDelegate:) convenience init(delegate: LogAnalyzerDelegate?) {
		self.init()
		self.delegate = delegate
	}

	deinit {
		stop()
	}

	@objc func stop() {
		queue.cancelAllOperations()
		queue.waitUntilAllOperationsAreFinished()
	}

	@objc(analyzeData:) func analyze(_ data: Data?) {
		// If there's no delegate, do nothing.
		// Therefore this class must have a delegate to work properly
		guard let data = data, !data.isEmpty, let delegate = delegate else { return }

		queue.addOperation(LogAnalyzeOperation(data: data, delegate: delegate))
	}
}

private final class LogAnalyzeOperation: Operation {

	private var log: Data?
	private weak var delegate: LogAnalyzerDelegate?

	init(data: Data, delegate: LogAnalyzerDelegate) {
		log = data
		self.delegate = delegate
		super.init()
	}

	/// The value starts one byte past the separator; the key starts after a
	/// leading "ANS_"/"MPX_" tag and runs up to the separator. Anything else on
	/// the line is mplayer chatter and is skipped.
	private static func validStart(_ bytes: UnsafeRawBufferPointer, from head: Int, to end: Int) -> Int? {
		guard end - head > 4, bytes[head + 3] == UInt8(ascii: "_") else { return nil }

		let tag = (bytes[head], bytes[head + 1], bytes[head + 2])
		if tag == (UInt8(ascii: "A"), UInt8(ascii: "N"), UInt8(ascii: "S")) ||
		   tag == (UInt8(ascii: "M"), UInt8(ascii: "P"), UInt8(ascii: "X")) {
			return head + 4
		}
		return nil
	}

	/// Returns the offset of the next newline, and the offset of the separator
	/// on that line. If multiple separators appear on a line, the farthest
	/// separator is returned.
	private static func nextReturnMark(_ bytes: UnsafeRawBufferPointer, from head: Int, to end: Int) -> (ret: Int?, split: Int?) {
		var split: Int?
		var i = head
		while i < end {
			if bytes[i] == UInt8(ascii: "\n") {
				return (i, split)
			} else if bytes[i] == UInt8(ascii: "=") {
				split = i
			}
			i += 1
		}
		return (nil, split)
	}

	override func main() {
		guard let log = log, let delegate = delegate as? NSObject else { return }

		log.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
			var head = 0
			let end = bytes.count

			while head < end && !isCancelled {
				let (retMarkOrNil, splitMark) = LogAnalyzeOperation.nextReturnMark(bytes, from: head, to: end)
				let retMark = retMarkOrNil ?? (end - 1)

				if let splitMark = splitMark,
				   let keyStart = LogAnalyzeOperation.validStart(bytes, from: head, to: splitMark) {
					// The second half is the value, the first half is the key
					let val = String(bytes: bytes[(splitMark + 1)..<retMark], encoding: .utf8)
					let key = String(bytes: bytes[keyStart..<splitMark], encoding: .utf8)

					if let val = val, let key = key {
						// Not DispatchQueue.main.async: this keeps the original's
						// default-run-loop-mode delivery, so playback updates stay
						// out of menu tracking and other modal loops.
						delegate.performSelector(onMainThread: #selector(LogAnalyzerDelegate.logAnalyzeFinished(_:)),
												 with: [key: val],
												 waitUntilDone: false)
					}
				}
				head = retMark + 1
			}
		}

		// Drop the data as soon as it is analyzed: the queue holds on to the
		// operation itself, and when it releases it is unknown.
		self.log = nil
	}
}
