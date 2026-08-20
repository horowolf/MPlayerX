/*
 * MPlayerX - DisplayLayer.swift
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
import CoreVideo
import ObjectiveC
import OpenGL.GL
import QuartzCore

/// Swift mirror of the `kDisplayAscpectRatioInvalid` macro that used to live in
/// DisplayLayer.h. The ObjC callers that are not ported yet still get the macro
/// from DisplayLayerDefs.h; delete that header once they are Swift too.
let kDisplayAspectRatioInvalid: CGFloat = -1

@inline(__always) func IsDisplayLayerAspectValid(_ x: CGFloat) -> Bool { x > 0 }

/// The whole class is one big deprecated-OpenGL call site (CAOpenGLLayer,
/// CGL*, CVOpenGLTextureCache, immediate-mode GL). Marking the class deprecated
/// is what silences those warnings inside it -- Swift has no per-call pragma,
/// and the C-level GL_SILENCE_DEPRECATION define does not apply to Swift.
@available(macOS, deprecated: 10.14, message: "Built on the deprecated OpenGL stack; replacing it with Metal is a separate job")
@objc(DisplayLayer)
class DisplayLayer: CAOpenGLLayer {

	/// The decoded frames handed over by mplayer through the shared-memory
	/// buffer. Wrapped around the mmap'd bytes, never copied.
	private var frames: [CVPixelBuffer] = []
	private var frameNow: Int = -1

	private var cache: CVOpenGLTextureCache?

	private var fmt = DisplayFormat()
	private var externalAspectRatioValue: CGFloat = kDisplayAspectRatioInvalid

	private var positionOffset = false
	private var scaleEnabled = false
	private var renderRatio = CGRect(x: 0, y: 0, width: 1, height: 1)

	private var flagFillScrnChanged = true
	private var flagAspectRatioChanged = true
	private var flagPositionOffsetChanged = true
	private var flagScaleChanged = true

	@objc var fillScreen: Bool = false {
		didSet { flagFillScrnChanged = true }
	}
	@objc var mirror: Bool = false
	@objc var flip: Bool = false

	/// The ObjC original exposed this as a property whose setter selector was
	/// spelled `forceAdjustToFitBounds:`; Swift cannot rename just a setter, so
	/// the getter stays a property and the setter is a separate method with the
	/// original selector.
	@objc private(set) var refitBounds: Bool = false

	@objc(forceAdjustToFitBounds:)
	func forceAdjustToFitBounds(_ refit: Bool) {
		refitBounds = refit
	}

	//////////////////////////////////////Init/Dealloc/////////////////////////////////////
	override init() {
		super.init()

		fmt.aspect = kDisplayAspectRatioInvalid

		CATransaction.begin()
		CATransaction.setDisableActions(true)

		autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
		isAsynchronous = false
		// The layer could not be Opaque, since it wil cover
		// the root layer for logo display
		// isOpaque = true

		CATransaction.commit()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func action(forKey event: String) -> CAAction? { nil } // no animations for me

	@objc var snapshot: CIImage? {
		var buf: CVPixelBuffer?
		objc_sync_enter(self)
		if frameNow >= 0 && frameNow < frames.count {
			buf = frames[frameNow]
		}
		objc_sync_exit(self)

		guard let buf else { return nil }
		return CIImage(cvImageBuffer: buf)
	}

	/// get the display size; when SAR!=1, this size is not equal to the render size
	@objc var displaySize: NSSize {
		let w = CGFloat(fmt.width)
		let h = CGFloat(fmt.height)

		// if SAR != 1, then get the expanded display size
		if w <= h * fmt.aspect {
			return NSSize(width: h * fmt.aspect, height: h)
		}
		return NSSize(width: w, height: w / fmt.aspect)
	}

	@objc var aspectRatio: CGFloat {
		if externalAspectRatioValue > 0 {
			return externalAspectRatioValue
		} else if fmt.aspect > 0 {
			return fmt.aspect
		}
		return kDisplayAspectRatioInvalid
	}

	@objc var originalAspectRatio: CGFloat { fmt.aspect }

	@objc var externalAspectRatio: CGFloat {
		get { externalAspectRatioValue }
		set {
			externalAspectRatioValue = (newValue > 0) ? newValue : kDisplayAspectRatioInvalid
			flagAspectRatioChanged = true
		}
	}

	@objc var positionOffsetRatio: CGPoint { renderRatio.origin }

	/// The selector keeps the original's "Positoin" typo -- the ObjC callers
	/// that are still around spell it that way.
	@objc(setPositoinOffsetRatio:)
	func setPositoinOffsetRatio(_ ratio: CGPoint) {
		renderRatio.origin = ratio
		flagPositionOffsetChanged = true
	}

	@objc(enablePositionOffset:)
	func enablePositionOffset(_ offset: Bool) {
		positionOffset = offset
		flagPositionOffsetChanged = true
	}

	@objc(enableScale:)
	func enableScale(_ en: Bool) {
		scaleEnabled = en
		flagScaleChanged = true
	}

	@objc var scaleRatio: CGSize {
		get { renderRatio.size }
		set {
			renderRatio.size = newValue
			flagScaleChanged = true
		}
	}

	private func reshape() {
		CATransaction.begin()
		CATransaction.setDisableActions(true)

		if flagFillScrnChanged || flagAspectRatioChanged || flagScaleChanged || refitBounds {
			MPLogString("as fil changed")
			var rc = superlayer?.bounds ?? .zero
			let sAspect = aspectRatio

			if ((sAspect * rc.size.height) > rc.size.width) == fillScreen {
				rc.size.width = rc.size.height * sAspect
			} else {
				rc.size.height = rc.size.width / sAspect
			}

			if scaleEnabled {
				rc.size.width *= renderRatio.size.width
				rc.size.height *= renderRatio.size.height
			}

			bounds = rc

			flagAspectRatioChanged = false
			flagFillScrnChanged = false
			flagScaleChanged = false
		}

		if flagPositionOffsetChanged {
			MPLogString("pos changed")
			let outer = superlayer?.bounds ?? .zero
			var pt = CGPoint(x: outer.size.width / 2, y: outer.size.height / 2)

			let rc = bounds

			if positionOffset {
				pt.x += rc.size.width * renderRatio.origin.x
				pt.y += rc.size.height * renderRatio.origin.y
			}

			position = pt

			flagPositionOffsetChanged = false
		}
		CATransaction.commit()
	}

	/**
	 * something about 3 methods below and this layer
	 * 1. Now the layer is set as synchronous with setNeedsDisplay,
	 *    which means only the [setNeedsDisplay] is called,the layer
	 *    will redraw itself.
	 * 2. in [draw:frameNum], [setNeedsDisplay] was called, and this
	 *    cause layer redraw once after one new frame is ready.
	 * 3. [draw:frameNum] SHOULD be called NOT in the main thread, or
	 *    that will block the UI or cause the playback stuttered.
	 * 4. currently, [draw:frameNum] does be called in the thread rather
	 *    than the main thread, since in CoreController, the Connection
	 *    with mplayer-mt runs in the new thread, so actually the code runs
	 *    fine now.
	 * IN the future, setup a DisplayLink should be a better solution.
	 */
	@objc(startWithFormat:buffer:total:)
	func start(withFormat displayFormat: DisplayFormat,
			   buffer data: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
			   total num: UInt) -> Int32 {
		objc_sync_enter(self)

		fmt = displayFormat

		if let data, num > 0 {
			frames.reserveCapacity(Int(num))

			for i in 0 ..< Int(num) {
				var buf: CVPixelBuffer?
				var error = kCVReturnError

				if let base = data[i] {
					error = CVPixelBufferCreateWithBytes(nil,
														 Int(fmt.width), Int(fmt.height),
														 fmt.pixelFormat,
														 UnsafeMutableRawPointer(base),
														 Int(fmt.width * fmt.bytes),
														 nil, nil, nil,
														 &buf)
				}
				guard error == kCVReturnSuccess, let buf else {
					stop()
					MPLogString("video buffer failed")
					break
				}
				frames.append(buf)
			}
		}
		flagAspectRatioChanged = true

		let ok = !frames.isEmpty
		objc_sync_exit(self)

		isOpaque = true
		return ok ? 0 : 1
	}

	@objc(draw:)
	func draw(_ frameNum: UInt) {
		frameNow = Int(frameNum)
		display()
	}

	@objc func stop() {
		objc_sync_enter(self)

		frameNow = -1
		frames.removeAll()

		fmt = DisplayFormat()
		fmt.aspect = kDisplayAspectRatioInvalid
		flagAspectRatioChanged = true

		// externalAspectRatio must not be cleared here
		// because there could be multiple start/stop cycles during a single playback
		// when the user has forced externalAspectRatio, it should not be reset even across multiple start/stop calls
		// so it should be reset externally instead

		setNeedsDisplay()

		objc_sync_exit(self)

		isOpaque = false
	}

	//////////////////////////////////////OpenGLLayer inherent/////////////////////////////////////
	override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
		var i: GLint = 1

		let ctx = super.copyCGLContext(forPixelFormat: pf)

		MPLogString("pfrc:\(CGLGetPixelFormatRetainCount(pf))")

		CGLLockContext(ctx)

		CGLSetParameter(ctx, kCGLCPSwapInterval, &i)

		CGLEnable(ctx, kCGLCEMPEngine)

		cache = nil
		let error = CVOpenGLTextureCacheCreate(nil, nil, ctx, pf, nil, &cache)

		CGLUnlockContext(ctx)

		if error != kCVReturnSuccess {
			cache = nil
			MPLogString("video cache create failed")
		}
		return ctx
	}

	override func releaseCGLContext(_ ctx: CGLContextObj) {
		cache = nil

		super.releaseCGLContext(ctx)
	}

	override func draw(inCGLContext glContext: CGLContextObj,
					   pixelFormat: CGLPixelFormatObj,
					   forLayerTime timeInterval: CFTimeInterval,
					   displayTime timeStamp: UnsafePointer<CVTimeStamp>?) {
		// Grab the frame under the same lock start/stop use, then let go of it
		// again before doing any GL work. The ObjC original read the raw C array
		// unlocked; the buffers now live in a Swift array, which must not be
		// read while another thread is replacing it.
		var buf: CVPixelBuffer?
		objc_sync_enter(self)
		if frameNow >= 0 && frameNow < frames.count {
			buf = frames[frameNow]
		}
		objc_sync_exit(self)

		if let buf, let cache {
			var tex: CVOpenGLTexture?

			let error = CVOpenGLTextureCacheCreateTextureFromImage(nil, cache, buf, nil, &tex)

			if error == kCVReturnSuccess, let tex {
				// draw

				let cornerX: GLfloat = mirror ? -1 : 1
				let cornerY: GLfloat = flip ? -1 : 1

				CGLLockContext(glContext)
				CGLSetCurrentContext(glContext)

				let target = CVOpenGLTextureGetTarget(tex)

				glEnable(target)
				glBindTexture(target, CVOpenGLTextureGetName(tex))

				let texW = GLfloat(fmt.width)
				let texH = GLfloat(fmt.height)

				glBegin(GLenum(GL_QUADS))

				// directly compute the size the layer needs
				glTexCoord2f(   0,    0);	glVertex2f(-cornerX,  cornerY)
				glTexCoord2f(   0, texH);	glVertex2f(-cornerX, -cornerY)
				glTexCoord2f(texW, texH);	glVertex2f( cornerX, -cornerY)
				glTexCoord2f(texW,    0);	glVertex2f( cornerX,  cornerY)

				glEnd()

				glDisable(target)
				glFlush()

				CGLUnlockContext(glContext)

				// This is the end of normal render routine
				return
			}
		}

		// This is the routine when there is no content to render
		CGLLockContext(glContext)
		CGLSetCurrentContext(glContext)

		glClearColor(0, 0, 0, 0)
		glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

		glFlush()
		CGLUnlockContext(glContext)
	}

	override func display() {
		reshape()
		super.display()
	}

	override func layoutSublayers() {
		/*
		 Called when the layer requires layout.
		 Discussion
		 The default implementation invokes the layout manager method layoutSublayersOfLayer:,
		 if a layout manager is specified and it implements that method.
		 Subclasses can override this method to provide their own layout algorithm,
		 which must set the frame of each sublayer.

		 This is called when met with onLayout event,
		 since I don't have any sublayer, I could ignore this function.
		 */
	}
}
