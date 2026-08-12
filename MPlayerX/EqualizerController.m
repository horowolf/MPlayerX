/*
 * MPlayerX - EqualizerController.m
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

#import "KeyCode.h"
#import "EqualizerController.h"
#import "PlayerController.h"
#import "UserDefaults.h"

#define kAutoSaveEQSettingsLifeNone			(0)		/**< reset as soon as playback starts */
#define kAutoSaveEQSettingsLifeAPN			(1)		/**< reset when it isn't APN */
#define kAutoSaveEQSettingsLifeApplication	(2)		/**< reset when the app quits */
#define kAutoSaveEQSettingsLifeUserDefaults	(3)		/**< never reset */

#define kEQValueDefault		(0.0f)

@interface EqualizerController (Internal)
-(void) playBackStopped:(NSNotification*)notif;
-(void) playBackFinalized:(NSNotification*)notif;
-(void) saveParameters:(NSArray*) arr;
@end

@implementation EqualizerController

+(void) initialize
{
	[[NSUserDefaults standardUserDefaults] 
	 registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
					   [NSNumber numberWithInt:kAutoSaveEQSettingsLifeAPN], kUDKeyAutoSaveEQSettings,
					   nil]];
}

-(id) init
{
	self = [super init];
	
	if (self) {
		ud = [NSUserDefaults standardUserDefaults];

		nibLoaded = NO;
		bars = nil;		
	}
	return self;
}

-(void) dealloc
{
	[bars release];
	[super dealloc];
}

-(void) awakeFromNib
{
	if (!nibLoaded) {
		[menuEQPanel setKeyEquivalent:kSCMEqualizerPanelKeyEquivalent];

		if ([ud integerForKey:kUDKeyAutoSaveEQSettings] != kAutoSaveEQSettingsLifeUserDefaults) {
			// if settings aren't saved permanently, then delete them
			[ud removeObjectForKey:kUDKeyEQSettings];
		}
		
		// load EQ settings
		// the UI hasn't loaded at this point, so no need to set anything on the UI
		// in the future, if the Controller loads the UI right at startup, care must be taken here to keep the UI in sync
		[playerController setEqualizer:[ud arrayForKey:kUDKeyEQSettings]];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playBackFinalized:)
													 name:kMPCPlayFinalizedNotification object:playerController];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playBackStopped:)
													 name:kMPCPlayStoppedNotification object:playerController];
	}
}

-(IBAction) showUI:(id)sender
{
	if (!nibLoaded) {
		NSUInteger idx = 0;
		NSUInteger num = 0;
		NSArray *settings = [ud arrayForKey:kUDKeyEQSettings];
		
		nibLoaded = YES;
		[NSBundle loadNibNamed:@"Equalizer" owner:self];
		
		/** \warning the min/max settings for the Outlets are in the XIB file */
		bars = [[NSArray alloc] initWithObjects:sli30,sli60,sli125,sli250,sli500,sli1k,sli2k,sli4k,sli8k,sli16k,nil];
		
		// per Apple's documentation, array returns nil rather than null when there's no such key
		// so the check here is safe
		if (settings) {
			num = [settings count];
		}
		
		for (id bar in bars) {
			if (idx < num) {
				[bar setFloatValue:[[settings objectAtIndex:idx++] floatValue]];
			} else {
				[bar setFloatValue:kEQValueDefault];
			}
		}

		// set the window's z coordinate
		[EQPanel setLevel:NSMainMenuWindowLevel];
	}
	
	if ([EQPanel isVisible]) {
		[EQPanel orderOut:self];
	} else {
		[EQPanel orderFront:self];
	}
}

-(void) saveParameters:(NSArray*) arr
{
	// since the EQ Slider setting can change very frequently, use a dedicated pool
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSMutableArray *settings = [[NSMutableArray alloc] initWithCapacity:12];
	
	for (id bar in arr) {
		[settings addObject:[NSNumber numberWithFloat:[bar floatValue]]];
	}
	
	[ud setObject:settings forKey:kUDKeyEQSettings];
	
	[settings release];
	
	[pool drain];
}

-(IBAction) setEqualizer:(id)sender
{	
	[playerController setEqualizer:bars];
	
	[self saveParameters:bars];
}

-(IBAction) resetEqualizer:(id)sender
{
	[playerController setEqualizer:nil];
	
	for (id bar in bars) {
		[bar setFloatValue:kEQValueDefault];
	}
	
	[self saveParameters:bars];
}

-(void) playBackStopped:(NSNotification*)notif
{
	if ([ud integerForKey:kUDKeyAutoSaveEQSettings] == kAutoSaveEQSettingsLifeNone) {
		// playback stopped, but we don't know whether it's APN
		// so only reset when the setting is always-reset
		[self resetEqualizer:nil];
	}
}

-(void) playBackFinalized:(NSNotification*)notif
{
	if ([ud integerForKey:kUDKeyAutoSaveEQSettings] == kAutoSaveEQSettingsLifeAPN) {
		// when resetting the option for non-APN
		// because with APN there won't be a Finalized notification
		// so as long as we get this notification, we can reset
		[self resetEqualizer:nil];
	}
}

@end
