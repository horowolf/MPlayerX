/*
 * MPlayerX - RootLayerView.m
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

#import <Quartz/Quartz.h>
#import "UserDefaults.h"
#import "KeyCode.h"
#import "RootLayerView.h"
#import "DisplayLayer.h"
#import "ControlUIView.h"
#import "PlayerController.h"
#import "ShortCutManager.h"
#import "OsdText.h"
#import "TitleView.h"
#import "CocoaAppendix.h"
#import "MPXAccessibilityConstants.h"
#import "MPlayerX-Swift.h"

#define kOnTopModeNormal		(0)
#define kOnTopModeAlways		(1)
#define kOnTopModePlaying		(2)

#define kScaleFrameRatioMinLimit	(0.05f)
#define kScaleFrameRatioStepMax		(0.20f)

#define kThreeFingersTapInit		(0)
#define kThreeFingersTapInvalid		(-1)
#define kThreeFingersTapReady		(1)

#define kThreeFingersPinchInit		(0)
#define kThreeFingersPinchInvalid	(-1)
#define kThreeFingersPinchReady		(1)

#define kFourFingersPinchInit		(0)
#define kFourFingersPinchInvalid	(-1)
#define kFourFingersPinchReady		(1)

// calculateFrameFrom:(NSRect)orgFrame toFit:(CGFloat)ar mode:(NSUInteger)modeMask;
#define kCalFrameSizeDiag			(1)
#define kCalFrameSizeInFit			(2)
#define kCalFrameSizeMask			(0xFF)

#define kCalFrameFixPosCenter		(1 << 8)
#define kCalFrameFixPosUpleft		(2 << 8)
#define kCalFrameFixPosMask			(0xFF00)

#define kFullScreenStatusNone		(0)
#define kFullScreenStatusLion		(1)
#define kFullScreenStatusOld		(2)

@interface RootLayerView (RootLayerViewInternal)
-(void) setExternalAspectRatio:(CGFloat)ar;
-(void) updateFrameForFullScreen;
-(NSRect) calculateFrameFrom:(NSRect)orgFrame toFit:(CGFloat)ar mode:(NSUInteger)modeMask;
-(void) setupLayers;
-(void) reorderSubviews;
-(void) prepareForStartingDisplay;

-(void) playBackOpened:(NSNotification*)notif;
-(void) playBackStarted:(NSNotification*)notif;
-(void) playBackStopped:(NSNotification*)notif;
-(void) playeBackFinalized:(NSNotification*)notif;

-(void) applicationDidBecomeActive:(NSNotification*)notif;
-(void) applicationDidResignActive:(NSNotification*)notif;

-(void) screenConfigurationChanged:(NSNotification*)notif;
@end

@interface RootLayerView (CoreDisplayDelegate)
-(int)  coreController:(id)sender startWithFormat:(DisplayFormat)df buffer:(char**)data total:(NSUInteger)num;
-(void) coreController:(id)sender draw:(NSUInteger)frameNum;
-(void) coreControllerStop:(id)sender;
@end

BOOL doesPrimaryScreenHasScreenAbove( void )
{
	NSRect frm, curFrm;
	NSScreen *scrn;
	NSEnumerator *it = [[NSScreen screens] objectEnumerator];
	
	// get the coordination of the Primary Screen
	frm = [[it nextObject] frame];
	
	// from the second screen
	while ((scrn = [it nextObject])) {
		
		curFrm = [scrn frame];
		
		if ((curFrm.origin.y - frm.origin.y) >= (frm.size.height - 1)) {
			return YES;
		}
	}
	return NO;
}

@implementation RootLayerView

@synthesize lockAspectRatio;

#pragma mark Init/Dealloc
+(void) initialize
{
	NSNumber *boolYes = [NSNumber numberWithBool:YES];
	NSNumber *boolNo  = [NSNumber numberWithBool:NO];
	
	[[NSUserDefaults standardUserDefaults] 
	 registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
					   [NSNumber numberWithInt:kOnTopModePlaying], kUDKeyOnTopMode,
					   boolNo, kUDKeyStartByFullScreen,
					   boolYes, kUDKeyFullScreenKeepOther,
					   boolNo, kUDKeyQuitOnClose,
					   boolNo, kUDKeyPinPMode,
					   boolNo, kUDKeyAlwaysHideDockInFullScrn,
					   boolYes, kUDKeyDisableHScrollSeek,
					   boolNo, kUDKeyDisableVScrollVol,
					   [NSNumber numberWithFloat:1.5], kUDKeyThreeFingersPinchThreshRatio,
					   [NSNumber numberWithFloat:1.8], kUDKeyFourFingersPinchThreshRatio,
					   boolNo, kUDKeyCloseWndOnEsc,
					   boolYes, kUDKeyDontResizeWhenContinuousPlay,
					   [NSNumber numberWithFloat:1.0], kUDKeyInitialFrameSizeRatio,
					   boolNo, kUDKeyOldFullScreenMethod,
					   boolNo, kUDKeyAlwaysUseSecondaryScreen,
					   nil]];
}

-(id) initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	
	if (self) {
		ud = [NSUserDefaults standardUserDefaults];
		notifCenter = [NSNotificationCenter defaultCenter];
		
		trackingArea = [[NSTrackingArea alloc] initWithRect:NSInsetRect([self frame], 1, 1) 
													options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect
													  owner:self
												   userInfo:nil];
		[self addTrackingArea:trackingArea];
		shouldResize = NO;
		rcBeforeFullScrn = [[self window] frame];
		
		dispLayer = [[DisplayLayer alloc] init];
		displaying = NO;
		fullScreenOptions = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
							 [NSNumber numberWithInt:NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar], NSFullScreenModeApplicationPresentationOptions,
							 [NSNumber numberWithBool:![ud boolForKey:kUDKeyFullScreenKeepOther]], NSFullScreenModeAllScreens,
							 [NSNumber numberWithInt:NSTornOffMenuWindowLevel], NSFullScreenModeWindowLevel,
							 nil];
		fullScreenStatus = kFullScreenStatusNone;
		lockAspectRatio = YES;
		frameAspectRatio = kDisplayAscpectRatioInvalid;
		dragShouldResize = NO;
		firstDisplay = YES;
		playbackFinalized = YES;
		canMoveAcrossMenuBar = doesPrimaryScreenHasScreenAbove();
		
		threeFingersTap = kThreeFingersTapInit;
		threeFingersPinch = kThreeFingersPinchInit;
		threeFingersPinchDistance = 1;
		fourFingersPinch = kFourFingersPinchInit;
		fourFingersPinchDistance = 1;

		[self setAcceptsTouchEvents:YES];
		[self setWantsRestingTouches:NO];
	}
	return self;
}

-(void) dealloc
{
	[notifCenter removeObserver:self];
	
	[self removeTrackingArea:trackingArea];
	[trackingArea release];
	[fullScreenOptions release];
	[dispLayer release];
	[logo release];
	
	[super dealloc];
}

-(void) setupLayers
{
	// set up the LayerHost; currently it only hosts one Layer
	[self setWantsLayer:YES];
	
	// get the basic rootLayer
	CALayer *root = [self layer];
	
	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	[root removeAllAnimations];
	// disable the resize action
	[root setDelegate:self];
	[root setDoubleSided:NO];

	// background color
	CGColorRef col =  CGColorCreateGenericGray(0.0, 1.0);
	[root setBackgroundColor:col];
	CGColorRelease(col);
	
	// border color
	col = CGColorCreateGenericRGB(0.392, 0.643, 0.812, 0.75);
	[root setBorderColor:col];
	CGColorRelease(col);
	
	// auto-resizing
	[root setAutoresizingMask:kCALayerWidthSizable|kCALayerHeightSizable];

	// icon setup
	logo = [[NSBitmapImageRep alloc] initWithCIImage:
			[CIImage imageWithContentsOfURL:
			 [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:@"logo.png"]]];
	[root setContentsGravity:kCAGravityCenter];
	[root setContents:(id)[logo CGImage]];
	
	// add dispLayer by default
	[root insertSublayer:dispLayer atIndex:0];
	
	// notify DispLayer
	[dispLayer setBounds:[root bounds]];
	[dispLayer setPosition:CGPointMake(root.bounds.size.width/2, root.bounds.size.height/2)];
	
	[CATransaction commit];
}
-(id<CAAction>) actionForLayer:(CALayer*)layer forKey:(NSString*)event { return ((id<CAAction>)[NSNull null]); }

-(void) reorderSubviews
{
	// put ControlUI on the top layer to prevent it being covered
	[controlUI retain];
	[controlUI removeFromSuperviewWithoutNeedingDisplay];
	[self addSubview:controlUI positioned:NSWindowAbove	relativeTo:nil];
	[controlUI release];
	
	[titlebar retain];
	[titlebar removeFromSuperviewWithoutNeedingDisplay];
	[self addSubview:titlebar positioned:NSWindowAbove relativeTo:nil];
	[titlebar release];
}

-(void) awakeFromNib
{
	[self setupLayers];
	
	[self reorderSubviews];
	
	// notify dispView to accept mplayer render notifications
	[playerController setDisplayDelegateForMPlayer:self];

	// set up to accept Drag Files
	[self registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType,nil]];

	[VTController setLayer:dispLayer];
	
	[notifCenter addObserver:self selector:@selector(playBackOpened:)
						name:kMPCPlayOpenedNotification object:playerController];
	[notifCenter addObserver:self selector:@selector(playBackStarted:)
						name:kMPCPlayStartedNotification object:playerController];
	[notifCenter addObserver:self selector:@selector(playBackStopped:)
						name:kMPCPlayStoppedNotification object:playerController];
	[notifCenter addObserver:self selector:@selector(playeBackFinalized:)
						name:kMPCPlayFinalizedNotification object:playerController];

	[notifCenter addObserver:self selector:@selector(applicationDidBecomeActive:)
						name:NSApplicationDidBecomeActiveNotification object:NSApp];
	[notifCenter addObserver:self selector:@selector(applicationDidResignActive:)
						name:NSApplicationDidResignActiveNotification object:NSApp];
	
	[notifCenter addObserver:self selector:@selector(screenConfigurationChanged:)
						name:NSApplicationDidChangeScreenParametersNotification object:NSApp];
}

-(void) screenConfigurationChanged:(NSNotification *)notif
{
	canMoveAcrossMenuBar = doesPrimaryScreenHasScreenAbove();
	MPLog(@"canMoveAcrossMenuBar:%d", canMoveAcrossMenuBar);
	
	if ((MPXGetSysVersion() >= kMPXSysVersionLion) &&
		(fullScreenStatus == kFullScreenStatusOld) &&
		([[NSScreen screens] count] == 1)) {
		// if it is a Lion system but the old fullscreen method was used, that means there were multiple screens at the time
		// but now there is only one screen, meaning the user unplugged the video cable, so we need to exit fullscreen
		[controlUI toggleFullScreen:nil];
	}
}

#pragma mark MPCNotification

-(void) playeBackFinalized:(NSNotification*)notif
{
	playbackFinalized = YES;
	
	NSInteger fsStatus = fullScreenStatus;
	
	// if not continuing playback, or there is no next file to play, exit fullscreen
	// at this point the display state, displaying, is NO
	// so, if in fullscreen it will exit fullscreen; if not in fullscreen it will not enter fullscreen either
	[controlUI toggleFullScreen:nil];
	// and reset the fillScreen state
	[controlUI toggleFillScreen:nil];
	
	if ([ud boolForKey:kUDKeyCloseWindowWhenStopped]) {
		// close cannot be used here, since using close would trigger the windowWillClose method
		if (fsStatus != kFullScreenStatusLion) {
			// if the Lion-style mode was used when exiting fullscreen
			// then we cannot orderOut now, because Lion-style fullscreen is asynchronous, so at this point it has not actually exited fullscreen yet
			// the actual window hiding is handled in the delegate function
			[[self window] orderOut:nil];			
		}
	} else {
		// at this point, if we are exiting from fullscreen, the window will not be shown
		// we need to force-show the window
		[[self window] makeKeyAndOrderFront:nil];
	}

	// playback fully completed, so resetAspectRatio now
	[self setExternalAspectRatio:kDisplayAscpectRatioInvalid];
	
	// playback fully ended, move the render area back to center
	[self moveFrameToCenter];
	[self resetFrameScaleRatio];
}

-(void) playBackStopped:(NSNotification*)notif
{
	firstDisplay = YES;
	playbackFinalized = NO;
	[self setPlayerWindowLevel];
	[playerWindow setTitle:kMPCStringMPlayerX];
	[[self layer] setContents:(id)[logo CGImage]];
}

-(void) playBackStarted:(NSNotification*)notif
{
	[self setPlayerWindowLevel];

	if ([[[notif userInfo] objectForKey:kMPCPlayStartedAudioOnlyKey] boolValue]) {
		// if audio only
		[[self layer] setContents:(id)[logo CGImage]];
		[playerWindow setContentSize:[playerWindow contentMinSize]];
		if (![NSApp isHidden]) {
			[playerWindow makeKeyAndOrderFront:nil];
		}
	} else {
		// if has video
		[[self layer] setContents:nil];
	}
}

-(void) playBackOpened:(NSNotification*)notif
{
	NSURL *url = [[notif userInfo] objectForKey:kMPCPlayOpenedURLKey];
	if (url) {		
		if ([url isFileURL]) {
			[playerWindow setTitle:[[[url path] lastPathComponent] stringByDeletingPathExtension]];
		} else {
			[playerWindow setTitle:[[url absoluteString] lastPathComponent]];
		}
	} else {
		[playerWindow setTitle:kMPCStringMPlayerX];
	}
}

#pragma mark keyboard/mouse
-(BOOL) acceptsFirstMouse:(NSEvent *)event { return YES; }
-(BOOL) acceptsFirstResponder { return YES; }

-(void) mouseMoved:(NSEvent *)theEvent
{
	if (NSPointInRect([self convertPoint:[theEvent locationInWindow] fromView:nil], self.bounds)) {
		[controlUI showUp];
		[controlUI updateHintTime];
	}
	[titlebar mouseMoved:theEvent];
}

-(void)mouseDown:(NSEvent *)theEvent
{
	dragMousePos = [NSEvent mouseLocation];
	NSRect winRC = [playerWindow frame];
	
	dragShouldResize = ((NSMaxX(winRC) - dragMousePos.x < 16) && (dragMousePos.y - NSMinY(winRC) < 16))?YES:NO;
	
	// MPLog(@"mouseDown");
}

- (void)mouseDragged:(NSEvent *)event
{
	BOOL ShiftKeyPressed = NO;
	
	// current location of the mouse
	NSPoint posNow = [NSEvent mouseLocation];
	NSPoint delta;
	
	// the position delta from last event
	delta.x = (posNow.x - dragMousePos.x);
	delta.y = (posNow.y - dragMousePos.y);

	dragMousePos = posNow;
	
	switch ([event modifierFlags] & (NSShiftKeyMask|NSControlKeyMask|NSAlternateKeyMask|NSCommandKeyMask)) {
		case NSShiftKeyMask|kSCMDragFullScrFrameModifierFlagMask:
			ShiftKeyPressed = YES;
			
		case kSCMDragFullScrFrameModifierFlagMask:
			if ([self isInFullScreenMode]) {
				// in fullscreen, move the render area
				CGPoint pt = [dispLayer positionOffsetRatio];
				CGSize sz = dispLayer.bounds.size;
				
				if (ShiftKeyPressed) {
					if (fabs(delta.x) > fabs(8 * delta.y)) {
						delta.y = 0;
					} else if (fabs(8 * delta.x) < fabs(delta.y)) {
						delta.x = 0;
					} else {
						// if use shift to drag the area, only X or only Y are accepted
						break;
					}
				}

				pt.x += (delta.x / sz.width);
				pt.y += (delta.y / sz.height);

				[dispLayer setPositoinOffsetRatio:pt];
				[dispLayer display];
			}
			break;
		//////////////////////////////////////////////////////////////////////////////////////////////////////
		case 0:
			if (![self isInFullScreenMode]) {
				// move the window when not in fullscreen

				if (dragShouldResize) {
					NSRect newFrame = [playerWindow frame];
					
					// new frame formed by the current mouse position and the window
					newFrame.size.width = posNow.x - newFrame.origin.x;
					newFrame.size.height = newFrame.size.height + newFrame.origin.y - posNow.y;
					newFrame.origin.y = posNow.y;
					
					CGFloat ar;
					
					if (displaying && lockAspectRatio) {
						// there is video displaying
						// get the new window size
						ar = [dispLayer aspectRatio];
					} else {
						ar = newFrame.size.width / newFrame.size.height;
					}
					newFrame = [self calculateFrameFrom:newFrame 
												  toFit:ar
												   mode:kCalFrameSizeInFit | kCalFrameFixPosUpleft];
					[playerWindow setFrame:newFrame display:YES animate:NO];
					// MPLog(@"%f,%f,%f,%f",newFrame.origin.x, newFrame.origin.y, newFrame.size.width, newFrame.size.height);
					// MPLog(@"should resize");
				} else {
					NSRect winFrm = [playerWindow frame];
					NSScreen *currentScrn = [[self window] screen];
					
					winFrm.origin.x += delta.x;
					winFrm.origin.y += delta.y;
					
					if (currentScrn == [[NSScreen screens] objectAtIndex:0] && (!canMoveAcrossMenuBar)) {
						// if the current screen has a menubar, do not let the window go past the menubar
						NSRect scrnFrm = [currentScrn visibleFrame];
						
						if ((winFrm.origin.y + winFrm.size.height) > (scrnFrm.origin.y + scrnFrm.size.height)) {
							winFrm.origin.y = scrnFrm.origin.y + scrnFrm.size.height - winFrm.size.height;
						}
					}
					
					[playerWindow setFrameOrigin:winFrm.origin];
					// MPLog(@"should move");
				}
			}
			break;
		default:
			break;
	}
}

-(void) mouseUp:(NSEvent *)theEvent
{
	if ([theEvent clickCount] == 2) {
		switch ([theEvent modifierFlags] & (NSShiftKeyMask| NSControlKeyMask|NSAlternateKeyMask|NSCommandKeyMask)) {
			case 0:
				[controlUI toggleFullScreen:nil];
				break;
			default:
				break;
		}
	}
	// do not use the playerWindow, since when fullscreen the window holds self is not playerWindow
	// when the mouse is released, automatically set FR to rootLayerView, so it can receive keyboard/mouse events
	[[self window] makeFirstResponder:self];
	// MPLog(@"mouseUp");
}

-(void) mouseEntered:(NSEvent *)theEvent
{
	[controlUI showUp];
}

-(void) mouseExited:(NSEvent *)theEvent
{
	if (![self isInFullScreenMode]) {
		// in fullscreen mode, be less aggressive about this
		[controlUI doHide];
	}
}

-(void) keyDown:(NSEvent *)theEvent
{
	if (![shortCutManager processKeyDown:theEvent]) {
		// if the shortcut manager does not handle this event, follow the default flow
		[super keyDown:theEvent];
	}
}

-(void) cancelOperation:(id)sender
{
	if ([self isInFullScreenMode]) {
		// when pressing Escape, exit fullscreen if being fullscreen
		[controlUI toggleFullScreen:nil];
	} else {
		if ([ud boolForKey:kUDKeyCloseWndOnEsc]) {
			[[self window] performClose:nil];
		}
	}
}

-(void)scrollWheel:(NSEvent *)theEvent
{
	float x, y;
	x = [theEvent deltaX];
	y = [theEvent deltaY];
    
    if ([theEvent respondsToSelector:@selector(isDirectionInvertedFromDevice)]) {
        MPLog(@"scrolling in Lion");
		if ([theEvent isDirectionInvertedFromDevice]) {
			x = -x;
			y = -y;
		}
    }
	
	switch ([theEvent modifierFlags] & (NSShiftKeyMask|NSControlKeyMask|NSAlternateKeyMask|NSCommandKeyMask)) {
		case kSCMScaleFrameKeyEquivalentModifierFlagMask:
			if ([self isInFullScreenMode]) {
				// only in full screen mode
				// in Y direction
				CGSize sz;
				sz.height = y / 100.0f;
				sz.width = sz.height;
				[self changeFrameScaleRatioBy:sz];
			}
			break;
		case 0:
			if ((fabsf(x) > fabsf(y*8)) && (![ud boolForKey:kUDKeyDisableHScrollSeek])) {
				// MPLog(@"%f", x);
				switch ([playerController playerState]) {
					case kMPCPausedState:
						if (x < 0) {
							[playerController frameStep];
						}
						break;
					case kMPCPlayingState:
						[controlUI changeTimeBy:-x];
						break;
					default:
						break;
				}
			} else if ((fabsf(x*8) < fabsf(y)) && (![ud boolForKey:kUDKeyDisableVScrollVol])) {
				[controlUI changeVolumeBy:[NSNumber numberWithFloat:y*0.2]];
			}
			break;
		default:
			break;
	}
}

-(void) magnifyWithEvent:(NSEvent *)event
{
	if ([self isInFullScreenMode]) {
		// in full screen
		CGSize sz;
		sz.height = [event magnification] / 2;
		sz.width = sz.height;
		[self changeFrameScaleRatioBy:sz];
	} else {
		[self changeWindowSizeBy:NSMakeSize([event magnification], [event magnification]) animate:NO];
	}
}

-(void) swipeWithEvent:(NSEvent *)event
{
	CGFloat x = [event deltaX];
	CGFloat y = [event deltaY];
	unichar key;
	
	if (x < 0) {
		key = NSRightArrowFunctionKey;
	} else if (x > 0) {
		key = NSLeftArrowFunctionKey;
	} else if (y > 0) {
		key = NSUpArrowFunctionKey;
	} else if (y < 0) {
		key = NSDownArrowFunctionKey;
	} else {
		key = 0;
	}
	
	if (key) {
		[shortCutManager processKeyDown:[NSEvent makeKeyDownEvent:[NSString stringWithCharacters:&key length:1] modifierFlags:0]];
	}
}

-(void) rotateWithEvent:(NSEvent*)event
{
	if ((!lockAspectRatio) || (([NSEvent modifierFlags] & NSAlternateKeyMask) == NSAlternateKeyMask)) {
		// if not locked, or if alt is pressed while locked
		float angle = atanf(1 / [dispLayer aspectRatio]);
		
		if ([event modifierFlags] & NSShiftKeyMask) {
			angle += [event rotation] * 3.1415926 / 720;				
		} else {
			angle += [event rotation] * 3.1415926 / 180;
		}
		angle = MIN(0.785/* 45 degree */, MAX(0.17 /* 10 degree */, angle));
		[self setAspectRatio:1/tanf(angle)];
	}
}

#pragma mark multitouch


float DistanceOf(NSPoint p1, NSPoint p2, NSPoint p3)
{
	return fabs(p1.x - p2.x) + fabs(p1.y - p2.y) +
	fabs(p1.x - p3.x) + fabs(p1.y - p3.y) +
	fabs(p2.x - p3.x) + fabs(p2.y - p3.y);
}

float AreaOf(NSPoint p1, NSPoint p2, NSPoint p3, NSPoint p4)
{
	CGFloat top, bottom, left, right;
	top = p1.y;
	bottom = p1.y;
	left = p1.x;
	right = p1.x;
	
	if (left   > p2.x) { left   = p2.x; }
	if (right  < p2.x) { right  = p2.x; }
	if (top    < p2.y) { top    = p2.y; }
	if (bottom > p2.y) { bottom = p2.y; }
	if (left   > p3.x) { left   = p3.x; }
	if (right  < p3.x) { right  = p3.x; }
	if (top    < p3.y) { top    = p3.y; }
	if (bottom > p3.y) { bottom = p3.y; }
	if (left   > p4.x) { left   = p4.x; }
	if (right  < p4.x) { right  = p4.x; }
	if (top    < p4.y) { top    = p4.y; }
	if (bottom > p4.y) { bottom = p4.y; }
	
	return fabs(top - bottom) * fabs(right - left);
}

-(void) touchesBeganWithEvent:(NSEvent*)event
{
	// MPLog(@"BEGAN");
	NSSet *touch = [event touchesMatchingPhase:NSTouchPhaseTouching inView:self];
	
	switch ([touch count]) {
		case 3:
			if (threeFingersTap == kThreeFingersTapInit) {
				// if it is a three-finger tap, and the state is currently OK, then it is ready
				threeFingersTap = kThreeFingersTapReady;
				// MPLog(@"Three Fingers Tap Ready");
			}
			
			if (threeFingersPinch == kThreeFingersPinchInit) {
				threeFingersPinch = kThreeFingersPinchReady;
				NSArray *touchAr = [touch allObjects];
				threeFingersPinchDistance = DistanceOf([[touchAr objectAtIndex:0] normalizedPosition],
													   [[touchAr objectAtIndex:1] normalizedPosition], 
													   [[touchAr objectAtIndex:2] normalizedPosition]);
				MPLog(@"Init 3f Dist:%f", threeFingersPinchDistance);
			}
			break;
		case 4:
			threeFingersTap = kThreeFingersTapInit;
			threeFingersPinch = kThreeFingersPinchInit;
			
			if (fourFingersPinch == kFourFingersPinchInit) {
				fourFingersPinch = kFourFingersPinchReady;
				NSArray *touchAr = [touch allObjects];
				fourFingersPinchDistance = AreaOf([[touchAr objectAtIndex:0] normalizedPosition],
												  [[touchAr objectAtIndex:1] normalizedPosition],
												  [[touchAr objectAtIndex:2] normalizedPosition],
												  [[touchAr objectAtIndex:3] normalizedPosition]);
				MPLog(@"Init 4f Dist:%f", fourFingersPinchDistance);
			}
			break;
			
		default:
			break;
	}
	[super touchesBeganWithEvent:event];
}

-(void) touchesMovedWithEvent:(NSEvent*)event
{
	// MPLog(@"MOVED");
	// whenever a move happens, it is no longer ready
	threeFingersTap = kThreeFingersTapInvalid;
	
	if (threeFingersPinch == kThreeFingersPinchReady) {
		NSSet *touch = [event touchesMatchingPhase:NSTouchPhaseMoved|NSTouchPhaseStationary inView:self];
		
		if ([touch count] == 3) {
			NSArray *touchAr = [touch allObjects];
			float dist = DistanceOf([[touchAr objectAtIndex:0] normalizedPosition],
									[[touchAr objectAtIndex:1] normalizedPosition], 
									[[touchAr objectAtIndex:2] normalizedPosition]);
			float thresh = [ud floatForKey:kUDKeyThreeFingersPinchThreshRatio];
			
			MPLog(@"Curr 3f Dist:%f", dist/threeFingersPinchDistance);
			if (((![self isInFullScreenMode]) && (dist > threeFingersPinchDistance * thresh)) ||
				(( [self isInFullScreenMode]) && (dist * thresh < threeFingersPinchDistance))){
				// toggle fullscreen
				threeFingersPinch = kThreeFingersPinchInit;
				[controlUI toggleFullScreen:nil];
			}
		}
	}
	
	if (fourFingersPinch == kFourFingersPinchReady) {
		NSSet *touch = [event touchesMatchingPhase:NSTouchPhaseMoved|NSTouchPhaseStationary inView:self];
		
		if ([touch count] == 4) {
			NSArray *touchAr = [touch allObjects];
			float dist = AreaOf([[touchAr objectAtIndex:0] normalizedPosition],
								[[touchAr objectAtIndex:1] normalizedPosition],
								[[touchAr objectAtIndex:2] normalizedPosition],
								[[touchAr objectAtIndex:3] normalizedPosition]);
			MPLog(@"Curr 4f Dist:%f", dist / fourFingersPinchDistance);
			
			if (dist * [ud floatForKey:kUDKeyFourFingersPinchThreshRatio] < fourFingersPinchDistance) {
				fourFingersPinch = kFourFingersPinchInit;
				[[self window] performClose:self];
			}
		}
	}
	[super touchesMovedWithEvent:event];
}

-(void) touchesEndedWithEvent:(NSEvent*)event
{
	// MPLog(@"ENDED");
	NSSet *touch = [event touchesMatchingPhase:NSTouchPhaseTouching inView:self];
	
	if ([touch count] == 0) {
		// once all fingers have left (except resting ones)
		if (threeFingersTap == kThreeFingersTapReady) {
			// if it is ready, toggle play pause
			[controlUI togglePlayPause:nil];
			// MPLog(@"Three Fingers Tap Trigger");
		}
		// regardless of whether it is ready, init, or invalid, reset everything once all fingers have left
		threeFingersTap = kThreeFingersTapInit;
		
		threeFingersPinch = kThreeFingersPinchInit;
		fourFingersPinch = kFourFingersPinchInit;
	}
	
	[super touchesEndedWithEvent:event];
}

-(void) touchesCancelledWithEvent:(NSEvent*)event
{
	// MPLog(@"CANCEL");
	threeFingersTap = kThreeFingersTapInit;
	threeFingersPinch = kThreeFingersPinchInit;
	fourFingersPinch = kFourFingersPinchInit;
	
	[super touchesCancelledWithEvent:event];
}

#pragma mark internal
-(void) resetFrameScaleRatio
{
	[dispLayer setScaleRatio:CGSizeMake(1, 1)];
	[dispLayer display];
}

-(void) changeFrameScaleRatioBy:(CGSize)rt
{
	CGSize ratio = [dispLayer scaleRatio];
	
	if (fabs(rt.width) > kScaleFrameRatioStepMax) {
		rt.width = (rt.width > 0)?(kScaleFrameRatioStepMax) : (-kScaleFrameRatioStepMax);
	}
	if (fabs(rt.height) > kScaleFrameRatioStepMax) {
		rt.height = (rt.height > 0)?(kScaleFrameRatioStepMax) : (-kScaleFrameRatioStepMax);
	}

	ratio.width  += rt.width;
	ratio.height += rt.height;
	
	if (ratio.width < kScaleFrameRatioMinLimit) {
		ratio.width = kScaleFrameRatioMinLimit;
	}
	if (ratio.height < kScaleFrameRatioMinLimit) {
		ratio.height = kScaleFrameRatioMinLimit;
	}
	
	[dispLayer setScaleRatio:ratio];
	[dispLayer display];
}

-(void) moveFrameToCenter
{
	[dispLayer setPositoinOffsetRatio:CGPointZero];
	[dispLayer display];
}

-(NSScreen*) findScreenFor:(NSRect)frame
{
	float areaMax = -1;
	NSArray *scrnList = [NSScreen screens];
	NSRect inter;
	NSScreen *ret = nil;
	
	for (NSScreen *scrn in scrnList) {
		inter = NSIntersectionRect([scrn frame], frame);
		if ((inter.size.width * inter.size.height) > areaMax) {
			ret = scrn;
			areaMax = inter.size.width * inter.size.height;
		}
	}
	return ret;
}

-(NSRect) calculateFrameFrom:(NSRect)orgFrame toFit:(CGFloat)ar mode:(NSUInteger)modeMask
{
	NSRect contentRect = [playerWindow contentRectForFrameRect:orgFrame];
	NSSize contentMinSize = [playerWindow contentMinSize];

	NSRect screenRc = [[self findScreenFor:orgFrame] visibleFrame];
	NSSize screenContentSize = [playerWindow contentRectForFrameRect:screenRc].size;

	if ((orgFrame.size.width <= 0) || (orgFrame.size.height <= 0)) {
		// invalid size, so use the window's current size
		orgFrame = [playerWindow contentRectForFrameRect:[playerWindow frame]];
	} else {
		orgFrame = contentRect;
	} // from here on, orgFrame is reused as the new content rect, to save stack

	if (!IsDisplayLayerAspectValid(ar)) {
		// if there is no target AR, then use the movie's original AR
		// note: not the movie's current AR -- when this API is called, the movie should already be in its current AR
		ar = [dispLayer originalAspectRatio];
	}
	if (!IsDisplayLayerAspectValid(ar)) {
		ar = orgFrame.size.width / orgFrame.size.height;
	}

	// we should really check whether ar > 0, but worst case it will just use orgFrame's current ar, so no check is needed

	// compute the transformed contentSize
	if ((modeMask & kCalFrameSizeMask) == kCalFrameSizeInFit) {
		// compute based on the containment relationship
		if (orgFrame.size.width > (orgFrame.size.height * ar)) {
			// becoming a portrait image
			orgFrame.size.width = orgFrame.size.height * ar;
		} else {
			// becoming a landscape image
			orgFrame.size.height = orgFrame.size.width / ar;
		}
	} else {
		// compute based on the diagonal
		float diagLen = hypotf(orgFrame.size.width, orgFrame.size.height);
		float angle = atanf(1/ar);

		orgFrame.size.width  = diagLen * cosf(angle);
		orgFrame.size.height = diagLen * sinf(angle);
	}
	
	// the max size needs both dimensions guaranteed, while the min size only needs one dimension guaranteed
	if (screenContentSize.width > (screenContentSize.height * ar)) {
		// becoming a portrait image, height overflows first, then width
		if (orgFrame.size.height > screenContentSize.height) {
			orgFrame.size.height = screenContentSize.height;
			orgFrame.size.width  = orgFrame.size.height * ar;
		}
	} else {
		// becoming a landscape image, width overflows first, then height
		if (orgFrame.size.width > screenContentSize.width) {
			orgFrame.size.width  = screenContentSize.width;
			orgFrame.size.height = orgFrame.size.width / ar;
		}			
	}

	if (contentMinSize.width > (contentMinSize.height * ar)) {
		// becoming a portrait image, width overflows first, then height
		if (orgFrame.size.height < contentMinSize.height) {
			orgFrame.size.height = contentMinSize.height;
			orgFrame.size.width  = orgFrame.size.height * ar;
		}
	} else {
		// becoming a landscape image, height overflows first, then width
		if (orgFrame.size.width < contentMinSize.width) {
			// prioritize width
			orgFrame.size.width  = contentMinSize.width;
			orgFrame.size.height = orgFrame.size.width / ar;
		}
	}
	// at this point we have the needed contentSize, stored in orgFrame.size
	
	// compute the new origin
	if ((modeMask & kCalFrameFixPosMask) == kCalFrameFixPosUpleft) {
		// align to the upper-left corner
		orgFrame.origin.y = contentRect.origin.y + contentRect.size.height - orgFrame.size.height;
	} else {
		// align to center
		orgFrame.origin.x += (contentRect.size.width  - orgFrame.size.width)  / 2;
		orgFrame.origin.y += (contentRect.size.height - orgFrame.size.height) / 2;
		orgFrame.origin.x = MAX(screenRc.origin.x, MIN(orgFrame.origin.x, screenRc.origin.x + screenRc.size.width  - orgFrame.size.width));
		orgFrame.origin.y = MAX(screenRc.origin.y, MIN(orgFrame.origin.y, screenRc.origin.y + screenRc.size.height - orgFrame.size.height));		
	}
	// from here on, orgFrame represents the latest content size and window origin
	
	// Apple's docs say ContentRect here uses Screen Coordinate
	// needs verification
	orgFrame = [playerWindow frameRectForContentRect:orgFrame];
	
	return orgFrame;
}

-(void) setExternalAspectRatio:(CGFloat)ar
{
	if (IsDisplayLayerAspectValid(ar)) {
		// if it is a valid value, that means it is an external AR, and the picture's AR needs to be computed from the external AR
		NSInteger lbMode = [ud integerForKey:kUDKeyLetterBoxMode];
		float margin = [ud floatForKey:kUDKeyLetterBoxHeight];
		
		switch (lbMode) {
			case kPMLetterBoxModeBoth:
				frameAspectRatio = ar * (1 + 2 * margin);
				break;
			case kPMLetterBoxModeBottomOnly:
			case kPMLetterBoxModeTopOnly:
				frameAspectRatio = ar * (1 + margin);
				break;
			default:
				frameAspectRatio = ar;
				break;
		}
	} else {
		frameAspectRatio = kDisplayAscpectRatioInvalid;
	}
	[dispLayer setExternalAspectRatio:ar];
}

-(void) setLockAspectRatio:(BOOL) lock
{
	if (lock != lockAspectRatio) {
		lockAspectRatio = lock;
		
		if (lockAspectRatio) {
			// if locking the aspect ratio, then go by the current window's
			// if in fullscreen, [self bounds] becomes the fullscreen size, which needs correcting
			NSSize sz = [self bounds].size;
			CGFloat ar = [dispLayer aspectRatio];
			
			sz.width = sz.height * ar;
			
			if (IsDisplayLayerAspectValid(ar)) {
				[playerWindow setContentAspectRatio:sz];
				[self setExternalAspectRatio:ar];
			}
		} else {
			[playerWindow setContentResizeIncrements:NSMakeSize(1.0, 1.0)];
		}
	}
}

-(void) resetAspectRatio
{
	if (displaying) {
		lockAspectRatio = YES;
		[self setAspectRatio:kDisplayAscpectRatioInvalid];
	}
}

-(void) setAspectRatio:(CGFloat) ar
{
	// if ar==kDisplayAscpectRatioInvalid, that means it is a reset
	// the calculateFrameFrom function will compute based on originalAspectRatio
	if (displaying) {
		
		NSRect newFrame;

		if (IsDisplayLayerAspectValid(ar)) {
			// valid means it is not a reset
			// if there is currently a letterbox, that would be a problem
			// needs compensating
			NSInteger lbMode = [ud integerForKey:kUDKeyLetterBoxMode];
			float margin = [ud floatForKey:kUDKeyLetterBoxHeight];
			
			switch (lbMode) {
				case kPMLetterBoxModeBoth:
					ar /= (1 + 2 * margin);
					break;
				case kPMLetterBoxModeBottomOnly:
				case kPMLetterBoxModeTopOnly:
					ar /= (1 + margin);
					break;
				default:
					break;
			}
		}
		
		if ([self isInFullScreenMode]) {
			[self setExternalAspectRatio:ar];
			[self updateFrameForFullScreen];
			newFrame = rcBeforeFullScrn;
		} else {
			newFrame = [self calculateFrameFrom:[[self window] frame] toFit:ar mode:kCalFrameFixPosCenter | kCalFrameSizeDiag];
			[playerWindow setFrame:newFrame display:YES animate:YES];
			[self setExternalAspectRatio:ar];
		}
		
		if (lockAspectRatio) {
			// if AR is locked, then the ratio needs to be reset
			[playerWindow setContentAspectRatio:[playerWindow contentRectForFrameRect:newFrame].size];

			[dispLayer display];
		} else {
			// if AR is not locked, dispLayer's AR will change along with the window, so nothing needs to be done for now
		}
	}
}

-(CIImage*) snapshot
{
	return [dispLayer snapshot];
}

-(CGFloat) aspectRatio
{
	return [dispLayer aspectRatio];
}

-(void) changeWindowSizeBy:(NSSize)delta animate:(BOOL)animate
{
	if (![self isInFullScreenMode]) {
		NSRect frm = [playerWindow frame];
		
		// the new target size
		delta.width  *= frm.size.width;
		delta.height *= frm.size.height;

		// target Rect
		frm.origin.x -= (delta.width ) / 2;
		frm.origin.y -= (delta.height) / 2;
		frm.size.width  += delta.width;
		frm.size.height += delta.height;
		
		frm = [self calculateFrameFrom:frm toFit:[dispLayer aspectRatio] mode:kCalFrameFixPosCenter | kCalFrameSizeDiag];
		
		[playerWindow setFrame:frm display:YES animate:animate];
	}
}

-(BOOL) isInFullScreenMode
{
	return (fullScreenStatus != kFullScreenStatusNone);
}

-(BOOL) toggleFullScreen
{
	BOOL oldWay = NO;
	
	if (fullScreenStatus == kFullScreenStatusNone) {
		// if not in fullscreen state, decide based on the current situation
		oldWay = ((MPXGetSysVersion() < kMPXSysVersionLion) ||
				  ([[NSScreen screens] count] > 1) ||
				  ([ud boolForKey:kUDKeyOldFullScreenMethod]));
	} else {
		// currently in fullscreen state, about to exit fullscreen
		// so it needs to stay consistent with the state used when entering fullscreen
		oldWay = (fullScreenStatus == kFullScreenStatusOld);
	}
	
	if (oldWay) {
		// ! note: the display state here differs from mplayer's playback state -- e.g. when mplayer is playing an MP3, the playback state is YES but the display state is NO
		if ([self isInFullScreenMode]) {
			// fullscreen can be exited regardless of whether it is currently displaying
			
			// this must only be set right when exiting fullscreen
			// before exiting fullscreen, this view does not belong to the window, so setting contentSize has no effect
			if (shouldResize) {
				shouldResize = NO;
				// get the target frame
				/*
				rcBeforeFullScrn = [self calculateFrameFrom:rcBeforeFullScrn
													  toFit:[dispLayer aspectRatio]
													   mode:kCalFrameSizeDiag | kCalFrameFixPosCenter];
				*/
				[dispLayer forceAdjustToFitBounds:YES];
				if (displaying) {
					// first put playerWindow behind the fullscreen window
					[playerWindow orderWindow:NSWindowBelow relativeTo:[[self window] windowNumber]];
					// exit fullscreen
					[self exitFullScreenModeWithOptions:fullScreenOptions];
					// cancel the various fullscreen-time settings
					[dispLayer enablePositionOffset:NO];
					[dispLayer enableScale:NO];
					// if CloseWindowWhenStopped is selected
					// when playback finishes and exits fullscreen, the window will be shown here, then closed back over in ControlUIView
					// this causes the window to flash, so only actively show the window when actually displaying
					[playerWindow makeKeyAndOrderFront:self];
				} else {
					// if not displaying, the window will not be shown at all
					// exit fullscreen
					[self exitFullScreenModeWithOptions:fullScreenOptions];
					[dispLayer enablePositionOffset:NO];
					[dispLayer enableScale:NO];
				}
				
				// if not displaying, then no animation is needed
				[playerWindow setFrame:rcBeforeFullScrn display:YES animate:displaying];
				[dispLayer display];
				[dispLayer forceAdjustToFitBounds:NO];
				
				// when entering fullscreen, ar was force-locked
				// when exiting fullscreen, after updating the window size, the window's ar needs to be set once more here
				[playerWindow setContentAspectRatio:[playerWindow contentRectForFrameRect:rcBeforeFullScrn].size];
			} else {
				[self exitFullScreenModeWithOptions:fullScreenOptions];
				
				// after exiting fullscreen, re-render the image according to the current size ratio
				[dispLayer enablePositionOffset:NO];
				[dispLayer enableScale:NO];
				[dispLayer display];
				
				if (displaying) {
					// if CloseWindowWhenStopped is selected
					// when playback finishes and exits fullscreen, the window will be shown here, then closed back over in ControlUIView
					// this causes the window to flash, so only actively show the window when actually displaying
					[playerWindow makeKeyAndOrderFront:self];
				}
			}
			[playerWindow makeFirstResponder:self];
			
			// window level can only be set after exiting fullscreen
			[self setPlayerWindowLevel];
			
			fullScreenStatus = kFullScreenStatusNone;
			
		} else if (displaying) {
			// should enter fullscreen
			// fullscreen can only be entered while an image is being displayed
			
			// force Lock Aspect Ratio
			[self setLockAspectRatio:YES];
			
			BOOL keepOtherSrn = [ud boolForKey:kUDKeyFullScreenKeepOther];
			
			NSScreen *chosenScreen;
			NSArray *scrnList = [NSScreen screens];
			if (([scrnList count] > 1) && [ud boolForKey:kUDKeyAlwaysUseSecondaryScreen]) {
				// if there are multiple screens, and always-use-secondary-screen is selected
				chosenScreen = [scrnList objectAtIndex:1];
			} else {
				// get the screen the window is currently on
				chosenScreen = [playerWindow screen];
			}
			
			// Presentation Options
			NSApplicationPresentationOptions opts;
			
			if (chosenScreen == [scrnList objectAtIndex:0] || (!keepOtherSrn)) {
				// if the main screen
				// there is no reason to always hide Dock, when MPX displayed in the secondary screen
				// so only do it in main screen
				if ([ud boolForKey:kUDKeyAlwaysHideDockInFullScrn]) {
					opts = NSApplicationPresentationHideDock | NSApplicationPresentationAutoHideMenuBar;
				} else {
					opts = NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar;
				}
			} else {
				// in secondary screens
				opts = [NSApp presentationOptions];
			}
			
			[fullScreenOptions setObject:[NSNumber numberWithInt:opts] forKey:NSFullScreenModeApplicationPresentationOptions];
			// whether grab all the screens
			[fullScreenOptions setObject:[NSNumber numberWithBool:!keepOtherSrn] forKey:NSFullScreenModeAllScreens];
			
			shouldResize = YES;
			// first record the window's position before fullscreen
			rcBeforeFullScrn = [playerWindow frame];
			// animate into fullscreen
			
			[dispLayer forceAdjustToFitBounds:YES];
			[playerWindow setFrame:[chosenScreen frame] display:YES animate:YES];
			[dispLayer display];
			
			// enter fullscreen
			[self enterFullScreenMode:chosenScreen withOptions:fullScreenOptions];
			// exit fullscreen, re-render the image according to the current size ratio
			[dispLayer enablePositionOffset:YES];
			[dispLayer enableScale:YES];
			// so it displays correctly when paused
			[dispLayer display];
			[dispLayer forceAdjustToFitBounds:NO];
			
			[playerWindow orderOut:self];
			
			[[self window] setCollectionBehavior:NSWindowCollectionBehaviorManaged];
			
			// get the screen's resolution, and compare it with the image being played
			// to know whether it is landscape or portrait
			NSSize sz = [self bounds].size;
			
			[controlUI setFillScreenMode:(((sz.height * [dispLayer aspectRatio]) >= sz.width)?kFillScreenButtonImageUBKey:kFillScreenButtonImageLRKey)
								   state:([dispLayer fillScreen])?NSOnState:NSOffState];
			fullScreenStatus = kFullScreenStatusOld;
		} else {
			// force a render once
			[dispLayer display];
			fullScreenStatus = kFullScreenStatusNone;
			return NO;
		}
	} else {
		// when it is Lion and there is only one screen
		if ([self isInFullScreenMode]) {
			// exit fullscreen
			if (shouldResize) {
				shouldResize = NO;
				// get the target frame
				/*
				rcBeforeFullScrn = [self calculateFrameFrom:rcBeforeFullScrn
													  toFit:[dispLayer aspectRatio]
													   mode:kCalFrameSizeDiag | kCalFrameFixPosCenter];
				*/
				// Lion-style fullscreen does not hide playerWindow
				// need to hide or show the window in the delegate function
				[playerWindow toggleFullScreenReal:self];
			} else {
				[playerWindow toggleFullScreenReal:self];
			}

			fullScreenStatus = kFullScreenStatusNone;
		} else if (displaying) {
			// enter fullscreen
			// force Lock Aspect Ratio
			[self setLockAspectRatio:YES];
			
			shouldResize = YES;
			// first record the window's position before fullscreen
			rcBeforeFullScrn = [playerWindow frame];
			
			[playerWindow toggleFullScreenReal:self];
			
			fullScreenStatus = kFullScreenStatusLion;
		} else {
			[dispLayer display];
			fullScreenStatus = kFullScreenStatusNone;
			return NO;
		}
	}
	return YES;
}

-(void) windowDidEnterFullScreen:(NSNotification *)notification
{	
	[[self window] makeFirstResponder:self];

	NSSize sz = [self bounds].size;
	
	[controlUI setFillScreenMode:(((sz.height * [dispLayer aspectRatio]) >= sz.width)?kFillScreenButtonImageUBKey:kFillScreenButtonImageLRKey)
						   state:([dispLayer fillScreen])?NSOnState:NSOffState];
}

-(void) windowDidExitFullScreen:(NSNotification *)notification
{
	if (!displaying && [ud boolForKey:kUDKeyCloseWindowWhenStopped]) {
		[[self window] orderOut:self];
	}
	// when entering fullscreen, ar was force-locked
	// when exiting fullscreen, after updating the window size, the window's ar needs to be set once more here
	[[self window] setContentAspectRatio:[[self window] contentRectForFrameRect:rcBeforeFullScrn].size];

	[[self window] makeFirstResponder:self];
	
	// window level can only be set after exiting fullscreen
	[self setPlayerWindowLevel];
}

-(NSSize) window:(NSWindow*)window willUseFullScreenContentSize:(NSSize)proposedSize
{
	MPLog(@"Prop Size:%f, %f", proposedSize.width, proposedSize.height);
	return proposedSize;
}

-(NSApplicationPresentationOptions) window:(NSWindow*)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions
{
	if ([ud boolForKey:kUDKeyAlwaysHideDockInFullScrn]) {
		return NSApplicationPresentationFullScreen | 
			   NSApplicationPresentationHideDock | 
			   NSApplicationPresentationAutoHideMenuBar;
	} else {
		return NSApplicationPresentationFullScreen |
			   NSApplicationPresentationAutoHideDock |
			   NSApplicationPresentationAutoHideMenuBar;
	}
}

-(NSArray*) customWindowsToEnterFullScreenForWindow:(NSWindow *)window
{
	if (window == playerWindow) {
		return [NSArray arrayWithObject:window];
	}
	return nil;
}

- (NSArray*) customWindowsToExitFullScreenForWindow:(NSWindow*)window
{
	if (window == playerWindow) {
		return [NSArray arrayWithObject:window];
	}
	return nil;	
}

-(void) window:(NSWindow*)window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
	[self invalidateRestorableState];
    
	[window setStyleMask:([window styleMask] | NSFullScreenWindowMask)];

    NSScreen *screen = [window screen];
    NSRect screenFrame = [screen frame];    
    NSRect proposedFrame = screenFrame;
	
    proposedFrame.size = [self window:window willUseFullScreenContentSize:proposedFrame.size];
    
    proposedFrame.origin.x += floor(0.5 * (NSWidth(screenFrame) - NSWidth(proposedFrame)));
    proposedFrame.origin.y += floor(0.5 * (NSHeight(screenFrame) - NSHeight(proposedFrame)));
    
	[dispLayer forceAdjustToFitBounds:YES];
	[dispLayer enablePositionOffset:YES];
	[dispLayer enableScale:YES];

	[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
		[context setDuration:0.5 * duration];
		[[window animator] setFrame:proposedFrame display:YES];		
	} completionHandler:^(void) {
		[dispLayer display];
		[dispLayer forceAdjustToFitBounds:NO];
	}];
}

-(void) window:(NSWindow*)window startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration
{
	[window setStyleMask:([window styleMask] & ~NSFullScreenWindowMask)];

	[dispLayer forceAdjustToFitBounds:YES];
	[dispLayer enablePositionOffset:NO];
	[dispLayer enableScale:NO];

	[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
		[context setDuration:0.5 * duration];
		[[window animator] setFrame:rcBeforeFullScrn display:YES animate:displaying];
	} completionHandler:^(void) {
		// so it displays correctly when paused
		[dispLayer display];
		[dispLayer forceAdjustToFitBounds:NO];
	}];
}

-(BOOL) toggleFillScreen
{
	[dispLayer setFillScreen: ![dispLayer fillScreen]];
	// so it displays correctly when paused
	[dispLayer display];
	return [dispLayer fillScreen];
}

-(void) setPlayerWindowLevel
{
	// in window mode
	int onTopMode = [ud integerForKey:kUDKeyOnTopMode];
	BOOL fullscr = [self isInFullScreenMode];
	
	if ((((onTopMode == kOnTopModeAlways)||((onTopMode == kOnTopModePlaying) && (playerController.playerState == kMPCPlayingState)))&&(!fullscr)) ||
		([NSApp isActive] && fullscr)) {
		[[self window] setLevel: NSTornOffMenuWindowLevel];
	} else {
		[[self window] setLevel: NSNormalWindowLevel];
	}
}

-(BOOL) mirror
{
	return [dispLayer mirror];
}

-(BOOL) flip
{
	return [dispLayer flip];
}

-(void) setMirror:(BOOL)m
{
	[dispLayer setMirror:m];
	[dispLayer display];
}

-(void) setFlip:(BOOL)f
{
	[dispLayer setFlip:f];
	[dispLayer display];
}

-(void) zoomToSize:(float)ratio
{
	if (displaying) {		
		NSSize orgSize = [dispLayer displaySize];
		CGFloat ar = [dispLayer aspectRatio];

		orgSize.width  *= ratio;
		orgSize.height *= ratio;

		if ([self isInFullScreenMode]) {
			CGSize curSize = [dispLayer bounds].size;
			CGSize sr = [dispLayer scaleRatio];
			
			orgSize.width = MIN(orgSize.width, orgSize.height * ar);
			
			CGFloat r = MAX(orgSize.width/curSize.width, orgSize.height/curSize.height);
			sr.width *= r;
			sr.height *= r;
			
			[dispLayer setScaleRatio:sr];
			[dispLayer display];
		} else {
			// not in full screen
			NSRect rc = [playerWindow contentRectForFrameRect:[playerWindow frame]];
			rc.origin.x -= (orgSize.width  - rc.size.width)  / 2;
			rc.origin.y -= (orgSize.height - rc.size.height) / 2;
			rc.size = orgSize;
			rc = [self calculateFrameFrom:[playerWindow frameRectForContentRect:rc] toFit:ar mode:kCalFrameFixPosCenter | kCalFrameSizeDiag];
			[playerWindow setFrame:rc display:YES animate:YES];
		}
	}
}

-(void) updateFrameForFullScreen
{
	// this function must be called while in fullscreen
	NSRect newFrame;
	
	shouldResize = YES;
	
	newFrame = [self calculateFrameFrom:rcBeforeFullScrn toFit:[dispLayer aspectRatio] mode:kCalFrameFixPosCenter | kCalFrameSizeDiag];
	
	rcBeforeFullScrn = newFrame;
	
	// determine the fillscreen state; this must be done after setExternalAspectRatio
	newFrame.size = [self bounds].size;
	[controlUI setFillScreenMode:(((newFrame.size.height * [dispLayer aspectRatio]) >= newFrame.size.width)?kFillScreenButtonImageUBKey:kFillScreenButtonImageLRKey)
						   state:([dispLayer fillScreen])?NSOnState:NSOffState];	
}

-(void) prepareForStartingDisplay
{
	if (firstDisplay) {
		// if this is the first display
		// but at this point the current externalAspectRatio is not known
		// if it is invalid, that means we need to keep our own state; if there is a value, that means we need to keep this aspect
		// until reset or finalized
		firstDisplay = NO;
		
		lockAspectRatio = YES;
		
		[controlUI displayStarted];
		
		if ([self isInFullScreenMode]) {
			[self updateFrameForFullScreen];
		} else {
			if ((![ud boolForKey:kUDKeyDontResizeWhenContinuousPlay]) || playbackFinalized) {
				// if forced to resize, or it is not continuous playback, resize to the original size
				[self zoomToSize:[ud floatForKey:kUDKeyInitialFrameSizeRatio]];
			} else {
				// AR needs to be adjusted here
				// if an external forced AR was set, set the window according to this AR
				// if no AR was set, fall the AR back to the original AR
				[self setAspectRatio:[dispLayer externalAspectRatio]];
			}
			
			[playerWindow setContentAspectRatio:[self bounds].size];
			
			if ([ud boolForKey:kUDKeyStartByFullScreen]) {
				// if using Lion-style fullscreen mode, since the window is never shown anywhere, a bug would occur
				// if using SL-style fullscreen mode, even though the window is shown here, it will be hidden again upon entering fullscreen, so it will not leak through
				[playerWindow makeKeyAndOrderFront:self];
				[controlUI toggleFullScreen:nil];
			} else {
				if (![NSApp isHidden]) {
					[playerWindow makeKeyAndOrderFront:self];
				}
			}
		}
	} else {
		// display being opened again during playback means either:
		// 1. letterbox and the like changing the AR from user action
		// 2. or a spontaneous change
		[controlUI displayStarted];
		
		CGFloat ar = kDisplayAscpectRatioInvalid;
		
		if (IsDisplayLayerAspectValid(frameAspectRatio)) {
			NSInteger lbMode = [ud integerForKey:kUDKeyLetterBoxMode];
			float margin = [ud floatForKey:kUDKeyLetterBoxHeight];
			
			switch (lbMode) {
				case kPMLetterBoxModeBoth:
					ar = frameAspectRatio / (1 + 2 * margin);
					break;
				case kPMLetterBoxModeBottomOnly:
				case kPMLetterBoxModeTopOnly:
					ar = frameAspectRatio / (1 + margin);
					break;
				default:
					ar = frameAspectRatio;
					break;
			}
		}
		
		if ([self isInFullScreenMode]) {
			[self updateFrameForFullScreen];
			
			if (IsDisplayLayerAspectValid(ar)) {
				
				if ([ud boolForKey:kUDKeyLBAutoHeightInFullScrn]) {
					// this is here to handle the AR for [auto height][landscape]
					// if it is portrait, letterbox will not be set, but display also will not be closed and reopened, so this is safe for now
					NSSize sz = [self bounds].size;
					[dispLayer setExternalAspectRatio:sz.width/sz.height];
					MPLog(@"prepare AR: %f", sz.width/sz.height);
				} else {
					// no need to use [self setExternalAspectRatio] here
					// that function would set frameAspectRatio again based on ar, which would be wasted work
					[dispLayer setExternalAspectRatio:ar];
				}
			}
			[dispLayer display];
		} else {
			NSRect frm = [self calculateFrameFrom:[playerWindow frame]
											toFit:IsDisplayLayerAspectValid(ar)?(ar):[dispLayer originalAspectRatio]
											 mode:kCalFrameFixPosCenter | kCalFrameSizeDiag];
			[playerWindow setFrame:frm display:YES animate:YES];
			if (IsDisplayLayerAspectValid([dispLayer externalAspectRatio])) {
				// if externalAspectRatio has a value set, that means it is forced
				// then update extAR
				// if extAR is invalid, that means we should respect the original AR, so nothing needs to be done
				[self setExternalAspectRatio:ar];
			}
		}
	}
}

#pragma mark drag/drop
///////////////////////////////////for dragging/////////////////////////////////////////
- (NSDragOperation) draggingEntered:(id <NSDraggingInfo>)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
	
    if ( [[pboard types] containsObject:NSFilenamesPboardType] && (sourceDragMask & NSDragOperationCopy)) {
		[[self layer] setBorderWidth:6.0];
		return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (void)draggingExited:(id < NSDraggingInfo >)sender
{
	[[self layer] setBorderWidth:0.0];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
	
	if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
		if (sourceDragMask & NSDragOperationCopy) {
			[[self layer] setBorderWidth:0.0];
			[playerController loadFiles:[pboard propertyListForType:NSFilenamesPboardType] fromLocal:YES];
		}
	}
	return YES;
}

#pragma mark coreController delegate
///////////////////////////////////!!!!!!!!!!!!!!!! these three methods are called on the worker thread; be careful if you need to touch the UI !!!!!!!!!!!!!!!!!!!!!!!!!/////////////////////////////////////////
-(int)  coreController:(id)sender startWithFormat:(DisplayFormat)df buffer:(char**)data total:(NSUInteger)num
{
	if ([dispLayer startWithFormat:df buffer:data total:num] == 0) {
		
		displaying = YES;

		[self performSelectorOnMainThread:@selector(prepareForStartingDisplay) withObject:nil waitUntilDone:YES];

		return 0;
	}
	return 1;
}

-(void) coreController:(id)sender draw:(NSUInteger)frameNum
{
	[dispLayer draw:frameNum];
}

-(void) coreControllerStop:(id)sender
{
	[dispLayer stop];

	displaying = NO;
	[controlUI displayStopped];
	[playerWindow setContentResizeIncrements:NSMakeSize(1.0, 1.0)];
}

#pragma mark Application notification
-(void) applicationDidBecomeActive:(NSNotification*)notif
{
	[self setPlayerWindowLevel];
}

-(void) applicationDidResignActive:(NSNotification*)notif
{
	[self setPlayerWindowLevel];
}

#pragma mark Window Delegate
-(void) windowWillClose:(NSNotification *)notification
{
	[[notification object] orderOut:nil];
	
	if ([ud boolForKey:kUDKeyQuitOnClose]) {
		[NSApp terminate:nil];
	} else {
		[playerController stop];
	}
}

-(BOOL)windowShouldZoom:(NSWindow *)window toFrame:(NSRect)newFrame
{
	return (displaying && (![window isZoomed]));
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)newFrame
{
	if (window == playerWindow) {		
		newFrame = [self calculateFrameFrom:[[window screen] visibleFrame]
									  toFit:[dispLayer aspectRatio]
									   mode:kCalFrameSizeDiag | kCalFrameFixPosCenter];
	}
	return newFrame;
}

-(void) windowDidResize:(NSNotification *)notification
{
	if (!lockAspectRatio) {
		// if aspect ratio is not locked
		NSSize sz = [self bounds].size;
		[self setExternalAspectRatio:(sz.width/sz.height)];
		[dispLayer display];
	}
}

#pragma mark Accessibility
-(void)accessibilitySetValue:(id)value forAttribute:(NSString *)attr
{
	if (![self isInFullScreenMode]) {
		NSRect rc = [playerWindow frame];
		
		if ([attr isEqualToString:NSAccessibilityPositionAttribute]) {
			rc.origin = [value pointValue];
		} else if ([attr isEqualToString:NSAccessibilitySizeAttribute]) {
			NSSize sz = [value sizeValue];
			
			// target Rect
			rc.origin.x -= (sz.width  - rc.size.width)  / 2;
			rc.origin.y -= (sz.height - rc.size.height) / 2;
			rc.size = sz;
		} else if ([attr isEqualToString:kMPXAccessibilityWindowFrameAttribute]) {
			rc = [value rectValue];

		} else {
			// only respond to position and size
			return;
		}
		
		rc = [self calculateFrameFrom:rc toFit:[dispLayer aspectRatio] mode:kCalFrameFixPosCenter|kCalFrameSizeInFit];
		[playerWindow setFrame:rc display:YES animate:NO];
	}
}
@end
