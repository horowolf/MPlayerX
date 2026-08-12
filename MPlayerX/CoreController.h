/*
 * MPlayerX - CoreController.h
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
#import "coredef.h"
#import "PlayerCore.h"
#import "ParameterManager.h"
#import "LogAnalyzer.h"

@class LogAnalyzer, ParameterManager, MovieInfo, PlayerCore, SubConverter;

@interface CoreController : NSObject <PlayerCoreDelegate, LogAnalyzerDelegate>
{
	// state
	int state;

	// basic components
	MovieInfo *movieInfo;
	LogAnalyzer *la;
	ParameterManager *pm;
	PlayerCore *playerCore;
	NSDictionary *mpPathPair;
	SubConverter *subConv;

	// render things
	void *imageData;
	unsigned int imageSize;
	NSUInteger imageBufferCount;	/**< the number of frame buffers in shared memory, depends on the mplayer version */
	NSString *sharedBufferName;
	NSThread *renderThread;

	// delegates
	id<CoreDisplayDelegate> dispDelegate;
	id<CoreControllerDelegate> delegate;
	
	NSTimer *pollingTimer;
	
	NSDictionary *keyPathDict;
	NSDictionary *typeDict;
}

@property (readonly)			int state;
@property (retain, readwrite, nonatomic)	NSDictionary *mpPathPair;
@property (readonly)			MovieInfo *movieInfo;
@property (retain, readwrite)	ParameterManager *pm;
@property (readonly)			LogAnalyzer *la;
@property (assign, readwrite)	id<CoreDisplayDelegate> dispDelegate;
@property (assign, readwrite)	id<CoreControllerDelegate> delegate;

-(void) setSubConverterDelegate:(id<SubConverterDelegate>)dlgt;

-(void) setWorkDirectory:(NSString*) wd;

-(void) playMedia:(NSString*)moviePath;
-(void) performStop;
-(void) togglePause;

-(void) frameStep:(NSInteger)frameNum;

/** If sent successfully, playingInfo's speed property will be updated */
-(void) setSpeed: (float) speed;

/** If sent successfully, playingInfo's currentChapter property will be updated */
-(void) setChapter: (int) chapter;

/** Returns the time value that was set; if it is -1, that means the send was not successful. But even
 *  if the send succeeds, playingInfo's currentTime property will not be updated here -- that property
 *  is updated on a separate thread and must be obtained via KVO.
 *  time is a delta in relative mode, and the target time in absolute mode.
 */
-(float) setTimePos:(float)time mode:(SEEK_MODE)seekMode;

/** If sent successfully, playingInfo's volume property will be updated; returns the actual value it was updated to */
-(float) setVolume: (float) vol;

/** If sent successfully, playingInfo's audioBalance property will be updated */
-(void) setBalance: (float) bal;

/** If sent successfully, playingInfo's mute property will be updated */
-(BOOL) setMute: (BOOL) mute;

-(void) setAudioDelay: (float) delay;

-(void) setAudio: (int) audioID;

-(void) setVideo: (int) videoID;

-(void) setSub: (int) subID;

/** If sent successfully, playingInfo's subDelay property will be updated */
-(void) setSubDelay: (float) delay;

/** If sent successfully, playingInfo's subPos property will be updated */
-(void) setSubPos: (float) pos;

/** If sent successfully, playingInfo's subScale property will be updated */
-(void) setSubScale: (float) scale;

-(void) loadSubFile: (NSString*) path;

-(void) setLetterBox:(BOOL) renderSubInLB top:(float) topRatio bottom:(float)bottomRatio;

-(void) setEqualizer:(NSArray*)amps;

-(void) mapAudioChannelsTo:(NSInteger)mode;

@end
