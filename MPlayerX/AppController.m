/*
 * MPlayerX - AppController.m
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

#import "AppController.h"
#import "UserDefaults.h"
#import "CocoaAppendix.h"
#import "PlayerController.h"
#import "LocalizedStrings.h"
#import "RootLayerView.h"
#import "SPMediaKeyTap.h"
#import "AODetector.h"

#define kSnapshotSaveDefaultPath	(@"~/Pictures")

/**
 * This is a sample of how to create a singleton object,
 * which could also work in Interface Builder
 *
 * - Declaration
 *   1. Nothing special but "+(AppController*) sharedAppController;" is enough,
 *      the return type of "id" would be better, but I prefer strict typing.
 *
 * - Implementation
 *    1. static AppController *sharedInstance = nil;
 *    2. static BOOL init_ed = NO;
 *       init_ed is to avoid [[ alloc] init] to initialize the static object again.
 *    3. +(AppController*) sharedAppController
 *    4. -(id) init
 *       The basic initialize method. this should be called only once.
 *    5. +(id) allocWithZone:(NSZone *)zone { return [[self sharedAppController] retain]; }
 *    6. -(id) copyWithZone:(NSZone*)zone { return self; }
 *    7. -(id) retain { return self; }
 *    8. -(NSUInteger) retainCount { return NSUIntegerMax; }
 *    9. -(void) release { }
 *   10. -(id) autorelease { return self; }
 *   11. -(void) dealloc
 *      
 */

NSString * const kMPCFMTBookmarkPath	= @"bookmarks.plist";
NSString * const kMPXFeedbackURL		= @"http://mplayerx.org/#contact";
NSString * const kMPXWikiURL			= @"https://github.com/niltsh/MPlayerX/wiki";
NSString * const kMPXEAFPlaceHolder		= @"";

static AppController *sharedInstance = nil;
static BOOL init_ed = NO;

@implementation AppController

@synthesize bookmarks;
@synthesize supportVideoFormats;
@synthesize supportAudioFormats;
@synthesize supportSubFormats;
@synthesize playableFormats;

+(void) initialize
{
	[[NSUserDefaults standardUserDefaults] 
	 registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
					   [NSNumber numberWithBool:NO], kUDKeyLogMode,
					   kSnapshotSaveDefaultPath, kUDKeySnapshotSavePath,
					   @"NO", @"AppleMomentumScrollSupported",
					   [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers], kMediaKeyUsingBundleIdentifiersDefaultsKey,
					   [NSNumber numberWithBool:YES], kUDKeyEnableMediaKeyTap,
					   [NSNumber numberWithBool:NO], kUDKeyDisableLastStopBookmark,
					   nil]];

	MPSetLogEnable([[NSUserDefaults standardUserDefaults] boolForKey:kUDKeyLogMode]);
}
					   
+(AppController*) sharedAppController
{
	if (sharedInstance == nil) {
		sharedInstance = [[super allocWithZone:nil] init];
	}
	return sharedInstance;
}

-(id) init
{
	if (init_ed == NO) {
		init_ed = YES;

		ud = [NSUserDefaults standardUserDefaults];
		notifCenter = [NSNotificationCenter defaultCenter];

		NSBundle *mainBundle = [NSBundle mainBundle];
		// build the Set of supported formats
		for( NSDictionary *dict in [mainBundle objectForInfoDictionaryKey:@"CFBundleDocumentTypes"]) {
			
			NSString *obj = [dict objectForKey:@"CFBundleTypeName"];
			// for the different kinds of formats
			if ([obj isEqualToString:@"Audio Media"]) {
				// if it's an audio file
				supportAudioFormats = [[NSSet alloc] initWithArray:[dict objectForKey:@"CFBundleTypeExtensions"]];
				
			} else if ([obj isEqualToString:@"Video Media"]) {
				// if it's a video file
				supportVideoFormats = [[NSSet alloc] initWithArray:[dict objectForKey:@"CFBundleTypeExtensions"]];
			} else if ([obj isEqualToString:@"Subtitle"]) {
				// if it's a subtitle file
				supportSubFormats = [[NSSet alloc] initWithArray:[dict objectForKey:@"CFBundleTypeExtensions"]];
			}
		}
		
		playableFormats = [[supportVideoFormats setByAddingObjectsFromSet:supportAudioFormats] retain];
		
		/////////////////////////setup bookmarks////////////////////
		// get the bookmark file name
		NSString *lastStoppedTimePath = [[NSFileManager UserPath:NSApplicationSupportDirectory WithSuffix:kMPCStringMPlayerX] stringByAppendingPathComponent:kMPCFMTBookmarkPath];

		// get the dict that records playback time
		bookmarks = [[NSMutableDictionary alloc] initWithContentsOfFile:lastStoppedTimePath];
		if (!bookmarks) {
			// if the file doesn't exist or the format is invalid
			bookmarks = [[NSMutableDictionary alloc] initWithCapacity:10];
		}
		keyTap = nil;
	}
	return self;
}

+(id) allocWithZone:(NSZone *)zone { return [[self sharedAppController] retain]; }
-(id) copyWithZone:(NSZone*)zone { return self; }
-(id) retain { return self; }
-(NSUInteger) retainCount { return NSUIntegerMax; }
-(oneway void) release { }
-(id) autorelease { return self; }

-(void) dealloc
{
	[supportVideoFormats release];
	[supportAudioFormats release];
	[supportSubFormats release];
	[playableFormats release];
	
	[bookmarks release];
	[keyTap release];
	sharedInstance = nil;
	
	[super dealloc];
}

-(void) awakeFromNib
{
	// setup url list for OpenURL Panel
	[openUrlController initURLList:bookmarks];
	
	if ([ud boolForKey:kUDKeyDisableLastStopBookmark]) {
		// disable bookmark completely
		[bookmarks removeAllObjects];
	}
	
	[externalAudioFilePath setStringValue:kMPXEAFPlaceHolder];
}

-(BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if ([menuItem action] == @selector(moveToTrash:)) {
		return ([playerController lastPlayedPath] != nil);
	}
	return YES;
}
/////////////////////////////////////Actions//////////////////////////////////////
-(IBAction) openFile:(id) sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setCanChooseFiles:YES];
	[openPanel setCanChooseDirectories:NO];
	[openPanel setResolvesAliases:NO];
	// playlists aren't supported yet, so disable multiple selection
	[openPanel setAllowsMultipleSelection:NO];
	[openPanel setCanCreateDirectories:NO];
	[openPanel setTitle:kMPXStringOpenMediaFiles];
	[openPanel setAccessoryView:openPanelAccView];
	
	if ([openPanel runModal] == NSFileHandlingPanelOKButton) {
		
		BOOL isDir = YES;
		if ([[NSFileManager defaultManager] fileExistsAtPath:[externalAudioFilePath stringValue] isDirectory:&isDir] &&
			(!isDir)) {
			[playerController setExternalAudioFilePath:[externalAudioFilePath stringValue]];
		}
		// this could also be opening a folder like dvdmedia, so the actual file-opening action is done in the application delegate method
		NSString *fileUrl = [[[openPanel URLs] objectAtIndex:0] path];
		
		if ([[[fileUrl pathExtension] lowercaseString] isEqualToString:@"dvdmedia"]) {
			[playerController setPlayDisk:kPMPlayDiskDVD];
			[playerController loadFiles:[openPanel URLs] fromLocal:YES];
			[playerController setPlayDisk:kPMPlayDiskNone];
		} else {
			[playerController loadFiles:[openPanel URLs] fromLocal:YES];
		}
		// if an audiofile was selected, clear it
		[externalAudioFilePath setStringValue:kMPXEAFPlaceHolder];
	}
}

-(IBAction) openExternalAudioFile:(id)sender
{
	NSOpenPanel *openEAF = [NSOpenPanel openPanel];
	[openEAF setCanChooseFiles:YES];
	[openEAF setCanChooseDirectories:NO];
	[openEAF setResolvesAliases:NO];
	[openEAF setAllowsMultipleSelection:NO];
	[openEAF setCanCreateDirectories:NO];
	[openEAF setTitle:kMPXStringOpenMediaFiles];
	
	[openEAF beginSheetModalForWindow:[sender window] completionHandler:^(NSInteger result) {
		if (result == NSFileHandlingPanelOKButton) {
			[externalAudioFilePath setStringValue:[[[openEAF URLs] objectAtIndex:0] path]];
		}
	}];
}

-(IBAction) openVIDEOTS:(id) sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setCanChooseFiles:NO];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setResolvesAliases:NO];
	// playlists aren't supported yet, so disable multiple selection
	[openPanel setAllowsMultipleSelection:NO];
	[openPanel setCanCreateDirectories:NO];
	[openPanel setTitle:kMPXStringOpenVideo_TS];
	
	if ([openPanel runModal] == NSFileHandlingPanelOKButton) {
		[playerController setPlayDisk:kPMPlayDiskDVD];
		[playerController loadFiles:[openPanel URLs] fromLocal:YES];
		[playerController setPlayDisk:kPMPlayDiskNone];
	}	
}

-(IBAction) gotoWikiPage:(id) sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kMPXWikiURL]];
}

-(IBAction) writeSnapshotToFile:(id)sender
{
	// get the image data
	CIImage *snapshot = [dispView snapshot];
	
	if (snapshot != nil) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		// get the save folder
		NSString *savePath = [ud stringForKey:kUDKeySnapshotSavePath];
		
		// if it's the default path, replace it with the absolute path
		if ([savePath isEqualToString:kSnapshotSaveDefaultPath]) {
			savePath = [NSFileManager UserPath:NSPicturesDirectory WithSuffix:kMPCStringMPlayerX];
		}
		
		NSFileManager *fm = [NSFileManager defaultManager];
		BOOL isDir = NO;
		if ([fm fileExistsAtPath:savePath isDirectory:&isDir] && (!isDir)) {
			// if it exists but isn't a folder
			[fm removeItemAtPath:savePath error:NULL];
		}
		if (!isDir) {
			// if the folder doesn't exist, or what exists there is a file, need to recreate the folder either way
			if (![fm createDirectoryAtPath:savePath withIntermediateDirectories:YES attributes:nil error:NULL]) {
				savePath = nil;
			}
		}

		if (savePath) {
			NSString *mediaPath = ([playerController.lastPlayedPath isFileURL])?([playerController.lastPlayedPath path]):([playerController.lastPlayedPath absoluteString]);
			NSString *dateTime = [NSDateFormatter localizedStringFromDate:[NSDate date]
																dateStyle:NSDateFormatterMediumStyle
																timeStyle:NSDateFormatterMediumStyle];
			dateTime = [dateTime stringByReplacingOccurrencesOfString:@":" withString:@"."];
			dateTime = [dateTime stringByReplacingOccurrencesOfString:@"/" withString:@"."];
			
			// create the file name
			// replace the ":" in the file name, since ":" can't be stored as part of a file name
			savePath = [NSString stringWithFormat:@"%@/%@_%@.png", savePath, [[mediaPath lastPathComponent] stringByDeletingPathExtension],dateTime];							   
			// get the image's Rep
			NSBitmapImageRep *imRep = [[NSBitmapImageRep alloc] initWithCIImage:snapshot];
			// set this Rep's storage format
			NSData *imData = [NSBitmapImageRep representationOfImageRepsInArray:[NSArray arrayWithObject:imRep]
																	  usingType:NSPNGFileType
																	 properties:[NSDictionary dictionary]];
			// write the file
			[imData writeToFile:savePath atomically:YES];
			[imRep release];			
		}
		[pool drain];
	}
}

-(IBAction) moveToTrash:(id) sender
{
	NSURL *path = [[playerController lastPlayedPath] retain];
		
	if (path && [path isFileURL]) {
		[playerController stop];
		[[NSWorkspace sharedWorkspace] recycleURLs:[NSArray arrayWithObject:path] completionHandler:nil];
	}
	[path release];
}

-(IBAction) donate:(id)sender
{
	NSArray *langs = [NSLocale preferredLanguages];
	NSString *currency = nil;
	
	if (langs && [[langs objectAtIndex:0] isEqualToString:@"ja"]) {
		MPLog(@"Japanese user");
		currency = @"JPY";
	} else {
		currency = @"USD";
	}

	[[NSWorkspace sharedWorkspace] openURL:
	 [NSURL URLWithString:[NSString stringWithFormat:
						   @"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=mplayerx%%2eqzy%%40gmail%%2ecom&lc=US&item_name=MPlayerX&no_note=0&currency_code=%@&bn=PP%%2dDonationsBF%%3abtn_donate_LG%%2egif%%3aNonHostedGuest", currency]]];
}

-(IBAction) gotoFeedbackPage:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kMPXFeedbackURL]];
}

//////////////////////////////////////Media Key Delegate//////////////////////////////////////
-(void) mediaKeyTap:(SPMediaKeyTap*)keyTap receivedMediaKeyEvent:(NSEvent*)event
{
	NSAssert([event type] == NSSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys, @"Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:");
	// here be dragons...
	int keyCode = (([event data1] & 0xFFFF0000) >> 16);
	int keyFlags = ([event data1] & 0x0000FFFF);
	BOOL keyIsPressed = (((keyFlags & 0xFF00) >> 8)) == 0xA;
	int keyRepeat = (keyFlags & 0x1);
	
	if (!keyRepeat) {
		switch (keyCode) {
			case NX_KEYTYPE_PLAY:
				if (keyIsPressed == NO) {
					MPLog(@"Media Key: play/pause");
					[[NSNotificationCenter defaultCenter] postNotificationName:kMPXMediaKeyPlayPauseNotification object:NSApp];
				}
				break;
			case NX_KEYTYPE_FAST:
				if (keyIsPressed == YES) {
					MPLog(@"Media Key: forward");
					[[NSNotificationCenter defaultCenter] postNotificationName:kMPXMediaKeyForwardNotification object:NSApp];
				}
				break;
			case NX_KEYTYPE_REWIND:
				if (keyIsPressed == YES) {
					MPLog(@"Media Key: backward");
					[[NSNotificationCenter defaultCenter] postNotificationName:kMPXMediaKeyBackwardNotification object:NSApp];
				}
				break;
			default:
				MPLog(@"Media Key %d pressed", keyCode);
				break;
		}
	}
}
/////////////////////////////////////Application Delegate//////////////////////////////////////
-(BOOL) application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	BOOL isDir = NO, ret = NO;
	
	// check whether the file exists here, in preparation for command line arguments
	if ([[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&isDir]) {
		if (isDir) {
			[playerController setPlayDisk:kPMPlayDiskDVD];
			[playerController loadFiles:[NSArray arrayWithObject:filename] fromLocal:YES];
			[playerController setPlayDisk:kPMPlayDiskNone];
		} else {
			[playerController loadFiles:[NSArray arrayWithObject:filename] fromLocal:YES];
		}
		ret = YES;
	}
	return ret;
}

-(void) application:(NSApplication *)theApplication openFiles:(NSArray *)filenames
{
	BOOL isDir = NO;
	NSApplicationDelegateReply reply = NSApplicationDelegateReplyFailure;
	
	// check whether the file exists here, in preparation for command line arguments
	if ([[NSFileManager defaultManager] fileExistsAtPath:[filenames objectAtIndex:0] isDirectory:&isDir]) {
		if (isDir) {
			[playerController setPlayDisk:kPMPlayDiskDVD];
			[playerController loadFiles:filenames fromLocal:YES];
			[playerController setPlayDisk:kPMPlayDiskNone];
		} else {
			[playerController loadFiles:filenames fromLocal:YES];
		}
		reply = NSApplicationDelegateReplySuccess;
	}
	[theApplication replyToOpenOrPrint:reply];
}

-(NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication *)sender
{
	if (keyTap) {
		[keyTap stopWatchingMediaKeys];
	}
	
	[playerController stop];
	
	[ud synchronize];

	[openUrlController syncToBookmark:bookmarks];
	
	[bookmarks writeToFile:[[NSFileManager UserPath:NSApplicationSupportDirectory WithSuffix:kMPCStringMPlayerX] stringByAppendingPathComponent:kMPCFMTBookmarkPath]
				atomically:YES];
	
	// don't enable listening for now
	// [[AODetector defaultDetector] stopListening];
	
	return NSTerminateNow;	
}

-(void) applicationDidFinishLaunching:(NSNotification *)notification
{
	if ([ud boolForKey:kUDKeyEnableMediaKeyTap]) {
		keyTap = [[SPMediaKeyTap alloc] initWithDelegate:self];
		if ([SPMediaKeyTap usesGlobalMediaKeyTap]) {
			[keyTap startWatchingMediaKeys];
		} else {
			MPLog(@"MediaKey monitoring Disabled.");
		}
	}
	
	// start listening to the AudioDevice
	// if the app was opened by double-clicking a file, application:(NSApplication *)theApplication openFile:(NSString *)filename will be called before this method
	// which means play would need to start before startListening
	// but that's fine - even without listening, playerController calls [AODetector defaultDetector] when playing, which forces a check of whether it's digital, so there's no problem
	// this method is placed here because we don't want to delay startup time
	// don't enable listening for now
	// [[AODetector defaultDetector] startListening];
	
	NSString *cmdStr;
	
	cmdStr = [ud stringForKey:@"url"];
	
	if (cmdStr) {
		MPLog(@"url:%@", cmdStr);
		
		[playerController loadFiles:[NSArray arrayWithObject:cmdStr] fromLocal:NO];
		
	} else {
		cmdStr = [ud stringForKey:@"file"];
		
		if (cmdStr) {
			MPLog(@"file:%@", cmdStr);
			[self application:NSApp openFile:cmdStr];
		}
	}
}

@end
