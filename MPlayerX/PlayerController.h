/*
 * MPlayerX - PlayerController.h
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

#import <Cocoa/Cocoa.h>
#import "def.h"
#import "MovieInfo.h"
#import <IOKit/pwr_mgt/IOPMLib.h>

///////////////////////////Notifications///////////////////////////
extern NSString * const kMPCPlayOpenedNotification;
extern NSString * const kMPCPlayOpenedURLKey;
extern NSString * const kMPCPlayLastStoppedTimeKey;
//-----------------------------------------------------------------
extern NSString * const kMPCPlayStartedNotification;
extern NSString * const kMPCPlayStartedAudioOnlyKey;
//-----------------------------------------------------------------
extern NSString * const kMPCPlayWillStopNotification;
extern NSString * const kMPCPlayStoppedNotification;
extern NSString * const kMPCPlayFinalizedNotification;
//-----------------------------------------------------------------
extern NSString * const kMPCPlayInfoUpdatedNotification;
extern NSString * const kMPCPlayInfoUpdatedKeyPathKey;
extern NSString * const kMPCPlayInfoUpdatedChangeDictKey;

@class ControlUIView, OpenURLController, CharsetQueryController, CoreController;

@interface PlayerController : NSObject <SubConverterDelegate, CoreControllerDelegate>
{
	NSUserDefaults *ud;
	NSNotificationCenter *notifCenter;
	
	CoreController *mplayer;
	NSURL *lastPlayedPath;
	NSURL *lastPlayedPathPre;

	BOOL kvoSetuped;
	NSUInteger autoPlayState;
	
	IOPMAssertionID nonSleepHandler;

	IBOutlet ControlUIView *controlUI;
	IBOutlet OpenURLController *openUrlController;
	IBOutlet CharsetQueryController *charsetController;
}

@property (readonly) NSURL *lastPlayedPath;

-(void) setupKVO;

-(id) setDisplayDelegateForMPlayer:(id<CoreDisplayDelegate>) delegate;
-(int) playerState;
-(BOOL) couldAcceptCommand;
-(void) setPlayDisk:(NSInteger)pd;

-(MovieInfo*) mediaInfo;
-(void) setMultiThreadMode:(BOOL) mt;

-(void) loadFiles:(NSArray*)files fromLocal:(BOOL)local;
-(void) stop;

-(void) togglePlayPause;	/** returns whether PlayPause succeeded */
-(BOOL) toggleMute;			/** returns the current mute state */
-(float) setVolume:(float) vol;	/** returns the current volume */
-(BOOL) isPassingThrough;

// time is always the target time to reach
-(float) seekTo:(float)time mode:(SEEK_MODE)seekMode;	/** returns the time now being sought to */

-(void) frameStep;

-(float) changeTimeBy:(float) delta;  /** returns the current time value */
-(float) changeSpeedBy:(float) delta; /** returns the current speed value */

-(float) changeSubDelayBy:(float) delta;
-(float) changeAudioDelayBy:(float) delta;
-(float) changeSubScaleBy:(float) delta;
-(float) changeSubPosBy:(float)delta;
-(float) changeAudioBalanceBy:(float)delta;

-(float) setSpeed:(float) spd;
-(float) setSubDelay:(float) sd;
-(float) setAudioDelay:(float) ad;
-(void) setAudioBalance:(float)bal;

-(void) setSubtitle:(int) subID;
-(void) setAudio:(int) audioID;
-(void) setVideo:(int) videoID;

-(void) setLetterBox:(BOOL) renderSubInLB top:(float) topRatio bottom:(float)bottomRatio;
-(void) setEqualizer:(NSArray*) amps;

-(void) loadSubFile:(NSString*)subPath;

-(void) mapAudioChannelsTo:(NSInteger)mode;
-(void) setExternalAudioFilePath:(NSString*)path;

@end