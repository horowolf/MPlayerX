/*
 * MPlayerX - ControlUIView.m
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

#import "UserDefaults.h"
#import "KeyCode.h"
#import "LocalizedStrings.h"
#import "ControlUIView.h"
#import "RootLayerView.h"
#import "PlayerController.h"
#import "ArrowTextField.h"
#import "ResizeIndicator.h"
#import "OsdText.h"
#import "TitleView.h"
#import "CocoaAppendix.h"
#import "MPlayerX-Swift.h"
#import "DisplayLayer.h"
#import "TimeSliderCell.h"

#define CONTROLALPHA		(1)
#define BACKGROUNDALPHA		(0.9)

#define CONTROL_CORNER_RADIUS	(6)

#define NUMOFVOLUMEIMAGES		(3)	// this value is the number of images excluding the no-volume one
#define AUTOHIDETIMEINTERNAL	(3)

#define LASTSTOPPEDTIMERATIO	(100)

#define ASPECTRATIOBASE			(900)

NSString * const kFillScreenButtonImageLRKey = @"LR";
NSString * const kFillScreenButtonImageUBKey = @"UB";

NSString * const kStringFMTTimeAppendTotal	= @" / %@";

#define PlayState	(NSOnState)
#define PauseState	(NSOffState)

@interface ControlUIView (ControlUIViewInternal)
-(void) windowHasResized:(NSNotification*)notification;
-(void) calculateHintTime;
-(void) resetSubtitleMenu;
-(void) resetAudioMenu;
-(void) resetVideoMenu;
-(void) resetChapterListMenu;
-(void) tryToHide;

-(void) playBackOpened:(NSNotification*)notif;
-(void) playBackStarted:(NSNotification*)notif;
-(void) playBackStopped:(NSNotification*)notif;
-(void) playBackWillStop:(NSNotification*)notif;
-(void) playInfoUpdated:(NSNotification*)notif;

-(void) gotCurentTime:(NSNumber*) timePos;
-(void) gotSpeed:(NSNumber*) speed;
-(void) gotSubDelay:(NSNumber*) sd;
-(void) gotAudioDelay:(NSNumber*) ad;
-(void) gotMediaLength:(NSNumber*) length;
-(void) gotSeekableState:(NSNumber*) seekable;
-(void) gotSubInfo:(NSArray*) subs changed:(int)changeKind;
-(void) gotCachingPercent:(NSNumber*) caching;
-(void) gotAudioInfo:(NSArray*) ais;
-(void) gotVideoInfo:(NSArray*) vis;
-(void) gotChapterInfo:(NSArray*) cis;
@end


@implementation ControlUIView

+(void) initialize
{
	NSNumber *boolYes = [NSNumber numberWithBool:YES];
	NSNumber *boolNo  = [NSNumber numberWithBool:NO];
	
	[[NSUserDefaults standardUserDefaults] 
	 registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
					   [NSNumber numberWithFloat:50], kUDKeyVolume,
					   [NSNumber numberWithDouble:AUTOHIDETIMEINTERNAL], kUDKeyCtrlUIAutoHideTime,
					   boolNo, kUDKeySwitchTimeHintPressOnAbusolute,
					   boolNo, kUDKeyTimeTextAltTotal,
					   [NSNumber numberWithFloat:10], kUDKeyVolumeStep,
					   [NSNumber numberWithFloat:BACKGROUNDALPHA], kUDKeyCtrlUIBackGroundAlpha,
					   boolYes, kUDKeyShowOSD,
					   [NSNumber numberWithFloat:0.1], kUDKeyResizeStep,
					   boolYes, kUDKeyCloseWindowWhenStopped,
					   boolNo, kUDKeyHideTitlebar,
					   [NSNumber numberWithFloat:0.001], kUDKeyFrameScaleStep,
					   boolNo, kUDKeyLBAutoHeightInFullScrn,
					   boolNo, kUDKeyPlayWhenEnterFullScrn,
					   boolYes, kUDKeyResizeControlBar,
					   nil]];
}

-(id) initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	
	if (self) {
		ud = [NSUserDefaults standardUserDefaults];
		notifCenter = [NSNotificationCenter defaultCenter];
		
		shouldHide = NO;
		fillGradient = nil;
		backGroundColor = nil;
		backGroundColor2 = nil;
		autoHideTimer = nil;
		autoHideTimeInterval = 0;
		timeFormatter = [[TimeFormatter alloc] init];
		floatWrapFormatter = [[FloatWrapFormatter alloc] init];
		subListMenu = [[NSMenu alloc] initWithTitle:@"SubListMenu"];
		audioListMenu = [[NSMenu alloc] initWithTitle:@"AudioListMenu"];
		videoListMenu = [[NSMenu alloc] initWithTitle:@"VideoListMenu"];
		chapterListMenu = [[NSMenu alloc] initWithTitle:@"ChapterListMenu"];
	}
	return self;
}

- (void)awakeFromNib
{
	orgHeight = [self bounds].size.height;
	
	// settings for itself
	[self setAlphaValue:CONTROLALPHA];
	[self refreshBackgroundAlpha];
	// auto-hide settings
	[self refreshAutoHideTimer];

	if ([ud boolForKey:kUDKeyResizeControlBar]) {
		[self setAutoresizingMask:NSViewWidthSizable|NSViewMinXMargin|NSViewMaxXMargin|NSViewMinYMargin|NSViewMaxYMargin]; 
	} else {
		[self setAutoresizingMask:NSViewNotSizable|NSViewMinXMargin|NSViewMaxXMargin|NSViewMinYMargin|NSViewMaxYMargin];	 
	}
	
	////////////////////////////////////////set KeyEquivalents////////////////////////////////////////
	[volumeButton setKeyEquivalent:kSCMMuteKeyEquivalent];
	[playPauseButton setKeyEquivalent:kSCMPlayPauseKeyEquivalent];
	[fullScreenButton setKeyEquivalentModifierMask:kSCMFullscreenKeyEquivalentModifierFlagMask];
	[fullScreenButton setKeyEquivalent:kSCMFullScrnKeyEquivalent];

	[menuSnapshot setKeyEquivalent:kSCMSnapShotKeyEquivalent];

	[menuSubScaleInc setKeyEquivalentModifierMask:kSCMSubScaleIncreaseKeyEquivalentModifierFlagMask];
	[menuSubScaleInc setKeyEquivalent:kSCMSubScaleIncreaseKeyEquivalent];
	[menuSubScaleDec setKeyEquivalentModifierMask:kSCMSubScaleDecreaseKeyEquivalentModifierFlagMask];
	[menuSubScaleDec setKeyEquivalent:kSCMSubScaleDecreaseKeyEquivalent];
	
	[menuPlayFromLastStoppedPlace setKeyEquivalent:kSCMPlayFromLastStoppedKeyEquivalent];
	[menuPlayFromLastStoppedPlace setKeyEquivalentModifierMask:kSCMPlayFromLastStoppedKeyEquivalentModifierFlagMask];
	
	[menuSwitchSub setKeyEquivalent:kSCMSwitchSubKeyEquivalent];
	[menuSwitchAudio setKeyEquivalent:kSCMSwitchAudioKeyEquivalent];
	[menuSwitchVideo setKeyEquivalent:kSCMSwitchVideoKeyEquivalent];

	[menuVolInc setKeyEquivalent:kSCMVolumeUpKeyEquivalent];
	[menuVolDec setKeyEquivalent:kSCMVolumeDownKeyEquivalent];
	[menuVolInc setKeyEquivalentModifierMask:0];
	[menuVolDec setKeyEquivalentModifierMask:0];
	
	[menuToggleLockAspectRatio setKeyEquivalent:kSCMToggleLockAspectRatioKeyEquivalent];
	
	[menuResetLockAspectRatio setKeyEquivalent:kSCMResetLockAspectRatioKeyEquivalent];
	[menuResetLockAspectRatio setKeyEquivalentModifierMask:kSCMResetLockAspectRatioKeyEquivalentModifierFlagMask];
	
	[menuToggleLetterBox setKeyEquivalent:kSCMToggleLetterBoxKeyEquivalent];
	
	[menuSizeInc setKeyEquivalentModifierMask:kSCMWindowSizeIncKeyEquivalentModifierFlagMask];
	[menuSizeDec setKeyEquivalentModifierMask:kSCMWindowSizeDecKeyEquivalentModifierFlagMask];
	[menuSizeInc setKeyEquivalent:kSCMWindowSizeIncKeyEquivalent];
	[menuSizeDec setKeyEquivalent:kSCMWindowSizeDecKeyEquivalent];
	
	[menuShowMediaInfo setKeyEquivalent:kSCMShowMediaInfoKeyEquivalent];
	
	[menuToggleFullScreen setKeyEquivalent:kSCMFullScrnKeyEquivalent];
	[menuToggleFillScreen setKeyEquivalent:kSCMFillScrnKeyEquivalent];
	[menuToggleAuxiliaryCtrls setKeyEquivalent:kSCMAcceControlKeyEquivalent];
	
	[menuMoveToTrash setKeyEquivalentModifierMask:kSCMMoveToTrashKeyEquivalentModifierFlagMask];
	unichar keyTemp = kSCMMoveToTrashKeyEquivalent;
	[menuMoveToTrash setKeyEquivalent:[NSString stringWithCharacters:&keyTemp length:1]];
	
	[menuMoveFrameToCenter setKeyEquivalent:kSCMMoveFrameToCenterKeyEquivalent];
	
	[menuNextEpisode setKeyEquivalent:kSCMNextEpisodeKeyEquivalent];
	[menuPrevEpisode setKeyEquivalent:kSCMPrevEpisodeKeyEquivalent];

	[menuResetFrameScaleRatio setKeyEquivalentModifierMask:kSCMResetFrameScaleRatioKeyEquivalentModifierFlagMask];
	[menuResetFrameScaleRatio setKeyEquivalent:kSCMResetFrameScaleRatioKeyEquivalent];
	
	[menuEnlargeFrame setKeyEquivalentModifierMask:kSCMScaleFrameLargerKeyEquivalentModifierFlagMask];
	[menuEnlargeFrame setKeyEquivalent:kSCMScaleFrameLargerKeyEquivalent];
	[menuShrinkFrame setKeyEquivalentModifierMask:kSCMScaleFrameSmallerKeyEquivalentModifierFlagMask];
	[menuShrinkFrame setKeyEquivalent:kSCMScaleFrameSmallerKeyEquivalent];
	
	[menuEnlargeFrame2 setKeyEquivalentModifierMask:kSCMScaleFrameLarger2KeyEquivalentModifierFlagMask];
	[menuEnlargeFrame2 setKeyEquivalent:kSCMScaleFrameLargerKeyEquivalent];
	[menuShrinkFrame2 setKeyEquivalentModifierMask:kSCMScaleFrameSmaller2KeyEquivalentModifierFlagMask];
	[menuShrinkFrame2 setKeyEquivalent:kSCMScaleFrameSmallerKeyEquivalent];
	
	[menuMirror setKeyEquivalentModifierMask:kSCMMirrorKeyEquivalentModifierFlagMask];
	[menuMirror setKeyEquivalent:kSCMMirrorKeyEquivalent];
	[menuFlip setKeyEquivalentModifierMask:kSCMFlipKeyEquivalentModifierFlagMask];
	[menuFlip setKeyEquivalent:kSCMFlipKeyEquivalent];

	[menuSpeedUp setKeyEquivalent:kSCMSpeedUpKeyEquivalent];
	[menuSpeedDown setKeyEquivalent:kSCMSpeedDownKeyEquivalent];
	[menuSpeedReset setKeyEquivalent:kSCMSpeedResetKeyEquivalent];
	
	[menuAudioDelayInc setKeyEquivalentModifierMask:kSCMAudioDelayKeyEquivalentModifierFlagMask];
	[menuAudioDelayInc setKeyEquivalent:kSCMAudioDelayPlusKeyEquivalent];
	[menuAudioDelayDec setKeyEquivalentModifierMask:kSCMAudioDelayKeyEquivalentModifierFlagMask];
	[menuAudioDelayDec setKeyEquivalent:kSCMAudioDelayMinusKeyEquivalent];
	[menuAudioDelayReset setKeyEquivalentModifierMask:kSCMAudioDelayKeyEquivalentModifierFlagMask];
	[menuAudioDelayReset setKeyEquivalent:kSCMAudioDelayResetKeyEquivalent];
	
	[menuSubDelayInc setKeyEquivalentModifierMask:kSCMSubDelayKeyEquivalentModifierFlagMask];
	[menuSubDelayInc setKeyEquivalent:kSCMSubDelayPlusKeyEquivalent];
	[menuSubDelayDec setKeyEquivalentModifierMask:kSCMSubDelayKeyEquivalentModifierFlagMask];
	[menuSubDelayDec setKeyEquivalent:kSCMSubDelayMinusKeyEquivalent];
	[menuSubDelayReset setKeyEquivalentModifierMask:kSCMSubDelayKeyEquivalentModifierFlagMask];
	[menuSubDelayReset setKeyEquivalent:kSCMSubDelayResetKeyEquivalent];
	
	[menuZoomToHalfSize setKeyEquivalentModifierMask:kSCMWindowZoomHalfSizeKeyEquivalentModifierFlagMask];
	[menuZoomToHalfSize setKeyEquivalent:kSCMWindowZoomHalfSizeKeyEquivalent];
	[menuZoomToOriginSize setKeyEquivalentModifierMask:kSCMWindowZoomToOrgSizeKeyEquivalentModifierFlagMask];
	[menuZoomToOriginSize setKeyEquivalent:kSCMWindowZoomToOrgSizeKeyEquivalent];
	[menuZoomToDoubleSize setKeyEquivalentModifierMask:kSCMWindowZoomDblSizeKeyEquivalentModifierFlagMask];
	[menuZoomToDoubleSize setKeyEquivalent:kSCMWindowZoomDblSizeKeyEquivalent];
	[menuWndFitToScrn setKeyEquivalentModifierMask:kSCMWindowFitToScreenKeyEquivalentModifierFlagMask];
	[menuWndFitToScrn setKeyEquivalent:kSCMWindowFitToScreenKeyEquivalent];
	
	////////////////////////////////////////load Images////////////////////////////////////////
	// initialize the volume-level icons
	volumeButtonImages = [[NSArray alloc] initWithObjects:	[NSImage imageNamed:@"vol_no"], [NSImage imageNamed:@"vol_low"],
															[NSImage imageNamed:@"vol_mid"], [NSImage imageNamed:@"vol_high"],
															nil];
	// fillScreenButton initialization
	fillScreenButtonAllImages =  [[NSDictionary alloc] initWithObjectsAndKeys: 
								  [NSArray arrayWithObjects:[NSImage imageNamed:@"fillscreen_lr"], [NSImage imageNamed:@"exitfillscreen_lr"], nil], kFillScreenButtonImageLRKey,
								  [NSArray arrayWithObjects:[NSImage imageNamed:@"fillscreen_ub"], [NSImage imageNamed:@"exitfillscreen_ub"], nil], kFillScreenButtonImageUBKey, 
								  nil];
	
	// get the default volume value from userdefault
	// [volumeSlider setFloatValue:];
	[self setVolume:[ud objectForKey:kUDKeyVolume]];
	
	// Mask mouseup event
	[volumeSlider sendActionOn:NSLeftMouseDownMask|NSLeftMouseDraggedMask];

	// set Volume menu
	[menuVolInc setEnabled:YES];
	[menuVolInc setTag:1];	
	[menuVolDec setEnabled:YES];
	[menuVolDec setTag:-1];
	
	// set Volume step
	volStep = [ud floatForKey:kUDKeyVolumeStep];

	// initialize the time display slider and text
	[[timeText cell] setFormatter:timeFormatter];
	[timeText setStringValue:@""];
	[[timeTextAlt cell] setFormatter:timeFormatter];
	[timeTextAlt setStringValue:@""];
	
	[timeSlider setEnabled:NO];
	[timeSlider setMaxValue:0];
	[timeSlider setMinValue:-1];
	// only trigger the event on drag and mouse down
	[timeSlider sendActionOn:NSLeftMouseDownMask|NSLeftMouseDraggedMask];

	// set Time hint text
	[hintTime setAlphaValue:0];
	[[hintTime cell] setFormatter:timeFormatter];
	[hintTime setStringValue:@""];

	// initial state is hidden
	[fullScreenButton setHidden: YES];

	// set fillscreen button status and image
	[fillScreenButton setHidden: YES];	
	NSArray *fillScrnBtnModeImages = [fillScreenButtonAllImages objectForKey:kFillScreenButtonImageUBKey];
	[fillScreenButton setImage: [fillScrnBtnModeImages objectAtIndex:0]];
	[fillScreenButton setAlternateImage:[fillScrnBtnModeImages objectAtIndex:1]];
	[fillScreenButton setState: NSOffState];
	
	// set fomatter and step
	[[speedText cell] setFormatter:floatWrapFormatter];
	[[subDelayText cell] setFormatter:floatWrapFormatter];
	[[audioDelayText cell] setFormatter:floatWrapFormatter];
	
	[speedText setStepValue:[ud floatForKey:kUDKeySpeedStep]];
	[subDelayText setStepValue:[ud floatForKey:kUDKeySubDelayStepTime]];
	[audioDelayText setStepValue:[ud floatForKey:kUDKeyAudioDelayStepTime]];

	// set list for sub/audio/video menu
	[menuSwitchSub setSubmenu:subListMenu];
	[subListMenu setAutoenablesItems:NO];
	[self resetSubtitleMenu];
	
	[menuSwitchAudio setSubmenu:audioListMenu];
	[audioListMenu setAutoenablesItems:NO];
	[self resetAudioMenu];
	
	[menuSwitchVideo setSubmenu:videoListMenu];
	[videoListMenu setAutoenablesItems:NO];
	[self resetVideoMenu];
	
	[menuChapterList setSubmenu:chapterListMenu];
	[chapterListMenu setAutoenablesItems:NO];
	[self resetChapterListMenu];
	
	// set menuItem tags
	[menuSubScaleInc setTag:1];
	[menuSubScaleDec setTag:-1];
	
	[menuSizeInc setTag:1];
	[menuSizeDec setTag:-1];

	// set menu status
	[menuToggleLockAspectRatio setEnabled:NO];
	[menuToggleLockAspectRatio setTitle:([dispView lockAspectRatio])?(kMPXStringMenuUnlockAspectRatio):(kMPXStringMenuLockAspectRatio)];
	
	[menuToggleLetterBox setTitle:([ud integerForKey:kUDKeyLetterBoxMode] == kPMLetterBoxModeNotDisplay)?(kMPXStringMenuShowLetterBox):
																										 (kMPXStringMenuHideLetterBox)];
	[menuToggleFullScreen setEnabled:NO];
	[menuToggleFullScreen setTitle:kMPXStringMenuEnterFullscrn];
	
	[menuToggleFillScreen setEnabled:NO];
	
	[toggleAcceButton setTag:NO];

	[menuToggleAuxiliaryCtrls setTag:NO];
	[menuToggleAuxiliaryCtrls setTitle:kMPXStringMenuShowAuxCtrls];
	[menuToggleAuxiliaryCtrls setEnabled:NO];
	
	//////ibtool bug fix, set noborder////////
	[volumeButton setBordered:NO];
	[nextEPButton setBordered:NO];
	[prevEPButton setBordered:NO];
	[playPauseButton setBordered:NO];
	[fillScreenButton setBordered:NO];
	[fullScreenButton setBordered:NO];
	[toggleAcceButton setBordered:NO];
	[timeText setBordered:NO];
	[timeTextAlt setBordered:NO];
	[timeDispSwitch setBordered:NO];
	
	// set OSD active status
	[osd setActive:NO];
	
	[notifCenter addObserver:self selector:@selector(windowHasResized:)
						name:NSWindowDidResizeNotification
					  object:[self window]];
	
	[notifCenter addObserver:self selector:@selector(playBackOpened:)
						name:kMPCPlayOpenedNotification object:playerController];
	[notifCenter addObserver:self selector:@selector(playBackStarted:)
						name:kMPCPlayStartedNotification object:playerController];
	[notifCenter addObserver:self selector:@selector(playBackWillStop:)
						name:kMPCPlayWillStopNotification object:playerController];
	[notifCenter addObserver:self selector:@selector(playBackStopped:)
						name:kMPCPlayStoppedNotification object:playerController];

	[notifCenter addObserver:self selector:@selector(playInfoUpdated:)
						name:kMPCPlayInfoUpdatedNotification object:playerController];
	
	// this functioin must be called after the Notification is setuped
	[playerController setupKVO];

	// force hide titlebar
	[title setAlphaValue:([ud boolForKey:kUDKeyHideTitlebar])?0:CONTROLALPHA];
}

-(void) dealloc
{
	[notifCenter removeObserver:self];
	
	if (autoHideTimer) {
		[autoHideTimer invalidate];
	}

	[fillScreenButtonAllImages release];
	[volumeButtonImages release];
	[timeFormatter release];
	[floatWrapFormatter release];
	
	[menuSwitchSub setSubmenu:nil];
	[subListMenu release];

	[menuSwitchAudio setSubmenu:nil];
	[audioListMenu release];
	
	[menuSwitchVideo setSubmenu:nil];
	[videoListMenu release];
	
	[menuChapterList setSubmenu:nil];
	[chapterListMenu release];
	
	[fillGradient release];
	[backGroundColor release];
	[backGroundColor2 release];
	
	[super dealloc];
}

-(BOOL) acceptsFirstMouse:(NSEvent *)event { return YES; }
-(BOOL) acceptsFirstResponder { return YES; }

-(void) refreshBackgroundAlpha
{
	[fillGradient release];
	[backGroundColor release];
	[backGroundColor2 release];
	
	float backAlpha = [ud floatForKey:kUDKeyCtrlUIBackGroundAlpha];

	fillGradient = [[NSGradient alloc] initWithColorsAndLocations:[NSColor colorWithDeviceWhite:0.220 alpha:backAlpha], 0.00f,
																  [NSColor colorWithDeviceWhite:0.150 alpha:backAlpha], 0.30f,
																  [NSColor colorWithDeviceWhite:0.090 alpha:backAlpha], 0.33f,
																  [NSColor colorWithDeviceWhite:0.050 alpha:backAlpha], 1.00f,	
																  nil];
	backGroundColor  = [[NSColor colorWithDeviceWhite:0.45 alpha:backAlpha] retain];
	backGroundColor2 = [[NSColor colorWithDeviceWhite:0.32 alpha:backAlpha] retain];
	
	[self setNeedsDisplay:YES];
}

-(void) refreshOSDSetting
{
	BOOL new = [ud boolForKey:kUDKeyShowOSD]; 
	if (new) {
		// if showing OSD, then get the new value
		[osd setAutoHideTimeInterval:[ud doubleForKey:kUDKeyOSDAutoHideTime]];
		[osd setFrontColor:[NSUnarchiver unarchiveObjectWithData:[ud objectForKey:kUDKeyOSDFrontColor]]];
		// and force-show OSD, but this may not match the OSD's current state
		[osd setActive:YES];
		[osd setStringValue:kMPXStringOSDSettingChanged owner:kOSDOwnerOther updateTimer:YES];
	}
	if ([playerController couldAcceptCommand]) {
		// if currently playing, then set it to show
		// if not playing, osd's active state will be force-set to OFF, so it cannot be set here
		// the active state will be set again when playback starts
		[osd setActive:new];
	}
}
////////////////////////////////////////////////AutoHideThings//////////////////////////////////////////////////
-(void) refreshAutoHideTimer
{
	float ti = [ud doubleForKey:kUDKeyCtrlUIAutoHideTime];
	
	if ((ti != autoHideTimeInterval) && (ti > 0)) {
		// this Timer is not retained, so it does not need to be released either
		if (autoHideTimer) {
			[autoHideTimer invalidate];
			autoHideTimer = nil;
		}
		autoHideTimeInterval = ti;
		autoHideTimer = [NSTimer timerWithTimeInterval:autoHideTimeInterval/2
												target:self
											  selector:@selector(tryToHide)
											  userInfo:nil
											   repeats:YES];
		[[NSRunLoop mainRunLoop] addTimer:autoHideTimer forMode:NSDefaultRunLoopMode];
	}
}

-(void) doHide
{
	// this code must not be reentered, otherwise it will keep calling hidecursor
	if ([self alphaValue] > (CONTROLALPHA-0.05)) {
		// get the mouse coordinates in this window
		NSPoint pos = [[self window] convertScreenToBase:[NSEvent mouseLocation]];
		
		// if not within this View, then hide itself
		// if HideTitlebar is ON, ignore the titlebar area when hiding the cursor
		if ((!NSPointInRect([self  convertPoint:pos fromView:nil], self.bounds)) && 
			((!NSPointInRect([title convertPoint:pos fromView:nil], title.bounds)) || [ud boolForKey:kUDKeyHideTitlebar])) {
			[self.animator setAlphaValue:0];
			
			// also hide the mouse if in fullscreen mode
			if ([dispView isInFullScreenMode]) {
				// [self window] here is not the member window, but self's new window after entering fullscreen
				if ([[self window] isKeyWindow] && NSPointInRect([NSEvent mouseLocation], [[self window] frame])) {
					// if it is not the key window, do not hide the mouse
					[NSCursor hide];
				}
			} else {
				// if not fullscreen, hide the resizeindicator
				// if fullscreen, leave it alone
				[rzIndicator.animator setAlphaValue:0];
				// this should check kUDKeyHideTitlebar, but since we are hiding the title here anyway
				// setting AlphaValue to 0 multiple times will not cause any harm
				[title.animator setAlphaValue:0];
			}
		}			
	}	
}

-(void) tryToHide
{
	if (shouldHide) {
		[self doHide];
	} else {
		shouldHide = YES;
	}
}

-(void) showUp
{
	shouldHide = NO;

	[self.animator setAlphaValue:CONTROLALPHA];

	if ([dispView isInFullScreenMode]) {
		// also show the mouse in fullscreen mode
		[NSCursor unhide];
	} else {
		// if not fullscreen mode, show the resizeindicator
		// leave it alone in fullscreen
		[rzIndicator.animator setAlphaValue:CONTROLALPHA];

		if (![ud boolForKey:kUDKeyHideTitlebar]) {
			// if kUDKeyHideTitlebar is OFF, go to display the titlebar
			[title.animator setAlphaValue:CONTROLALPHA];
		}
	}
}

////////////////////////////////////////////////Actions//////////////////////////////////////////////////
-(IBAction) togglePlayPause:(id)sender
{
	[playerController togglePlayPause];

	NSString *osdStr;

	switch (playerController.playerState) {
		case kMPCStoppedState:
			// stopped state
			[self playBackStopped:nil];
			osdStr = kMPXStringOSDPlaybackStopped;
			break;
		case kMPCPausedState:
			// paused state
			[dispView setPlayerWindowLevel];
			[playPauseButton setState:PauseState];
			osdStr = kMPXStringOSDPlaybackPaused;
			break;
		case kMPCPlayingState:
			// playing state
			[dispView setPlayerWindowLevel];
			[playPauseButton setState:PlayState];
			osdStr = kMPXStringOSDNull;
			break;
		default:
			osdStr = kMPXStringOSDNull;
			break;
	}
	[osd setStringValue:osdStr owner:kOSDOwnerOther updateTimer:YES];
}

-(IBAction) toggleMute:(id)sender
{
	BOOL mute = [playerController toggleMute];

	// set buttons and menu status
	[volumeButton setState:(mute)?NSOnState:NSOffState];
	[volumeSlider setEnabled:!mute];
	[menuVolInc setEnabled:!mute];
	[menuVolDec setEnabled:!mute];
	
	// update OSD
	[osd setStringValue:(mute)?(kMPXStringOSDMuteON):(kMPXStringOSDMuteOFF)
				  owner:kOSDOwnerOther
			updateTimer:YES];
}

-(IBAction) setVolume:(id)sender
{
	if ([volumeSlider isEnabled]) {
		// floatValue must be obtained from sender here, not directly from volumeSlider
		// because it could be a keyboard shortcut, in which case ShortCutManager sends an NSNumber as the sender
		float vol = [playerController setVolume:[sender floatValue]];

		// update buttons status
		[volumeSlider setFloatValue: vol];
		
		double max = [volumeSlider maxValue];
		int now = (int)((vol*NUMOFVOLUMEIMAGES + max -1)/max);
		[volumeButton setImage: [volumeButtonImages objectAtIndex: now]];
		
		// store the volume in UserDefaults
		[ud setFloat:vol forKey:kUDKeyVolume];
		
		// update OSD
		[osd setStringValue:[NSString stringWithFormat:kMPXStringOSDVolumeHint, vol]
					  owner:kOSDOwnerOther
				updateTimer:YES];
	}
}

-(IBAction) changeVolumeBy:(id)sender
{
	float delta = ([sender isKindOfClass:[NSMenuItem class]])?([sender tag]):([sender floatValue]);
	
	[self setVolume:[NSNumber numberWithFloat:[volumeSlider floatValue] + (delta * volStep)]];
}

-(IBAction) seekTo:(id) sender
{
	if ([sender isKindOfClass:[NSMenuItem class]]) {
		// action from menu
		sender = [NSNumber numberWithFloat:MAX(0, (((float)[sender tag]) / LASTSTOPPEDTIMERATIO) - 5)];
	}
	
	// when dragging, use absolute seeking
	float time = [playerController seekTo:[sender floatValue]
									 mode:([(TimeSliderCell*)[timeSlider cell] isDragging])?kMPCSeekModeAbsolute:kMPCSeekModeRelative];

	[self updateHintTime];
	
	if ([osd isActive] && (time > 0)) {
		NSString *osdStr = [timeFormatter stringForObjectValue:[NSNumber numberWithFloat:time]];
		double length = [timeSlider maxValue];
		
		if (length > 0) {
			osdStr = [osdStr stringByAppendingFormat:kStringFMTTimeAppendTotal, [timeFormatter stringForObjectValue:[NSNumber numberWithDouble:length]]];
		}
		[osd setStringValue:osdStr owner:kOSDOwnerTime updateTimer:YES];
	}
}

-(void) changeTimeBy:(float) delta
{
	delta = [playerController changeTimeBy:delta];

	if ([osd isActive] && (delta > 0)) {
		NSString *osdStr = [timeFormatter stringForObjectValue:[NSNumber numberWithFloat:delta]];
		double length = [timeSlider maxValue];
		
		if (length > 0) {
			osdStr = [osdStr stringByAppendingFormat:kStringFMTTimeAppendTotal, [timeFormatter stringForObjectValue:[NSNumber numberWithDouble:length]]];
		}
		[osd setStringValue:osdStr owner:kOSDOwnerTime updateTimer:YES];
	}
}

-(IBAction) toggleFullScreen:(id)sender
{
	if ([dispView toggleFullScreen]) {
		// succeeded
		if ([dispView isInFullScreenMode]) {
			// entering fullscreen
			
			[fullScreenButton setState: NSOnState];
			[menuToggleFullScreen setTitle:kMPXStringMenuExitFullscrn];

			// setting fillScreenButton's Image and the like,
			// is implemented in RootLayerView, because setting this needs quite a few parameters
			// which would make the interface look ugly
			[fillScreenButton setHidden: NO];
			[menuToggleFillScreen setEnabled:YES];
			
			// if self has already been hidden, then hide the mouse too
			if ([self alphaValue] < (CONTROLALPHA-0.05)) {
				[NSCursor hide];
			}
			
			// entering fullscreen, force-hide the resizeindicator
			[rzIndicator setAlphaValue:0];
			// this should check kUDKeyHideTitlebar, but since we are hiding the title here anyway
			// setting AlphaValue to 0 multiple times will not cause any harm
			[title setAlphaValue:0];
			
			[menuToggleLockAspectRatio setTitle:([dispView lockAspectRatio])?(kMPXStringMenuUnlockAspectRatio):(kMPXStringMenuLockAspectRatio)];
			[menuToggleLockAspectRatio setEnabled:NO];
			
			[menuEnlargeFrame setEnabled:YES];
			[menuShrinkFrame setEnabled:YES];
			[menuEnlargeFrame2 setEnabled:YES];
			[menuShrinkFrame2 setEnabled:YES];
			[menuWndFitToScrn setEnabled:NO];
			
			if ([ud boolForKey:kUDKeyLBAutoHeightInFullScrn]) {
				NSInteger lb = [ud integerForKey:kUDKeyLetterBoxMode];
				float height = [ud floatForKey:kUDKeyLetterBoxHeight];
				
				NSSize scrnSize = [[[dispView window] screen] frame].size;
				float margin;
				
				switch (lb) {
					case kPMLetterBoxModeBoth:
						margin = ((scrnSize.height * (1 + height * 2) * [dispView aspectRatio] / scrnSize.width) - 1) / 2;
						// MPLog(@"SRN:%f,%f, AR:%f, MH:%f, MRG:%f", scrnSize.width, scrnSize.height, [dispView aspectRatio], [dispView displaySize].height, margin);
						MPLog(@"AutoLBH, AR:%f, margin:%f", [dispView aspectRatio], margin);
						if (margin > 0) {
							[playerController setLetterBox:YES top:margin bottom:margin];
							// [playerController changeTimeBy:0.01f];
						}
						break;
					case kPMLetterBoxModeBottomOnly:
						margin = ((scrnSize.height * (1 + height) * [dispView aspectRatio] / scrnSize.width) - 1);
						// NSLog(@"SRN:%f,%f, AR:%f, MH:%f, MRG:%f", scrnSize.width, scrnSize.height, [dispView aspectRatio], [dispView displaySize].height, margin);
						MPLog(@"AutoLBH, AR:%f, margin:%f", [dispView aspectRatio], margin);
						if (margin > 0) {
							[playerController setLetterBox:YES top:-1.0f bottom:margin];
							// [playerController changeTimeBy:0.01f];
						}
						break;
					case kPMLetterBoxModeTopOnly:
						margin = ((scrnSize.height * (1 + height) * [dispView aspectRatio] / scrnSize.width) - 1);
						// NSLog(@"SRN:%f,%f, AR:%f, MH:%f, MRG:%f", scrnSize.width, scrnSize.height, [dispView aspectRatio], [dispView displaySize].height, margin);
						MPLog(@"AutoLBH, AR:%f, margin:%f", [dispView aspectRatio], margin);
						if (margin > 0) {
							[playerController setLetterBox:YES top:margin bottom:-1.0f];
							// [playerController changeTimeBy:0.01f];
						}
						break;
					default:		
						margin = ((scrnSize.height * [dispView aspectRatio] / scrnSize.width) - 1);
						// NSLog(@"SRN:%f,%f, AR:%f, MH:%f, MRG:%f", scrnSize.width, scrnSize.height, [dispView aspectRatio], [dispView displaySize].height, margin);
						MPLog(@"AutoLBH, AR:%f, margin:%f", [dispView aspectRatio], margin);
						if (margin > 0) {
							NSInteger lbAlt = [ud integerForKey:kUDKeyLetterBoxModeAlt];
							
							switch (lbAlt) {
								case kPMLetterBoxModeBoth:
									margin /= 2;
									[playerController setLetterBox:YES top:margin bottom:margin];
									// [playerController changeTimeBy:0.01f];
									break;
								case kPMLetterBoxModeBottomOnly:
									[playerController setLetterBox:YES top:-1.0f bottom:margin];
									// [playerController changeTimeBy:0.01f];
									break;
								case kPMLetterBoxModeTopOnly:
									[playerController setLetterBox:YES top:margin bottom:-1.0f];
									// [playerController changeTimeBy:0.01f];
									break;
								default:
									break;
							}
						}
						break;						
				}
			}
			
			if ([ud boolForKey:kUDKeyPlayWhenEnterFullScrn] && ([playerController playerState] == kMPCPausedState)) {
				[self togglePlayPause:nil];
			}
		} else {
			// exiting fullscreen
			[NSCursor unhide];

			[fullScreenButton setState:NSOffState];
			[menuToggleFullScreen setTitle:kMPXStringMenuEnterFullscrn];

			[fillScreenButton setHidden: YES];
			[menuToggleFillScreen setEnabled:NO];
			
			if ([self alphaValue] > (CONTROLALPHA-0.05)) {
				// if controlUI is not hidden, show the resizeindicator
				[rzIndicator.animator setAlphaValue:CONTROLALPHA];

				if (![ud boolForKey:kUDKeyHideTitlebar]) {
					// if kUDKeyHideTitlebar is OFF, go to display the titlebar
					[title.animator setAlphaValue:CONTROLALPHA];
				}
			}
			[menuToggleLockAspectRatio setEnabled:YES];
			
			[menuEnlargeFrame setEnabled:NO];
			[menuShrinkFrame setEnabled:NO];
			[menuEnlargeFrame2 setEnabled:NO];
			[menuShrinkFrame2 setEnabled:NO];
			[menuWndFitToScrn setEnabled:YES];
			
			if ([ud boolForKey:kUDKeyLBAutoHeightInFullScrn]) {
				[self toggleLetterBox:nil];
			}
		}
	} else {
		// failed
		[fullScreenButton setState: NSOffState];
		[menuToggleFullScreen setTitle:kMPXStringMenuEnterFullscrn];
		
		[fillScreenButton setHidden: YES];
		[menuToggleFillScreen setEnabled:NO];
		
		[menuToggleLockAspectRatio setEnabled:NO];
		
		[menuEnlargeFrame setEnabled:NO];
		[menuShrinkFrame setEnabled:NO];
		[menuEnlargeFrame2 setEnabled:NO];
		[menuShrinkFrame2 setEnabled:NO];
		[menuWndFitToScrn setEnabled:NO];
	}
	[self windowHasResized:nil];
}

-(IBAction) toggleFillScreen:(id)sender
{
	if (sender || ([fillScreenButton state] == NSOnState)) {
		// if sender is nil
		// that means it is an internal reset signal, and whether to trigger toggle is decided by the button's state
		BOOL status = [dispView toggleFillScreen];
		if (status) {
			[fillScreenButton setState:NSOnState];
			[menuToggleFillScreen setState:NSOnState];
		} else {
			[fillScreenButton setState:NSOffState];
			[menuToggleFillScreen setState:NSOffState];
		}
	}
}

-(IBAction) toggleAccessaryControls:(id)sender
{
	NSRect rcSelf = [self frame];
	CGFloat delta = accessaryContainer.frame.size.height -10;
	NSRect rcAcc = [accessaryContainer frame];

	if ([sender tag] == NO) {
		// to show
		rcSelf.size.height = orgHeight + delta;
		rcSelf.origin.y -= MIN(rcSelf.origin.y, delta);
		
		[self.animator setFrame:rcSelf];
		
		rcAcc.origin.y = 0;
		rcAcc.origin.x = (rcSelf.size.width - rcAcc.size.width) / 2;
		[accessaryContainer setFrameOrigin:rcAcc.origin];
		
		[accessaryContainer.animator setHidden: NO];
		
		[menuToggleAuxiliaryCtrls setTitle:kMPXStringMenuHideAuxCtrls];
		[menuToggleAuxiliaryCtrls setTag:YES];
		[toggleAcceButton setState:NSOnState];
		[toggleAcceButton setTag:YES];
		
	} else {
		[accessaryContainer.animator setHidden: YES];

		rcSelf.size.height = orgHeight;
		rcSelf.origin.y += delta;
		
		[self.animator setFrame:rcSelf];
		
		rcAcc.origin.y = 0;
		rcAcc.origin.x = (rcSelf.size.width - rcAcc.size.width) / 2;
		[accessaryContainer setFrameOrigin:rcAcc.origin];
		
		[menuToggleAuxiliaryCtrls setTitle:kMPXStringMenuShowAuxCtrls];
		[menuToggleAuxiliaryCtrls setTag:NO];
		[toggleAcceButton setState:NSOffState];
		[toggleAcceButton setTag:NO];
	}
	[hintTime.animator setAlphaValue:0];
}

-(IBAction) changeSpeed:(id) sender
{
	if ([sender isKindOfClass:[NSMenuItem class]]) {
		// from changespeed menu
		if ([sender tag]) {
			// if not zero, means not reset
			[playerController changeSpeedBy:[sender tag] * [ud floatForKey:kUDKeySpeedStep]];
		} else {
			// if zero, reset
			[playerController setSpeed:1];
		}
	} else {
		// from textfield
		[playerController setSpeed:[sender floatValue]];
	}
}

-(IBAction) changeAudioDelay:(id) sender
{
	if ([sender isKindOfClass:[NSMenuItem class]]) {
		if ([sender tag]) {
			[playerController changeAudioDelayBy:[sender tag] * [ud floatForKey:kUDKeyAudioDelayStepTime]];
		} else {
			[playerController setAudioDelay:0];
		}
	} else {
		[playerController setAudioDelay:[sender floatValue]];	
	}
}

-(IBAction) changeSubDelay:(id)sender
{
	if ([sender isKindOfClass:[NSMenuItem class]]) {
		if ([sender tag]) {
			[playerController changeSubDelayBy:[sender tag] * [ud floatForKey:kUDKeySubDelayStepTime]];
		} else {
			[playerController setSubDelay:0];
		}
	} else {
		[playerController setSubDelay:[sender floatValue]];
	}
}

-(IBAction) changeSubScale:(id)sender
{
	[playerController changeSubScaleBy:[sender tag] * [ud floatForKey:kUDKeySubScaleStepValue]];
}

-(IBAction) stepSubtitles:(id)sender
{
	int selectedTag = -2;
	NSMenuItem* mItem;
	
	// find the currently selected subtitle
	for (mItem in [subListMenu itemArray]) {
		if (([mItem state] == NSOnState) && (![mItem isSeparatorItem])) {
			selectedTag = [mItem tag];
			break;
		}
	}
	// get the next subtitle's tag
	// if no menu item is selected, then select "hide subtitles"
	selectedTag++;
	
	if (!(mItem = [subListMenu itemWithTag:selectedTag])) {
		// if it is the last subtitle item, then wrap around to the "hide subtitles" menu item
		mItem = [subListMenu itemWithTag:-1];
	}
	[self setSubWithID:mItem];
}

-(IBAction) setSubWithID:(id)sender
{
	if (sender) {
		[playerController setSubtitle:[sender tag]];
		
		for (NSMenuItem* mItem in [subListMenu itemArray]) {
			if (([mItem state] == NSOnState) && (![mItem isSeparatorItem])) {
				[mItem setState:NSOffState];
				break;
			}
		}
		[sender setState:NSOnState];
		
		[osd setStringValue:[NSString stringWithFormat:kMPXStringOSDSubtitleHint, [sender title]]
					  owner:kOSDOwnerOther
				updateTimer:YES];
	}
}

-(IBAction) stepAudios:(id)sender
{
	NSUInteger num = [audioListMenu numberOfItems];
	
	if (num) {
		NSUInteger idx = 0, found = 0;
		NSMenuItem* mItem;
		
		for (mItem in [audioListMenu itemArray]) {
			if ([mItem state] == NSOnState) {
				found = idx+1;
				break;
			}
			idx++;
		}
		if (found >= num) {
			found = 0;
		}
		[self setAudioWithID:[audioListMenu itemAtIndex:found]];
	}
}

-(IBAction) setAudioWithID:(id)sender
{
	if (sender) {
		[playerController setAudio:[sender tag]];
		
		// This is a hack
		// since I have to reset the volume when switch audio
		// so I should disable OSD when set volume
		BOOL oldAct = [osd isActive];
		[osd setActive:NO];
		// this might be an mplayer bug -- when cycling all the way around through the audio tracks to silent and back to a track, the volume jumps to max, so set the volume again here
		[self setVolume:volumeSlider];
		[osd setActive:oldAct];
		
		for (NSMenuItem* mItem in [audioListMenu itemArray]) {
			if ([mItem state] == NSOnState) {
				[mItem setState:NSOffState];
				break;
			}
		}
		[sender setState:NSOnState];
		
		[osd setStringValue:[NSString stringWithFormat:kMPXStringOSDAudioHint, [sender title]]
					  owner:kOSDOwnerOther
				updateTimer:YES];
	}
}

-(IBAction) stepVideos:(id)sender
{
	NSUInteger num = [videoListMenu numberOfItems];
	
	if (num) {
		NSUInteger idx = 0, found = 0;
		NSMenuItem* mItem;

		for (mItem in [videoListMenu itemArray]) {
			if ([mItem state] == NSOnState) {
				found = idx+1;
				break;
			}
			idx++;
		}
		if (found >= num) {
			found = 0;
		}
		[self setVideoWithID:[videoListMenu itemAtIndex:found]];
	}
}

-(IBAction) setVideoWithID:(id)sender
{
	if (sender) {
		[playerController setVideo:[sender tag]];
		
		for (NSMenuItem* mItem in [videoListMenu itemArray]) {
			if ([mItem state] == NSOnState) {
				[mItem setState:NSOffState];
				break;
			}
		}
		[sender setState:NSOnState];
		
		[osd setStringValue:[NSString stringWithFormat:kMPXStringOSDVideoHint, [sender title]]
					  owner:kOSDOwnerOther
				updateTimer:YES];
	}
}

-(IBAction) setChapterWithTime:(id)sender
{
	if (sender) {
		[playerController seekTo:[sender tag] / kMPCChapterTimeBase mode:kMPCSeekModeRelative];
		
		[self updateHintTime];
		
		[osd setStringValue:[NSString stringWithFormat:kMPXStringOSDChapterHint, [sender representedObject]]
					  owner:kOSDOwnerOther
				updateTimer:YES];
	}
}

-(IBAction) changeSubPosBy:(id)sender
{
	if (sender) {
		if ([sender isKindOfClass:[NSNumber class]]) {
			// if it is an NSNumber, that means it did not come from Target-Action
			[playerController changeSubPosBy:[sender floatValue]];
		}
	}
}

-(IBAction) changeAudioBalanceBy:(id)sender
{
	if (sender) {
		if ([sender isKindOfClass:[NSNumber class]]) {
			// if it is an NSNumber, that means it did not come from Target-Action
			[playerController changeAudioBalanceBy:[sender floatValue]];
		}
	} else {
		// nil means the intent is to restore
		[playerController setAudioBalance:0];
	}
}

-(IBAction) toggleLockAspectRatio:(id)sender
{
	[dispView setLockAspectRatio:(![dispView lockAspectRatio])];

	BOOL lock = [dispView lockAspectRatio];
	[menuToggleLockAspectRatio setTitle:(lock)?(kMPXStringMenuUnlockAspectRatio):(kMPXStringMenuLockAspectRatio)];
	
	[osd setStringValue:(lock)?(kMPXStringOSDAspectRatioLocked):(kMPXStringOSDAspectRatioUnLocked)
				  owner:kOSDOwnerOther
			updateTimer:YES];
}

-(IBAction) resetAspectRatio:(id)sender
{
	[dispView resetAspectRatio];
	[menuToggleLockAspectRatio setTitle:([dispView lockAspectRatio])?(kMPXStringMenuUnlockAspectRatio):(kMPXStringMenuLockAspectRatio)];
	
	[osd setStringValue:kMPXStringOSDAspectRatioReset
				  owner:kOSDOwnerOther
			updateTimer:YES];
}

-(IBAction) setAspectRatio:(id)sender
{
	[dispView setAspectRatio:((CGFloat)[sender tag]) / ASPECTRATIOBASE];
}

-(IBAction) toggleLetterBox:(id)sender
{
	NSInteger lbMode = [ud integerForKey:kUDKeyLetterBoxMode];

	if (sender) {
		// means the event was triggered from the menu
		// if it is nil, it means the event was triggered internally, so just update the menu state
		if (lbMode == kPMLetterBoxModeNotDisplay) {
			// not currently showing
			lbMode = [ud integerForKey:kUDKeyLetterBoxModeAlt];
			[ud setInteger:lbMode forKey:kUDKeyLetterBoxMode];
		} else {
			// currently showing
			lbMode = kPMLetterBoxModeNotDisplay;
			[ud setInteger:lbMode forKey:kUDKeyLetterBoxMode];
		}
	}

	// not in the fullscreen mode
	float margin = [ud floatForKey:kUDKeyLetterBoxHeight];

	switch (lbMode) {
		case kPMLetterBoxModeBoth:
			[menuToggleLetterBox setTitle:kMPXStringMenuHideLetterBox];
			[playerController setLetterBox:YES top:margin bottom:margin];
			break;
		case kPMLetterBoxModeBottomOnly:
			[menuToggleLetterBox setTitle:kMPXStringMenuHideLetterBox];
			[playerController setLetterBox:YES top:-1.0f bottom:margin];
			break;
		case kPMLetterBoxModeTopOnly:
			[menuToggleLetterBox setTitle:kMPXStringMenuHideLetterBox];
			[playerController setLetterBox:YES top:margin bottom:-1.0f];
			break;
		default:
			[menuToggleLetterBox setTitle:kMPXStringMenuShowLetterBox];
			[playerController setLetterBox:NO top:-1.0f bottom:-1.0f];
			break;
	}
	// [playerController changeTimeBy:0.01f];
}

-(IBAction) stepWindowSize:(id)sender
{
	if ([sender isKindOfClass:[NSMenuItem class]]) {
		float step = [sender tag] * [ud floatForKey:kUDKeyResizeStep];
		
		[dispView changeWindowSizeBy:NSMakeSize(step, step) animate:YES];
	}
}

-(IBAction) moveFrameToCenter:(id)sender
{
	[dispView moveFrameToCenter];
}

-(IBAction) resetFrameScaleRatio:(id)sender
{
	[dispView resetFrameScaleRatio];
}

-(IBAction) stepFrameScale:(id)sender
{
	CGSize rt;
	rt.width = [sender tag] * [ud floatForKey:kUDKeyFrameScaleStep];
	rt.height = rt.width;
	
	[dispView changeFrameScaleRatioBy:rt];
}

-(IBAction) toggleMirror:(id)sender
{
	[dispView setMirror:![dispView mirror]];
	
	[menuMirror setState:([dispView mirror])?(NSOnState):(NSOffState)];
}

-(IBAction) toggleFlip:(id)sender
{
	[dispView setFlip:![dispView flip]];
	
	[menuFlip setState:([dispView flip])?(NSOnState):(NSOffState)];
}

-(IBAction) zoomToSize:(id)sender
{
	[dispView zoomToSize:((float)[sender tag]) / 4];
}

-(IBAction) toggleTimeAltDisplayMode:(id)sender
{
	[ud setBool:![ud boolForKey:kUDKeyTimeTextAltTotal] forKey:kUDKeyTimeTextAltTotal];
}

-(IBAction) mapAudioChannelsTo:(id)sender
{
	[playerController mapAudioChannelsTo:[sender tag]];
	
	for (NSMenuItem *mitem in [[menuAudioChannels submenu] itemArray]) {
		if (([mitem state] == NSOnState) && (![mitem isSeparatorItem])) {
			[mitem setState:NSOffState];
			break;
		}
	}
	[sender setState:NSOnState];
}
////////////////////////////////////////////////FullscreenThings//////////////////////////////////////////////////
-(void) setFillScreenMode:(NSString*)modeKey state:(NSInteger) state
{
	NSArray *fillScrnBtnModeImages = [fillScreenButtonAllImages objectForKey:modeKey];
	
	if (fillScrnBtnModeImages) {
		[fillScreenButton setImage:[fillScrnBtnModeImages objectAtIndex:0]];
		[fillScreenButton setAlternateImage:[fillScrnBtnModeImages objectAtIndex:1]];
	}
	[fillScreenButton setState:state];
}

////////////////////////////////////////////////displayThings//////////////////////////////////////////////////
-(void) displayStarted
{
	[fullScreenButton setHidden: NO];

	[menuToggleFullScreen setEnabled:YES];
	[menuSnapshot setEnabled:YES];
	if (![dispView isInFullScreenMode]) {
		[menuToggleLockAspectRatio setEnabled:YES];
		[menuWndFitToScrn setEnabled:YES];
	}
	[menuToggleLockAspectRatio setTitle:([dispView lockAspectRatio])?(kMPXStringMenuUnlockAspectRatio):(kMPXStringMenuLockAspectRatio)];
	[menuZoomToHalfSize setEnabled:YES];
	[menuZoomToOriginSize setEnabled:YES];
	[menuZoomToDoubleSize setEnabled:YES];
}

-(void) displayStopped
{
	[fullScreenButton setHidden: YES];
	
	[menuToggleFullScreen setEnabled:NO];
	[menuSnapshot setEnabled:NO];
	[menuToggleLockAspectRatio setEnabled:NO];
	[menuZoomToHalfSize setEnabled:NO];
	[menuZoomToOriginSize setEnabled:NO];
	[menuZoomToDoubleSize setEnabled:NO];
	[menuWndFitToScrn setEnabled:NO];
}

////////////////////////////////////////////////playback//////////////////////////////////////////////////
-(void) playBackOpened:(NSNotification*)notif
{
	[osd setActive:[ud boolForKey:kUDKeyShowOSD]];

	NSNumber *stopTime = [[notif userInfo] objectForKey:kMPCPlayLastStoppedTimeKey];
	if (stopTime) {
		[menuPlayFromLastStoppedPlace setTag: ([stopTime integerValue] * LASTSTOPPEDTIMERATIO)];
		[menuPlayFromLastStoppedPlace setEnabled:YES];
	} else {
		[menuPlayFromLastStoppedPlace setEnabled:NO];		
	}
}

-(void) playBackStarted:(NSNotification*)notif
{
	[playPauseButton setState:(playerController.playerState == kMPCPlayingState)?PlayState:PauseState];

	[speedText setEnabled:YES];
	[audioDelayText setEnabled:YES];
	
	[menuSwitchAudio setEnabled:YES];
	[menuSwitchVideo setEnabled:YES];
	
	[menuToggleAuxiliaryCtrls setEnabled:YES];
	
	[menuSpeedUp setEnabled:YES];
	[menuSpeedDown setEnabled:YES];
	[menuAudioDelayInc setEnabled:YES];
	[menuAudioDelayDec setEnabled:YES];
	
	if ([playerController isPassingThrough]) {
		[volumeButton setEnabled:NO];
		[volumeSlider setEnabled:NO];
		[menuVolInc setEnabled:NO];
		[menuVolDec setEnabled:NO];		
	} else {
		[menuAudioChannels setEnabled:YES];
		for (NSMenuItem *mitem in [[menuAudioChannels submenu] itemArray]) {
			if ([mitem tag] == kMPCMonoAudioNone) {
				[mitem setState:NSOnState];
			} else {
				[mitem setState:NSOffState];
			}
		}
		// if it is a DD setting, ParameterManager will not set the volume.
		// but if the file ends up not playing as DD, the volume needs to be set again
		// and do not show the OSD
		BOOL oldAct = [osd isActive];
		[osd setActive:NO];
		// this might be an mplayer bug -- when cycling all the way around through the audio tracks to silent and back to a track, the volume jumps to max, so set the volume again here
		[self setVolume:volumeSlider];
		[osd setActive:oldAct];
	}
	
	[self showUp];
}

-(void) playBackWillStop:(NSNotification*)notif
{
	[osd setStringValue:@"" owner:kOSDOwnerOther updateTimer:YES];
	[osd setActive:NO];
}

/** this API is called at two points in time,
 * 1. when mplayer playback ends, whether forced or natural
 * 2. when mplayer playback fails */
-(void) playBackStopped:(NSNotification*)notif
{
	[playPauseButton setState:PauseState];

	[timeText setStringValue:@""];
	[timeTextAlt setStringValue:@""];
	[timeSlider setFloatValue:-1];
	
	// since mplayer cannot start muted, we must always return to the unmuted state
	[volumeButton setState:NSOffState];
	[volumeButton setEnabled:YES];
	[volumeSlider setEnabled:YES];
	[menuVolInc setEnabled:YES];
	[menuVolDec setEnabled:YES];

	[speedText setEnabled:NO];
	[subDelayText setEnabled:NO];
	[audioDelayText setEnabled:NO];
	
	[menuSwitchAudio setEnabled:NO];
	[menuSwitchSub setEnabled:NO];
	[menuSwitchVideo setEnabled:NO];
	
	[menuSubScaleInc setEnabled:NO];
	[menuSubScaleDec setEnabled:NO];
	[menuPlayFromLastStoppedPlace setEnabled:NO];
	
	[menuSpeedUp setEnabled:NO];
	[menuSpeedDown setEnabled:NO];
	[menuAudioDelayInc setEnabled:NO];
	[menuAudioDelayDec setEnabled:NO];
	[menuSubDelayInc setEnabled:NO];
	[menuSubDelayDec setEnabled:NO];
	
	[menuAudioChannels setEnabled:NO];
}

-(void) playInfoUpdated:(NSNotification*)notif
{
	NSString *keyPath = [[notif userInfo] objectForKey:kMPCPlayInfoUpdatedKeyPathKey];
	NSDictionary *change = [[notif userInfo] objectForKey:kMPCPlayInfoUpdatedChangeDictKey];

	if ([keyPath isEqualToString:kKVOPropertyKeyPathCurrentTime]) {
		// get the current playback time
		[self gotCurentTime:[change objectForKey:NSKeyValueChangeNewKey]];
		
	} else if ([keyPath isEqualToString:kKVOPropertyKeyPathSpeed]) {
		// get the playback speed
		[self gotSpeed:[change objectForKey:NSKeyValueChangeNewKey]];
		
	} else if ([keyPath isEqualToString:kKVOPropertyKeyPathSubDelay]) {
		// get the subtitle delay
		[self gotSubDelay:[change objectForKey:NSKeyValueChangeNewKey]];
		
	} else if ([keyPath isEqualToString:kKVOPropertyKeyPathAudioDelay]) {
		// get the audio delay
		[self gotAudioDelay:[change objectForKey:NSKeyValueChangeNewKey]];
		
	} else if ([keyPath isEqualToString:kKVOPropertyKeyPathLength]){
		// get the media file's length
		[self gotMediaLength:[change objectForKey:NSKeyValueChangeNewKey]];
		
	} else if ([keyPath isEqualToString:kKVOPropertyKeyPathSeekable]) {
		// get whether seeking is possible
		[self gotSeekableState:[change objectForKey:NSKeyValueChangeNewKey]];
		
	} else if ([keyPath isEqualToString:kKVOPropertyKeyPathCachingPercent]) {
		// get the current caching percent
		[self gotCachingPercent:[change objectForKey:NSKeyValueChangeNewKey]];
		
	} else if ([keyPath isEqualToString:kKVOPropertyKeyPathSubInfo]) {
		// get the subtitle info
		[self gotSubInfo:[change objectForKey:NSKeyValueChangeNewKey]
					  changed:[[change objectForKey:NSKeyValueChangeKindKey] intValue]];
	
	} else if ([keyPath isEqualToString:kKVOPropertyKeyPathAudioInfo]) {
		// get the audio info
		[self gotAudioInfo:[change objectForKey:NSKeyValueChangeNewKey]];
		
	} else if ([keyPath isEqualToString:kKVOPropertyKeyPathVideoInfo]) {
		// got the video info
		[self gotVideoInfo:[change objectForKey:NSKeyValueChangeNewKey]];
		
	} else if ([keyPath isEqualToString:kKVOPropertyKeyPathChapterInfo]) {
		// got chapter info
		[self gotChapterInfo:[change objectForKey:NSKeyValueChangeNewKey]];
	}
}
////////////////////////////////////////////////KVO for time//////////////////////////////////////////////////
-(void) gotMediaLength:(NSNumber*) length
{
	float len = [length floatValue];
	
	if (len > 0) {
		[timeSlider setMaxValue:len];
		[timeSlider setMinValue:0];
		if ([ud boolForKey:kUDKeyTimeTextAltTotal]) {
			// diplay total time
			[timeTextAlt setIntValue:len + 0.5]; 
		} else {
			// display remain time
			[timeTextAlt setIntValue:-len-0.5];
		}
	} else {
		[timeSlider setEnabled:NO];
		[timeSlider setMaxValue:0];
		[timeSlider setMinValue:-1];
		[hintTime.animator setAlphaValue:0];
	}
}

-(void) gotCurentTime:(NSNumber*) timePos
{
	float time = [timePos floatValue];
	double length = [timeSlider maxValue];

	if (length > 0) {
		if ([ud boolForKey:kUDKeyTimeTextAltTotal]) {
			[timeTextAlt setIntValue:length + 0.5];
		} else {
			// display remaining time
			[timeTextAlt setIntValue:time - length - 0.5];
		}
	}

	[timeText setIntValue:time + 0.5];
	// the time can still be displayed even if timeSlider is disabled
	[timeSlider setFloatValue:time];
	
	if (length > 0) {
		[self calculateHintTime];
	}
	
	if ([osd isActive] && (time > 0)) {
		NSString *osdStr = [timeFormatter stringForObjectValue:timePos];
		
		if (length > 0) {
			osdStr = [osdStr stringByAppendingFormat:kStringFMTTimeAppendTotal, [timeFormatter stringForObjectValue:[NSNumber numberWithDouble:length]]];
		}
		[osd setStringValue:osdStr owner:kOSDOwnerTime updateTimer:NO];		
	}
}

-(void) gotSeekableState:(NSNumber*) seekable
{
	[timeSlider setEnabled:[seekable boolValue]];
}

-(void) gotSpeed:(NSNumber*) speed
{
	[speedText setFloatValue:[speed floatValue]];
	
	[osd setStringValue:[NSString stringWithFormat:kMPXStringOSDSpeedHint, [speed floatValue]] 
				  owner:kOSDOwnerOther
			updateTimer:YES];
}

-(void) gotSubDelay:(NSNumber*) sd
{
	[subDelayText setFloatValue:[sd floatValue]];
	
	[osd setStringValue:[NSString stringWithFormat:kMPXStringOSDSubDelayHint, [sd floatValue]]
				  owner:kOSDOwnerOther
			updateTimer:YES];
}

-(void) gotAudioDelay:(NSNumber*) ad
{
	[audioDelayText setFloatValue:[ad floatValue]];

	[osd setStringValue:[NSString stringWithFormat:kMPXStringOSDAudioDelayHint, [ad floatValue]]
				  owner:kOSDOwnerOther
			updateTimer:YES];
}

-(void) resetSubtitleMenu
{
	[subListMenu removeAllItems];
	
	// add a separator
	NSMenuItem *mItem = [NSMenuItem separatorItem];
	[mItem setEnabled:NO];
	[mItem setTag:-2];
	[mItem setState:NSOffState];
	[subListMenu addItem:mItem];
	
	// add the "hide subtitles" menu item
	mItem = [[NSMenuItem alloc] init];
	[mItem setEnabled:YES];
	[mItem setTarget:self];
	[mItem setAction:@selector(setSubWithID:)];
	[mItem setTitle:kMPXStringDisable];
	[mItem setTag:-1];
	[mItem setState:NSOffState];
	[subListMenu addItem:mItem];
	[mItem release];	
}

-(void) gotSubInfo:(NSArray*) subs changed:(int)changeKind
{
	if (changeKind == NSKeyValueChangeSetting) {
		[self resetSubtitleMenu];
	}
	
	if (subs && (subs != (id)[NSNull null]) && [subs count]) {
		
		NSInteger idx = [subListMenu numberOfItems] - 2;
		NSMenuItem *mItem = nil;
		
		// add all subtitle names to the menu
		for(NSString *str in subs) {
			mItem = [[NSMenuItem alloc] init];
			[mItem setEnabled:YES];
			[mItem setTarget:self];
			[mItem setAction:@selector(setSubWithID:)];
			[mItem setTitle:str];
			[mItem setTag:idx];
			[mItem setState:NSOffState];
			[subListMenu insertItem:mItem atIndex:idx];
			[mItem release];
			idx++;
		}
		
		if (changeKind == NSKeyValueChangeSetting) {
			// this place is only called when playback has just started and subs are loading, so it is safe
			// this branch is not entered when subs are cleared
			[[subListMenu itemWithTag:[[[[playerController mediaInfo] playingInfo] currentSubID] integerValue]]
			 setState:NSOnState];
		} else {
			// this is called here when a sub is loaded midway through
			// activate this loaded sub by default
			[self setSubWithID:mItem];
			
			// this is a workaround, because if a subtitle is loaded while paused
			// since it cannot be loaded while staying paused, playback will start automatically
			// this would cause mplayer's state and MPX's state to become inconsistent; here we check MPX's state, and if it was loaded while paused, toggle it
			// the underlying command issued is pause -1, which has no side effect while playing -- it just resets MPX's state.
			if ([playerController playerState] == kMPCPausedState) {
				[self togglePlayPause:nil];
			}
		}

		[menuSwitchSub setEnabled:YES];
		[menuSubScaleInc setEnabled:YES];
		[menuSubScaleDec setEnabled:YES];
		[menuSubDelayInc setEnabled:YES];
		[menuSubDelayDec setEnabled:YES];

		[subDelayText setEnabled:YES];
		
	} else if (changeKind == NSKeyValueChangeSetting) {
		[menuSwitchSub setEnabled:NO];
		[menuSubScaleInc setEnabled:NO];
		[menuSubScaleDec setEnabled:NO];
		[menuSubDelayInc setEnabled:NO];
		[menuSubDelayDec setEnabled:NO];
	
		[subDelayText setEnabled:NO];
	}
}

-(void) gotCachingPercent:(NSNumber*) caching
{
	NSWindow *win = [self window];
	float percent = [caching floatValue];
	
	if ([osd isActive] && (percent > 0.01)) {
		if (![win isVisible]) {
			[win makeKeyAndOrderFront:self];
		}
		
		[osd setStringValue:[NSString stringWithFormat:kMPXStringOSDCachingPercent, percent*100]
					  owner:kOSDOwnerOther
				updateTimer:YES];
	}
}

-(void) resetAudioMenu
{
	[audioListMenu removeAllItems];
}

-(void) gotAudioInfo:(NSArray*) ais
{
	[audioListMenu removeAllItems];

	if (ais && (ais != (id)[NSNull null]) && [ais count]) {
		
		NSMenuItem *mItem = nil;
		
		for (id info in ais) {
			mItem = [[NSMenuItem alloc] init];
			[mItem setEnabled:YES];
			[mItem setTarget:self];
			[mItem setAction:@selector(setAudioWithID:)];
			[mItem setTitle:[info description]];
			[mItem setTag:[info ID]];
			[mItem setState:NSOffState];
			[audioListMenu addItem:mItem];
			[mItem release];
		}
		
		[[audioListMenu itemAtIndex:0] setState:NSOnState];
		
		[menuSwitchAudio setEnabled:YES];
	} else {
		[menuSwitchAudio setEnabled:NO];
	}
}

-(void) resetVideoMenu
{
	[videoListMenu removeAllItems];
}

-(void) gotVideoInfo:(NSArray*) vis
{
	[videoListMenu removeAllItems];
	
	if (vis && (vis != (id)[NSNull null]) && [vis count]) {
		
		NSMenuItem *mItem = nil;
		
		for (id info in vis) {
			mItem = [[NSMenuItem alloc] init];
			[mItem setEnabled:YES];
			[mItem setTarget:self];
			[mItem setAction:@selector(setVideoWithID:)];
			[mItem setTitle:[info description]];
			[mItem setTag:[info ID]];
			[mItem setState:NSOffState];
			[videoListMenu addItem:mItem];
			[mItem release];
		}
		
		[[videoListMenu itemAtIndex:0] setState:NSOnState];
		
		[menuSwitchVideo setEnabled:YES];
	} else {
		[menuSwitchVideo setEnabled:NO];
	}
}

-(void) resetChapterListMenu
{
	[chapterListMenu removeAllItems];
}

-(void) gotChapterInfo:(NSArray*) cis
{
	[chapterListMenu removeAllItems];
	
	if (cis && (cis != (id)[NSNull null]) && [cis count]) {
		
		NSMenuItem *mItem = nil;
		
		for (ChapterItem *info in cis) {
			mItem = [[NSMenuItem alloc] init];
			[mItem setEnabled:YES];
			[mItem setTarget:self];
			[mItem setAction:@selector(setChapterWithTime:)];
			[mItem setTitle:[info description]];
			[mItem setTag:[info start]];
			[mItem setState:NSOffState];
			[mItem setRepresentedObject:[info name]];
			
			[chapterListMenu addItem:mItem];
			[mItem release];
		}
		
		[menuChapterList setEnabled:YES];
	} else {
		[menuChapterList setEnabled:NO];
	}
}

////////////////////////////////////////////////draw myself//////////////////////////////////////////////////
- (void)drawRect:(NSRect)dirtyRect
{
	NSRect rc = [self bounds];
	NSPoint pt;
	
	//////////////////// main background
	NSBezierPath *fillPath = [NSBezierPath bezierPathWithRoundedRect:rc xRadius:CONTROL_CORNER_RADIUS yRadius:CONTROL_CORNER_RADIUS];
	[fillGradient drawInBezierPath:fillPath angle:270];

	//////////////////// top line
	[backGroundColor set];
	NSBezierPath *hilightPath = [NSBezierPath bezierPath];
	 
	pt.x = rc.size.width - CONTROL_CORNER_RADIUS;
	pt.y = rc.size.height;
	[hilightPath moveToPoint:pt];
	
	pt.x = CONTROL_CORNER_RADIUS;
	[hilightPath lineToPoint:pt];

	[hilightPath stroke];
	
	//////////////////// round corner line
	[backGroundColor2 set];
	
	NSBezierPath *roundPath = [NSBezierPath bezierPath];
	pt.x = rc.size.width;
	pt.y = rc.size.height - CONTROL_CORNER_RADIUS;
	[roundPath moveToPoint:pt];
	
	pt.x = rc.size.width - CONTROL_CORNER_RADIUS;
	[roundPath appendBezierPathWithArcWithCenter:pt radius:CONTROL_CORNER_RADIUS
									  startAngle:0 endAngle:90];
	pt.x = CONTROL_CORNER_RADIUS;
	pt.y = rc.size.height;
	[roundPath moveToPoint:pt];

	pt.y = rc.size.height - CONTROL_CORNER_RADIUS;
	[roundPath appendBezierPathWithArcWithCenter:pt radius:CONTROL_CORNER_RADIUS
									  startAngle:90 endAngle:180];
	[roundPath stroke];
}

-(void) calculateHintTime
{
	NSPoint pt = [self convertPoint:[[self window] convertScreenToBase:[NSEvent mouseLocation]] fromView:nil];
	NSRect frm = timeSlider.frame;
	
	float timeDisp = ((pt.x-frm.origin.x) * [timeSlider maxValue])/ frm.size.width;;

	if ((([NSEvent modifierFlags] == kSCMSwitchTimeHintKeyModifierMask)?YES:NO) != 
		[ud boolForKey:kUDKeySwitchTimeHintPressOnAbusolute]) {
		// if Fn is not pressed, show the time difference
		// otherwise show the absolute time
		timeDisp -= [timeSlider floatValue];
	}
	[hintTime setIntValue:timeDisp + ((timeDisp>0)?0.5:-0.5)];
}

-(void) updateHintTime
{
	// get the mouse position within ControlUI
	NSPoint pt = [self convertPoint:[[self window] convertScreenToBase:[NSEvent mouseLocation]] fromView:nil];
	NSRect frm = timeSlider.frame;

	// if the media is not seekable, timeSlider is disabled
	// but if the length of the media is available, we should display the hintTime, whether it is seekable or not
	if (NSPointInRect(pt, frm) && ([timeSlider maxValue] > 0)) {
		// if the mouse is within timeSlider
		// update the time
		[self calculateHintTime];
		
		CGFloat wd = [hintTime bounds].size.width;
		pt.x -= (wd/2);
		pt.x = MIN(pt.x, [self bounds].size.width - wd);
		pt.y = frm.origin.y + frm.size.height - 4;
		
		[hintTime setFrameOrigin:pt];
		
		[hintTime.animator setAlphaValue:1];
	} else {
		[hintTime.animator setAlphaValue:0];
	}
}

- (void)mouseDragged:(NSEvent *)event
{
	NSRect selfFrame = [self frame];
	NSRect contentBound = [[[self window] contentView] bounds];
	
	selfFrame.origin.x += [event deltaX];
	selfFrame.origin.y -= [event deltaY];
	
	selfFrame.origin.x = MAX(contentBound.origin.x, 
							 MIN(selfFrame.origin.x, contentBound.origin.x + contentBound.size.width - selfFrame.size.width));
	selfFrame.origin.y = MAX(contentBound.origin.y, 
							 MIN(selfFrame.origin.y, contentBound.origin.y + contentBound.size.height - selfFrame.size.height));
	
	[self setFrameOrigin:selfFrame.origin];
}

-(void) windowHasResized:(NSNotification *)notification
{
	[hintTime.animator setAlphaValue:0];
	
	// this is to make the font size match the window size
	[osd setStringValue:nil owner:osd.owner updateTimer:NO];
}
@end
