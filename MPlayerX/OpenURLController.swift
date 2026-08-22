/*
 * MPlayerX - OpenURLController.swift
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

// These four constants were `NSString * const` globals in the ObjC original,
// but nothing outside OpenURLController.m ever referenced the symbols --
// only their string *values* matter (kBookmarkURLKey is a persisted plist
// key, the schemes are compared against NSURL.scheme), so they're plain
// private Swift constants here rather than anything ObjC-visible.
private let kBookmarkURLKey = "Bookmark:URL"
private let kURLPanelSupportedSchemes: Set<String> = ["http", "https", "ftp", "mms", "rtsp", "rtp", "udp"]

private let kMPXStringURLPanelClearMenu = NSLocalizedString("Clear Menu...", comment: "open url panel")
private let kMPXStringUseFFMpegHandleStream = NSLocalizedString("⌘-OK: Use FFMpeg to handle the stream", comment: "OpenURL Panel")
private let kMPXStringUseMPlayerHandleStream = NSLocalizedString("⌘-OK: Use MPlayer to handle the stream", comment: "OpenURL Panel")

private final class OpenURLModel: ObservableObject {
	@Published var hintText: String = ""
}

// A narrow protocol standing in for `PlayerController` (not yet ported to
// Swift). Importing PlayerController.h into the bridging header instead
// would create a build cycle: it #imports the generated MPlayerX-Swift.h,
// which doesn't exist until this Swift file has already compiled. Dynamic
// dispatch through this @objc protocol reaches the real -[PlayerController
// loadFiles:fromLocal:] implementation by selector match at runtime, same
// as any other ObjC message send, without needing the full header.
@objc protocol OpenURLFileLoading: AnyObject {
	func loadFiles(_ files: [String], fromLocal local: Bool)
}

// Wraps an already-constructed, already-configured AppKit view so SwiftUI
// only handles its layout, not its lifecycle. The combo box needs to exist
// (and be reachable from the controller) before the SwiftUI hierarchy is
// even built, because initURLList(_:) can be called at app-launch time --
// long before the panel is ever shown -- exactly like the old IBOutlet was
// reachable the moment the nib finished loading. Letting SwiftUI create and
// own the NSComboBox itself (the CharsetQueryController-style approach)
// would make that instance appear only once SwiftUI's own layout pass runs,
// which isn't guaranteed to have happened yet at that point.
private struct ExistingView<V: NSView>: NSViewRepresentable {
	let view: V
	func makeNSView(context: Context) -> V { view }
	func updateNSView(_ nsView: V, context: Context) {}
}

private struct OpenURLView: View {
	@ObservedObject var model: OpenURLModel
	let comboBox: NSComboBox
	let onCancel: () -> Void
	let onConfirm: () -> Void

	var body: some View {
		VStack(spacing: 10) {
			HStack {
				Text(NSLocalizedString("Media URL", comment: "OpenURL Panel"))
					.font(.system(size: 13))
					.frame(width: 71, alignment: .trailing)
				ExistingView(view: comboBox)
					.frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
			}
			HStack {
				Text(model.hintText)
					.font(.system(size: 10))
					.lineLimit(1)
				Spacer()
				Button(NSLocalizedString("Cancel", comment: "Panel Button"), action: onCancel)
					.keyboardShortcut(.cancelAction)
				Button(NSLocalizedString("OK", comment: "Panel Button"), action: onConfirm)
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding(16)
	}
}

@objc(OpenURLController)
class OpenURLController: NSObject {

	// Equivalent of the ObjC original's +initialize (see CharsetQueryController
	// for why this lazily-evaluated static stands in for it in Swift).
	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [kUDKeyFFMpegHandleStream: true])
	}()

	@IBOutlet weak var playerController: OpenURLFileLoading?

	// Built directly (not inside the SwiftUI hierarchy) so it's usable the
	// moment this object exists -- see ExistingView's doc comment above.
	private let comboBox: NSComboBox = {
		let box = NSComboBox()
		box.focusRingType = .none
		box.isEditable = true
		box.completes = false
		box.numberOfVisibleItems = 7
		return box
	}()

	private let model = OpenURLModel()

	// Always built by the end of init(), same guarantee CharsetQueryController
	// relies on for its own force-unwrapped uses of `window`.
	private var window: NSPanel?

	override init() {
		super.init()
		_ = OpenURLController.registerDefaultsOnce

		comboBox.target = self
		comboBox.action = #selector(comboBoxAction(_:))
		resetComboBoxItems()

		// Same fixed content size and style (titled only -- no close/miniaturize
		// button, Cancel/OK are the only way out) as the original xib's NSPanel.
		let contentRect = NSRect(x: 0, y: 0, width: 500, height: 94)
		let panel = NSPanel(contentRect: contentRect, styleMask: [.titled], backing: .buffered, defer: false)
		panel.title = NSLocalizedString("Open URL", comment: "OpenURL Panel")
		panel.isReleasedWhenClosed = false
		panel.minSize = contentRect.size
		panel.maxSize = contentRect.size

		let view = OpenURLView(model: model,
								comboBox: comboBox,
								onCancel: { [weak self] in self?.performCancel() },
								onConfirm: { [weak self] in self?.performConfirm() })
		panel.contentView = NSHostingView(rootView: view)

		window = panel
	}

	private func resetComboBoxItems() {
		comboBox.removeAllItems()
		comboBox.addItem(withObjectValue: kMPXStringURLPanelClearMenu)
	}

	@objc(initURLList:)
	func initURLList(_ list: [String: Any]?) {
		comboBox.removeAllItems()

		if let urls = list?[kBookmarkURLKey] as? [String] {
			comboBox.addItems(withObjectValues: urls)
		}

		comboBox.addItem(withObjectValue: kMPXStringURLPanelClearMenu)
	}

	@objc(addUrl:)
	func addUrl(_ urlString: String) {
		let idx = comboBox.indexOfItem(withObjectValue: urlString)

		if idx != 0 {
			// if it doesn't exist, or isn't in the first position
			if idx != NSNotFound {
				// if this string was already there, remove it and then add it at the first position
				comboBox.removeItem(at: idx)
			}
			comboBox.insertItem(withObjectValue: urlString, at: 0)
		}
	}

	@objc(syncToBookmark:)
	func syncToBookmark(_ bmk: NSMutableDictionary) {
		let urls = (comboBox.objectValues as? [String]) ?? []
		bmk[kBookmarkURLKey] = Array(urls.dropLast())
	}

	@IBAction @objc(urlSelected:)
	func urlSelected(_ sender: Any) {
		comboBoxAction(comboBox)
	}

	@objc private func comboBoxAction(_ sender: NSComboBox) {
		if sender.indexOfSelectedItem == sender.numberOfItems - 1 {
			resetComboBoxItems()
			sender.stringValue = ""
		}
	}

	@IBAction @objc(openURL:)
	func openURL(_ sender: Any) {
		// since this is a modal method, it is safe to set the hint text
		if UserDefaults.standard.bool(forKey: kUDKeyFFMpegHandleStream) {
			model.hintText = kMPXStringUseMPlayerHandleStream
		} else {
			model.hintText = kMPXStringUseFFMpegHandleStream
		}

		if NSApp.runModal(for: window!) == .OK {
			// mplayer's online playback feature is currently not very stable and freezes often, so disable this feature for now
			playerController?.loadFiles([comboBox.stringValue], fromLocal: false)
		}
	}

	@IBAction @objc(confirmed:)
	func confirmed(_ sender: Any) {
		performConfirm()
	}

	private func performConfirm() {
		let urlString = comboBox.stringValue

		if let url = URL(string: urlString),
		   let scheme = url.scheme?.lowercased(),
		   kURLPanelSupportedSchemes.contains(scheme) {
			// fix up the URL first
			comboBox.stringValue = url.standardized.absoluteString
			// exit Modal mode
			NSApp.stopModal(withCode: .OK)
			// hide the window
			window?.orderOut(self)
		} else {
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("Error", comment: "")
			alert.informativeText = NSLocalizedString("The URL is not supported by MPlayerX.", comment: "")
			alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
			if let window {
				alert.beginSheetModal(for: window, completionHandler: nil)
			}
		}
	}

	@IBAction @objc(canceled:)
	func canceled(_ sender: Any) {
		performCancel()
	}

	private func performCancel() {
		NSApp.abortModal()
		window?.orderOut(self)
	}
}
