/*
 * MPlayerX - PlayerController.m
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

#import "CocoaAppendix.h"
#import "UserDefaults.h"
#import "KeyCode.h"
#import "LocalizedStrings.h"
#import "PlayerController.h"
#import <sys/sysctl.h>
#import "AppController.h"
#import "CoreController.h"
#import "AODetector.h"
#import <sys/mount.h>

NSString * const kMPCPlayOpenedNotification			= @"kMPCPlayOpenedNotification";
NSString * const kMPCPlayOpenedURLKey				= @"kMPCPlayOpenedURLKey";
NSString * const kMPCPlayLastStoppedTimeKey			= @"kMPCPlayLastStoppedTimeKey";

NSString * const kMPCPlayStartedNotification		= @"kMPCPlayStartedNotification";
NSString * const kMPCPlayStartedAudioOnlyKey		= @"kMPCPlayStartedAudioOnlyKey";

NSString * const kMPCPlayStoppedNotification		= @"kMPCPlayStoppedNotification";
NSString * const kMPCPlayWillStopNotification		= @"kMPCPlayWillStopNotification";
NSString * const kMPCPlayFinalizedNotification		= @"kMPCPlayFinalizedNotification";

NSString * const kMPCPlayInfoUpdatedNotification	= @"kMPCPlayInfoUpdatedNotification";
NSString * const kMPCPlayInfoUpdatedKeyPathKey		= @"kMPCPlayInfoUpdatedKeyPathKey";
NSString * const kMPCPlayInfoUpdatedChangeDictKey	= @"kMPCPlayInfoUpdatedChangeDictKey";

NSString * const kMPCMplayerNameMT		= @"mplayer-mt";
NSString * const kMPCMplayerName		= @"mplayer";
NSString * const kMPCFMTMplayerPathM32	= @"binaries/m32/%@";
NSString * const kMPCFMTMplayerPathX64	= @"binaries/x86_64/%@";
NSString * const kMPCFMTMplayerPathArm64 = @"binaries/arm64/%@";

NSString * const kMPCFFMpegProtoHead	= @"ffmpeg://";

NSString * const kMPXPowerSaveAssertion	= @"MPlayerX is in playback.";

#define kThreadsNumMax	(8)

#define PlayerCouldAcceptCommand	(((mplayer.state) & 0x0100)!=0)

/** state of APN */
enum {
	kMPCAutoPlayStateInvalid   = 0,
	kMPCAutoPlayStateJustFound = 1,
	kMPCAutoPlayStatePlaying   = 2
};

@interface PlayerController (CoreControllerDelegate)
-(void) playbackOpened:(id)coreController;
-(void) playbackStarted:(id)coreController;
-(void) playbackWillStop:(id)coreController;
-(void) playbackStopped:(id)coreController info:(NSDictionary*)dict;
-(void) playbackError:(id)coreController;
@end

@interface PlayerController (PlayerControllerInternal)
-(NSString*) preferredMPlayerArchKey;
-(NSSet*) supportedOptionsOfMPlayerAtPath:(NSString*)path;
-(void) playMedia:(NSURL*)url;
-(NSURL*) findFirstMediaFileFromSubFile:(NSString*)path;
-(void) enablePowerSave:(BOOL)en;
@end

@interface PlayerController (SubConverterDelegate)
-(NSString*) subConverter:(id)subConv detectedFile:(NSString*)path ofCharsetName:(NSString*)charsetName confidence:(float)confidence;
@end

@implementation PlayerController

@synthesize lastPlayedPath;

+(void) initialize
{
	NSNumber *boolYes = [NSNumber numberWithBool:YES];
	NSNumber *boolNo  = [NSNumber numberWithBool:NO];
	
	[[NSUserDefaults standardUserDefaults] 
	 registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
					   boolYes, kUDKeyAutoPlayNext,
					   kMPCDefaultSubFontPath, kUDKeySubFontPath,
					   boolYes, kUDKeyPrefer64bitMPlayer,
					   boolYes, kUDKeyEnableMultiThread,
					   [NSNumber numberWithFloat:1.0], kUDKeySubScale,
					   [NSNumber numberWithFloat:0.1], kUDKeySubScaleStepValue,
					   [NSArchiver archivedDataWithRootObject:[NSColor colorWithCalibratedWhite:1.0 alpha:1.00]], kUDKeySubFontColor,
					   [NSArchiver archivedDataWithRootObject:[NSColor colorWithCalibratedWhite:0.0 alpha:0.85]], kUDKeySubFontBorderColor,
					   boolNo, kUDKeyForceIndex,
					   [NSNumber numberWithUnsignedInt:kSubFileNameRuleContain], kUDKeySubFileNameRule,
					   boolNo, kUDKeyDTSPassThrough,
					   boolNo, kUDKeyAC3PassThrough,
					   /** auto processor setting */
					   [NSNumber numberWithUnsignedInt:[[NSProcessInfo processInfo] processorCount]], kUDKeyThreadNum,
					   boolYes, kUDKeyUseEmbeddedFonts,
					   [NSNumber numberWithUnsignedInt:10000], kUDKeyCacheSize,
					   [NSNumber numberWithUnsignedInt:5000], kUDKeyCacheSizeLocalMinLimit,
					   [NSNumber numberWithUnsignedInt:20], kUDKeyCacheSizeLocalTime,
					   boolYes, kUDKeyPreferIPV6,
					   [NSNumber numberWithUnsignedInt:kPMLetterBoxModeNotDisplay], kUDKeyLetterBoxMode,
					   [NSNumber numberWithUnsignedInt:kPMLetterBoxModeBoth], kUDKeyLetterBoxModeAlt,
					   [NSNumber numberWithFloat:0.1], kUDKeyLetterBoxHeight,
					   boolYes, kUDKeyPlayWhenOpened,
					   boolYes, kUDKeyOverlapSub,
					   boolYes, kUDKeyRtspOverHttp,
					   [NSNumber numberWithUnsignedInt:kPMMixDTS5_1ToStereo], kUDKeyMixToStereoMode,
					   boolYes, kUDKeyAutoResume,
					   [NSNumber numberWithUnsignedInt:kPMImgEnhanceNone], kUDKeyImgEnhanceMethod,
					   [NSNumber numberWithUnsignedInt:kPMDeInterlaceNone], kUDKeyDeIntMethod,
					   @"", kUDKeyExtraOptions,
					   [NSNumber numberWithUnsignedInt:kPMSubAlignDefault], kUDKeySubAlign,
					   [NSNumber numberWithUnsignedInt:kPMSubBorderWidthDefault], kUDKeySubBorderWidth,
					   [NSNumber numberWithUnsignedInt:kPMAssSubMarginVDefault], kUDKeyAssSubMarginV,
					   boolNo, kUDKeyNoDispSub,
					   boolNo, kUDKeyAutoDetectSPDIF,
					   boolYes, kUDKeyEnableOpenRecentMenu,
					   nil]];	
}

#pragma mark Init/Dealloc
-(id) init
{
	self = [super init];
	
	if (self) {
		ud = [NSUserDefaults standardUserDefaults];
		notifCenter = [NSNotificationCenter defaultCenter];
		
		mplayer = [[CoreController alloc] init];
		[mplayer setDelegate:self];
		
		// TODO Need test
		/////////////////////////setup subconverter////////////////////
		NSFileManager *fm = [NSFileManager defaultManager];
		BOOL isDir = NO;
		NSString *workDir = [NSFileManager UserPath:NSApplicationSupportDirectory WithSuffix:kMPCStringMPlayerX];
		
		if ([fm fileExistsAtPath:workDir isDirectory:&isDir] && (!isDir)) {
			// If it exists but is not a folder
			[fm removeItemAtPath:workDir error:NULL];
		}
		if (!isDir) {
			// If this folder didn't exist before, or if a file exists there instead, the folder needs to be recreated
			if (![fm createDirectoryAtPath:workDir withIntermediateDirectories:YES attributes:nil error:NULL]) {
				workDir = nil;
			}
		}
		[mplayer setWorkDirectory:workDir];
		[mplayer setSubConverterDelegate:self];

		NSString *subFontPath = [ud stringForKey:kUDKeySubFontPath];
		
		if (![subFontPath isEqualToString:kMPCDefaultSubFontPath]) {
			// If it's not the default path
			isDir = YES;
			if ((![fm fileExistsAtPath:subFontPath isDirectory:&isDir]) || isDir) {
				[ud setObject:kMPCDefaultSubFontPath forKey:kUDKeySubFontPath];
			}
		}

		/////////////////////////setup CoreController////////////////////
		[self setMultiThreadMode:[ud boolForKey:kUDKeyEnableMultiThread]];

		// Decide which arch of mplayer to use
		[mplayer.pm setMplayerArch:[self preferredMPlayerArchKey]];

		// Ask which parameters this mplayer supports
		[mplayer.pm setSupportedOptions:
		 [self supportedOptionsOfMPlayerAtPath:
		  [[mplayer mpPathPair] objectForKey:mplayer.pm.mplayerArch]]];

		lastPlayedPath = nil;
		lastPlayedPathPre = nil;

		kvoSetuped = NO;
		
		autoPlayState = kMPCAutoPlayStateInvalid;
		
		nonSleepHandler = kIOPMNullAssertionID;
	}
	return self;
}

-(void) setupKVO
{
	if (!kvoSetuped) {
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathLength
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathCurrentTime
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathSeekable
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathSpeed
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathSubDelay
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathAudioDelay
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathSubInfo
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathCachingPercent
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathAudioInfo
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathVideoInfo
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathAudioInfoID
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathVideoInfoID
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		[mplayer addObserver:self
				  forKeyPath:kKVOPropertyKeyPathChapterInfo
					 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					 context:NULL];
		kvoSetuped = YES;	
	}
}

-(void) dealloc
{
	if (kvoSetuped) {
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathCurrentTime];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathLength];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathSeekable];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathSpeed];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathSubDelay];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathAudioDelay];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathSubInfo];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathCachingPercent];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathAudioInfo];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathVideoInfo];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathAudioInfoID];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathVideoInfoID];
		[mplayer removeObserver:self forKeyPath:kKVOPropertyKeyPathChapterInfo];
		
		kvoSetuped = NO;
	}

	if (nonSleepHandler != kIOPMNullAssertionID) {
		IOPMAssertionRelease(nonSleepHandler);
		nonSleepHandler = kIOPMNullAssertionID;
	}
	
	[mplayer release];
	[lastPlayedPath release];

	[super dealloc];
}

-(void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == mplayer) {
		[notifCenter postNotificationName:kMPCPlayInfoUpdatedNotification object:self
								 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
										   keyPath, kMPCPlayInfoUpdatedKeyPathKey,
										   change, kMPCPlayInfoUpdatedChangeDictKey, nil]];
		// MPLog(@"%@", keyPath);
		return;
	}
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

-(id) setDisplayDelegateForMPlayer:(id<CoreDisplayDelegate>) delegate
{
	[mplayer setDispDelegate:delegate];
	return mplayer;
}

-(int) playerState { return mplayer.state; }
-(BOOL) couldAcceptCommand { return PlayerCouldAcceptCommand; }
-(MovieInfo*) mediaInfo { return [mplayer movieInfo]; }
-(void) setPlayDisk:(NSInteger) pd { [mplayer.pm setPlayDisk:pd]; }

-(void) enablePowerSave:(BOOL)en
{
	if (en) {
		// to enable power save, release the assertion
		if (nonSleepHandler != kIOPMNullAssertionID) {
			IOPMAssertionRelease(nonSleepHandler);
			nonSleepHandler = kIOPMNullAssertionID;
		}	
	} else {
		// to disable power save, create the assertion
		if (nonSleepHandler == kIOPMNullAssertionID) {
			IOReturn err =
				IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep, kIOPMAssertionLevelOn,
											(CFStringRef)kMPXPowerSaveAssertion, &nonSleepHandler);
			if (err != kIOReturnSuccess) {
				MPLog(@"Can't disable powersave");
			}
		}
	}
}

-(void) loadFiles:(NSArray*)files fromLocal:(BOOL)local
{
	if (files) {
		NSString *path;
		BOOL isDir = YES;
		NSFileManager *fm = [NSFileManager defaultManager];

		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		for (id file in files) {
		
			// If it's a string, first convert it to a URL
			if ([file isKindOfClass:[NSString class]]) {
				if (local) {
					file = [NSURL fileURLWithPath:file isDirectory:NO];
				} else {
					file = [NSURL URLWithString:file];
				}
			}
			
			if (file && [file isKindOfClass:[NSURL class]]) {
				if ([file isFileURL]) {
					// If it's a local file
					path = [file path];
					isDir = YES;

					if ([fm fileExistsAtPath:path isDirectory:&isDir]) {
						if (isDir) {
							// If it's a folder
							[self playMedia:file];
							break;
						} else {
							// If the file exists
							NSString *ext = [[path pathExtension] lowercaseString];

							if ([[[AppController sharedAppController] playableFormats] containsObject:ext]) {
								// If it's a supported format
								[self playMedia:file];
								break;

							} else if ([[[AppController sharedAppController] supportSubFormats] containsObject:ext]) {
								// If it's a subtitle file
								if (PlayerCouldAcceptCommand) {
									// If playback is active, load the subtitle
									[self loadSubFile:path];
								} else {
									// If in the stopped state, the user probably wants to open a media file first
									// Need to search for a movie file based on the subtitle file name
									NSURL *autoSearchMediaFile = [self findFirstMediaFileFromSubFile:path];

									if (autoSearchMediaFile) {
										// If found
										[self playMedia:autoSearchMediaFile];
									}
									// Whether or not it was found, need to break either way
									// If found, play it
									// If not found, it means no corresponding media file exists under the current filename rule
									if (!autoSearchMediaFile) {
										// If no suitable media file to play was found
										[self showAlertPanelModal:kMPXStringCantFindMediaFile];
									}
									break;
								}
							} else {
								if ([NSEvent modifierFlags] & NSControlKeyMask) {
									// open the file while control key pressing
									// try to open the file
									[self playMedia:file];
									break;
								} else {
									// Otherwise show a prompt
									[self showAlertPanelModal:kMPXStringFileNotSupported];
								}
							}
						}
					} else {
						// File doesn't exist
						[self showAlertPanelModal:kMPXStringFileNotExist];
					}
				} else {
					// If it's not a local file
					[self playMedia:file];
					break;
				}
			}
		}
		[pool drain];
	}
}

static BOOL isNetworkPath(const char *path)
{
	BOOL ret = NO;
	
	if (path) {
		struct statfs buf;
		
		if (statfs(path, &buf) == 0) {
			if ((strncasecmp(buf.f_fstypename, "nfs", 3) == 0) ||
				(strncasecmp(buf.f_fstypename, "afp", 3) == 0) ||
				(strncasecmp(buf.f_fstypename, "smb", 3) == 0) ||
				(strncasecmp(buf.f_fstypename, "web", 3) == 0) ||
				(strncasecmp(buf.f_fstypename, "ftp", 3) == 0)) {
				MPLog(@"Actually a network path:%s", buf.f_fstypename);
				ret = YES;
			}
		}
	}
	return ret;
}

-(void) playMedia:(NSURL*)url
{
	// Internal function, not that necessary to check the validity of url
	NSString *path;
	NSNumber *stime;

	// Set the subtitle size
	[mplayer.pm setSubScale:[ud floatForKey:kUDKeySubScale]];
	[mplayer.pm setSubFontColor: [NSUnarchiver unarchiveObjectWithData: [ud objectForKey:kUDKeySubFontColor]]];
	[mplayer.pm setSubFontBorderColor: [NSUnarchiver unarchiveObjectWithData: [ud objectForKey:kUDKeySubFontBorderColor]]];
	// Get the path to the subtitle font file
	NSString *subFontPath = [ud stringForKey:kUDKeySubFontPath];

	if ([subFontPath isEqualToString:kMPCDefaultSubFontPath]) {
		// If it's the default path, some path prefix needs to be prepended
		[mplayer.pm setSubFont:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:kMPCDefaultSubFontPath]];
	} else {
		// Otherwise set it directly
		[mplayer.pm setSubFont:subFontPath];
	}
	
	[mplayer.pm setForceIndex:[ud boolForKey:kUDKeyForceIndex]];
	[mplayer.pm setSubNameRule:[ud integerForKey:kUDKeySubFileNameRule]];
	
	if ([ud boolForKey:kUDKeyAutoDetectSPDIF]) {
		BOOL digi = [[AODetector defaultDetector] isDigital];
		[mplayer.pm setDtsPass:digi];
		[mplayer.pm setAc3Pass:digi];
	} else {
		[mplayer.pm setDtsPass:[ud boolForKey:kUDKeyDTSPassThrough]];
		[mplayer.pm setAc3Pass:[ud boolForKey:kUDKeyAC3PassThrough]];
	}
	[mplayer.pm setUseEmbeddedFonts:[ud boolForKey:kUDKeyUseEmbeddedFonts]];
	
	[mplayer.pm setLetterBoxMode:[ud integerForKey:kUDKeyLetterBoxMode]];
	[mplayer.pm setLetterBoxHeight:[ud floatForKey:kUDKeyLetterBoxHeight]];
	
	[mplayer.pm setOverlapSub:[ud boolForKey:kUDKeyOverlapSub]];
	[mplayer.pm setMixToStereo:[ud integerForKey:kUDKeyMixToStereoMode]];
	
	[mplayer.pm setImgEnhance:[ud integerForKey:kUDKeyImgEnhanceMethod]];
	[mplayer.pm setDeinterlace:[ud integerForKey:kUDKeyDeIntMethod]];

	[mplayer.pm setExtraOptions:[ud stringForKey:kUDKeyExtraOptions]];
	[mplayer.pm setSubAlign:[ud integerForKey:kUDKeySubAlign]];
	[mplayer.pm setSubBorderWidth:[ud integerForKey:kUDKeySubBorderWidth]];
	[mplayer.pm setAssSubMarginV:[ud integerForKey:kUDKeyAssSubMarginV]];
	
	if (autoPlayState == kMPCAutoPlayStateJustFound) {
		// when APN, do not pause at start
		[mplayer.pm setPauseAtStart:NO];
	} else {
		[mplayer.pm setPauseAtStart:![ud boolForKey:kUDKeyPlayWhenOpened]];
	}
	
	[mplayer.pm setNoDispSub:[ud boolForKey:kUDKeyNoDispSub]];

	// Must retain here, otherwise there would be a problem if lastPlayedPath were passed in as the argument
	lastPlayedPathPre = [[url absoluteURL] retain];
	
	if ([url isFileURL]) {
		// local files
		path = [url path];

		if (isNetworkPath([path UTF8String])) {
			// is network path
			[mplayer.pm setCache:[ud integerForKey:kUDKeyCacheSize]];
			[mplayer.pm setDisplayCacheLog:YES];
		} else {
			// local path
			// the local cache should use another value
			unsigned long long cacheSize = 0;
			NSDictionary *fileInfo = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];

			if (fileInfo) {
				// assuming one movie is 6000 seconds, 
				cacheSize = [[fileInfo objectForKey:NSFileSize] unsignedLongLongValue] * [ud integerForKey:kUDKeyCacheSizeLocalTime] / 6000000;
			}
			[mplayer.pm setCache:(unsigned int)(MAX(cacheSize, [ud integerForKey:kUDKeyCacheSizeLocalMinLimit]))];
			[mplayer.pm setDisplayCacheLog:NO];
		}
		[mplayer.pm setRtspOverHttp:NO];
		
		// Add the file to the Recent Menu; only local files can be added
		if ([ud boolForKey:kUDKeyEnableOpenRecentMenu]) {
			[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:url];
		}
	} else {
		// network stream
		path = [url absoluteString];
		
		[mplayer.pm setCache:[ud integerForKey:kUDKeyCacheSize]];
		[mplayer.pm setPreferIPV6:[ud boolForKey:kUDKeyPreferIPV6]];
		[mplayer.pm setRtspOverHttp:[ud boolForKey:kUDKeyRtspOverHttp]];
		[mplayer.pm setDisplayCacheLog:YES];
		
		// Add the URL to OpenURLController
		[openUrlController addUrl:path];

		if ([ud boolForKey:kUDKeyFFMpegHandleStream] != ([NSEvent modifierFlags]==kSCMFFMpegHandleStreamShortCurKey)) {
			path = [kMPCFFMpegProtoHead stringByAppendingString:path];
		}
	}

	////////////////////////////////////////////////////////////////////
	// HACK!!! always try to use ffmpeg as the demuxer
	// EXCEPT real media
	NSString *ext = [[path pathExtension] lowercaseString];
	if ([ext isEqualToString:@"rm"] || [ext isEqualToString:@"rmvb"] ||
		[ext isEqualToString:@"ra"] || [ext isEqualToString:@"ram"]) {
		[mplayer.pm setDemuxer:nil];
	} else {
		[mplayer.pm setDemuxer:kPMValDemuxFFMpeg];
	}
	////////////////////////////////////////////////////////////////////

	if ([ud boolForKey:kUDKeyAutoResume] && (stime = [[[AppController sharedAppController] bookmarks] objectForKey:[lastPlayedPathPre absoluteString]])) {
		// if AutoResume is ON and there was a record in the bookmarks
		// and 5s to help the users to remember where they left in the movie
		[mplayer.pm setStartTime:([stime floatValue] - 5)];
	} else {
		[mplayer.pm setStartTime:-1];
	}
	
	[mplayer playMedia:path];
	
	SAFERELEASE(lastPlayedPath);
	lastPlayedPath = lastPlayedPathPre;
	lastPlayedPathPre = nil;
	
	////////////////////////////////////////////////////////////////////
	// Auto reset
	[self setPlayDisk:kPMPlayDiskNone];
	////////////////////////////////////////////////////////////////////
}

-(NSURL*) findFirstMediaFileFromSubFile:(NSString*)path
{
	// Need to get the latest value of nameRule first
	[mplayer.pm setSubNameRule:[ud integerForKey:kUDKeySubFileNameRule]];

	// Get the latest nameRule
	SUBFILE_NAMERULE nameRule = [mplayer.pm subNameRule];
	
	NSURL *mediaURL = nil;
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	// Folder path
	NSString *directoryPath = [path stringByDeletingLastPathComponent];
	// Subtitle file name
	NSString *subName = [[[path lastPathComponent] stringByDeletingPathExtension] lowercaseString];

	NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:directoryPath];

	// Iterate over the directory the playback file is in
	for (NSString *mediaFile in directoryEnumerator)
	{
		// TODO need to check here whether mediaFile is a file name or a path name
		NSDictionary *fileAttr = [directoryEnumerator fileAttributes];
		NSString *ext = [[mediaFile pathExtension] lowercaseString];
		
		if ([[fileAttr objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory]) {
			//don't recurse into subdirectories
			[directoryEnumerator skipDescendants];

		} else if ([[fileAttr objectForKey:NSFileType] isEqualToString: NSFileTypeRegular] &&
					([[[AppController sharedAppController] playableFormats] containsObject:ext])) {
			// If it's a normal file, and it's a media file
			NSString *mediaName = [[mediaFile stringByDeletingPathExtension] lowercaseString];
			
			switch (nameRule) {
				case kSubFileNameRuleExactMatch:
					if (![mediaName isEqualToString:subName]) continue; // exact match
					break;
				case kSubFileNameRuleAny:
					break; // any sub file is OK
				case kSubFileNameRuleContain:
					if ([subName rangeOfString: mediaName].location == NSNotFound) continue; // contain the movieName
					break;
				default:
					continue;
					break;				
			}
			// Reaching here means a suitable playback file was found, break out of the loop
			mediaURL = [[NSURL fileURLWithPath:[directoryPath stringByAppendingPathComponent:mediaFile] isDirectory:NO] retain];
			break;
		}
	}
	[pool drain];
	return [mediaURL autorelease];
}

-(void) setMultiThreadMode:(BOOL) mt
{
	NSString *resPath = [[NSBundle mainBundle] resourcePath];
	
	NSString *mplayerName;
	unsigned int threadNum;
	
	if (/*mt*/0) {
		// use multi-threading
		threadNum = MIN(kThreadsNumMax, MAX(1,[ud integerForKey:kUDKeyThreadNum]));
		mplayerName = kMPCMplayerNameMT;
	} else {
		threadNum = MIN(kThreadsNumMax, MAX(1,[ud integerForKey:kUDKeyThreadNum]));
		mplayerName = kMPCMplayerName;
	}

	[ud setInteger:threadNum forKey:kUDKeyThreadNum];
	
    // temp hack for 1.0.10
    // the threads larger than 4 will bring out-of-sync
    // so limit it here to 4 and do not influence UI and Preference.
    if (threadNum > 4) {
        threadNum = 4;
    }
	[mplayer.pm setThreads: threadNum];
	
	[mplayer setMpPathPair: [NSDictionary dictionaryWithObjectsAndKeys:
							 [resPath stringByAppendingPathComponent:[NSString stringWithFormat:kMPCFMTMplayerPathM32, mplayerName]], kI386Key,
							 [resPath stringByAppendingPathComponent:[NSString stringWithFormat:kMPCFMTMplayerPathX64, mplayerName]], kX86_64Key,
							 [resPath stringByAppendingPathComponent:[NSString stringWithFormat:kMPCFMTMplayerPathArm64, mplayerName]], kArm64Key,
							 nil]];
}

////////////////////////////////////////////////cooperative actions with UI//////////////////////////////////////////////////
-(void) stop
{
	[mplayer performStop];
	// Once the window is closed, clear lastPlayPath so that even reopening the window won't play the previous file
	SAFERELEASE(lastPlayedPath);	
}

-(void) togglePlayPause
{
	if (mplayer.state == kMPCStoppedState) {
		//mplayer is not in the playing state
		if (lastPlayedPath) {
			// There is a file available to play
			[self playMedia:lastPlayedPath];
		}
	} else {
		// mplayer is currently playing
		[mplayer togglePause];
		
		if (mplayer.state == kMPCPausedState) {
			[self enablePowerSave:YES];
		} else if (mplayer.state == kMPCPlayingState) {
			[self enablePowerSave:NO];
		}
	}
}

-(void) frameStep
{
	[mplayer frameStep:1];
}

-(BOOL) toggleMute
{
	if (PlayerCouldAcceptCommand && (![self isPassingThrough])) {
		return [mplayer setMute:!mplayer.movieInfo.playingInfo.mute];
	} else {
		return NO;
	}
}

-(float) setVolume:(float) vol
{
	if ([self isPassingThrough]) {
		// if is passing through, do nothing
		// and return the current volume
		vol = mplayer.pm.volume;
	} else {
		vol = [mplayer setVolume:vol];
		[mplayer.pm setVolume:vol];
	}
	return vol;
}

-(BOOL) isPassingThrough
{
	BOOL ret = NO;
	if (PlayerCouldAcceptCommand) {
		AudioInfo *ai = [mplayer.movieInfo audioInfoForID:[mplayer.movieInfo.playingInfo currentAudioID]];
		if (ai) {
			NSString *format = [[ai format] uppercaseString];
			MPLog(@"audio format:%@", format);
			if ((([format isEqualToString:@"0X2000"] || [format isEqualToString:@"AC-3"]) && [mplayer.pm ac3Pass]) ||
				(([format isEqualToString:@"0X2001"] || [format isEqualToString:@"DTS"]) && [mplayer.pm dtsPass])) {
				ret = YES;
			}
		}
	}
	return ret;
}

-(float) seekTo:(float)time mode:(SEEK_MODE)seekMode
{
	// playingInfo's currentTime is synced by reading the log, so it's not set directly here
	if (PlayerCouldAcceptCommand && mplayer.movieInfo.seekable) {
		if (seekMode == kMPCSeekModeRelative) {
			time -= [mplayer.movieInfo.playingInfo.currentTime floatValue];
		}
		
		time = [mplayer setTimePos:time mode:seekMode];
		[mplayer.la stop];
		return time;
	}
	return -1;
}

-(float) changeTimeBy:(float) delta
{
	// playingInfo's currentTime is synced by reading the log, so it's not set directly here
	if (PlayerCouldAcceptCommand && mplayer.movieInfo.seekable) {
		delta = [mplayer setTimePos:delta mode:kMPCSeekModeRelative];
		[mplayer.la stop];
		return delta;
	}
	return -1;
}

-(float) changeSpeedBy:(float) delta
{
	if (PlayerCouldAcceptCommand) {
		[mplayer setSpeed:[mplayer.movieInfo.playingInfo.speed floatValue] + delta];
	}
	return [mplayer.movieInfo.playingInfo.speed floatValue];
}

-(float) changeSubDelayBy:(float) delta
{
	if (PlayerCouldAcceptCommand) {
		[mplayer setSubDelay:[mplayer.movieInfo.playingInfo.subDelay floatValue] + delta];
	}
	return [mplayer.movieInfo.playingInfo.subDelay floatValue];
}

-(float) changeAudioDelayBy:(float) delta
{
	if (PlayerCouldAcceptCommand) {
		[mplayer setAudioDelay:[mplayer.movieInfo.playingInfo.audioDelay floatValue] + delta];
	}
	return [mplayer.movieInfo.playingInfo.audioDelay floatValue];	
}

-(float) changeSubScaleBy:(float) delta
{
	if (PlayerCouldAcceptCommand) {
		[mplayer setSubScale: [mplayer.movieInfo.playingInfo.subScale floatValue] + delta];
	}
	return [mplayer.movieInfo.playingInfo.subScale floatValue];
}

-(float) changeSubPosBy:(float)delta
{
	if (PlayerCouldAcceptCommand) {
		[mplayer setSubPos: mplayer.movieInfo.playingInfo.subPos + delta*100];
	}
	return mplayer.movieInfo.playingInfo.subPos;
}

-(float) changeAudioBalanceBy:(float)delta
{
	if (PlayerCouldAcceptCommand) {
		[mplayer setBalance:mplayer.movieInfo.playingInfo.audioBalance + delta];
	}
	return mplayer.movieInfo.playingInfo.audioBalance;
}

-(float) setSpeed:(float) spd
{
	if (PlayerCouldAcceptCommand) {
		[mplayer setSpeed:spd];
	}
	return [mplayer.movieInfo.playingInfo.speed floatValue];
}

-(float) setSubDelay:(float) sd
{
	if (PlayerCouldAcceptCommand) {
		[mplayer setSubDelay:sd];
	}
	return [mplayer.movieInfo.playingInfo.subDelay floatValue];	
}

-(float) setAudioDelay:(float) ad
{
	if (PlayerCouldAcceptCommand) {
		[mplayer setAudioDelay:ad];
	}
	return [mplayer.movieInfo.playingInfo.audioDelay floatValue];	
}

-(void) setSubtitle:(int) subID
{
	[mplayer setSub:subID];
}

-(void) setAudio:(int) audioID
{
	[mplayer setAudio:audioID];
}

-(void) setAudioBalance:(float)bal
{
	[mplayer setBalance:bal];
}

-(void) setVideo:(int) videoID
{
	[mplayer setVideo:videoID];
}

-(void) loadSubFile:(NSString*)subPath
{
	[mplayer loadSubFile:subPath];
}

-(void) setLetterBox:(BOOL) renderSubInLB top:(float) topRatio bottom:(float)bottomRatio
{
	if (PlayerCouldAcceptCommand) {
		[mplayer setLetterBox:renderSubInLB top:topRatio bottom:bottomRatio];
	}
}

-(void) setEqualizer:(NSArray*) amps
{
	if (PlayerCouldAcceptCommand) {
		[mplayer setEqualizer:amps];
	}
	[mplayer.pm setEqualizer:amps];
}

-(void) mapAudioChannelsTo:(NSInteger)mode
{
	if (PlayerCouldAcceptCommand) {
		[mplayer mapAudioChannelsTo:mode];
	}
}

-(void) setExternalAudioFilePath:(NSString*)path
{
	[mplayer.pm setAudioFilePath:path];
}
//////////////////////////////////////private methods////////////////////////////////////////////////////
-(NSString*) preferredMPlayerArchKey
{
	// The keys are tried in order and the first one whose binary is actually
	// present in the bundle wins. Compile-time detection is enough here: the
	// app ships as a universal binary, so the arm64 slice only ever runs on
	// Apple Silicon and the x86_64 slice only on Intel (or under Rosetta,
	// where an x86_64 mplayer is the right choice anyway).
	NSArray *candidates;

#if defined(__arm64__)
	// Native first, then the Intel build as a Rosetta fallback.
	candidates = [NSArray arrayWithObjects:kArm64Key, kX86_64Key, nil];
#else
	// 32bit mplayer only remains usable on macOS 10.14 and earlier.
	candidates = ([ud boolForKey:kUDKeyPrefer64bitMPlayer]) ?
				 [NSArray arrayWithObjects:kX86_64Key, kI386Key, nil] :
				 [NSArray arrayWithObjects:kI386Key, kX86_64Key, nil];
#endif

	NSFileManager *fm = [NSFileManager defaultManager];
	NSDictionary *pathPair = [mplayer mpPathPair];

	for (NSString *key in candidates) {
		NSString *path = [pathPair objectForKey:key];

		if (path && [fm isExecutableFileAtPath:path]) {
			return key;
		}
	}

	// Nothing usable was found; return the preferred key anyway so that the
	// failure surfaces as a normal playback error instead of a silent no-op.
	return [candidates objectAtIndex:0];
}

-(NSSet*) supportedOptionsOfMPlayerAtPath:(NSString*)path
{
	// MPlayerX was developed against a privately patched mplayer that
	// understood a handful of options upstream never had (-nodispclog,
	// -stpause, -subid). Passing one of those to a stock mplayer makes it
	// refuse to start, so ask the binary what it accepts and let
	// ParameterManager leave out anything it does not.
	//
	// Returning nil means "assume everything is supported", which reproduces
	// the behaviour MPlayerX had before this check existed.
	if (!path || ![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
		return nil;
	}

	NSTask *task = [[[NSTask alloc] init] autorelease];
	NSPipe *pipe = [NSPipe pipe];
	NSData *output = nil;

	[task setLaunchPath:path];
	[task setArguments:[NSArray arrayWithObject:@"-list-options"]];
	[task setStandardOutput:pipe];
	[task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
	[task setStandardInput:[NSFileHandle fileHandleWithNullDevice]];

	@try {
		[task launch];
		output = [[pipe fileHandleForReading] readDataToEndOfFile];
		[task waitUntilExit];
	}
	@catch (NSException *e) {
		MPLog(@"could not query mplayer options: %@", e);
		return nil;
	}

	if (!output || ![output length]) {
		return nil;
	}

	NSString *text = [[[NSString alloc] initWithData:output
											encoding:NSUTF8StringEncoding] autorelease];
	if (!text) {
		return nil;
	}

	NSMutableSet *opts = [NSMutableSet set];
	NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];

	for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
		// Every option line starts with whitespace, then the option name.
		// Anything else is a banner or a table header.
		if ([line length] == 0 || ![ws characterIsMember:[line characterAtIndex:0]]) {
			continue;
		}

		NSString *name = [[line stringByTrimmingCharactersInSet:ws]
						  componentsSeparatedByCharactersInSet:ws].firstObject;

		// Suboption groups are listed as "name:suboption"; keep the group name.
		name = [[name componentsSeparatedByString:@":"] objectAtIndex:0];
		// Options taking a list are listed with a trailing '*'.
		if ([name hasSuffix:@"*"]) {
			name = [name substringToIndex:[name length] - 1];
		}

		if ([name length]) {
			[opts addObject:name];
		}
	}

	// A parse that found almost nothing means the output was not what we
	// expected; do not start dropping options on the strength of that.
	if ([opts count] < 50) {
		MPLog(@"unexpected -list-options output (%lu entries); not filtering",
			  (unsigned long)[opts count]);
		return nil;
	}

	return opts;
}

///////////////////////////////////////MPlayer Notifications/////////////////////////////////////////////
-(void) playbackOpened:(id)coreController
{
	// When the mplayer in use has no -stpause, the process starts playing and
	// is paused here instead. Upstream mplayer has never had a start-paused
	// option; only MPlayerX's own build did.
	if (mplayer.pm.pauseAtStart && ![mplayer.pm supportsStartPausedOption]) {
		[mplayer togglePause];
	}

	// according to the apn state
	if (autoPlayState == kMPCAutoPlayStateJustFound) {
		autoPlayState = kMPCAutoPlayStatePlaying;
	} else {
		autoPlayState = kMPCAutoPlayStateInvalid;
	}
	
	// Use the file name to look up whether there is a previous playback record
	NSNumber *stopTime = [[[AppController sharedAppController] bookmarks] objectForKey:[lastPlayedPathPre absoluteString]];
	NSDictionary *dict;

	if (stopTime) {
		dict = [NSDictionary dictionaryWithObjectsAndKeys:
				lastPlayedPathPre, kMPCPlayOpenedURLKey, 
				stopTime, kMPCPlayLastStoppedTimeKey,
				nil];
	} else {
		dict = [NSDictionary dictionaryWithObjectsAndKeys: lastPlayedPathPre, kMPCPlayOpenedURLKey, nil];		
	}

	// disable the powersave
	// when in auto play next, this function will be called multiple times
	// but it is OK, calling this function multiple times won't lead errors
	[self enablePowerSave:NO];
	
	[notifCenter postNotificationName:kMPCPlayOpenedNotification object:self userInfo:dict];
}

-(void) playbackStarted:(id)coreController
{
	[notifCenter postNotificationName:kMPCPlayStartedNotification object:self 
							 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
									   [NSNumber numberWithBool:([mplayer.movieInfo.videoInfo count] == 0)], kMPCPlayStartedAudioOnlyKey,
									   nil]];

	MPLog(@"vc:%lu, ac:%lu", [mplayer.movieInfo.videoInfo count], [mplayer.movieInfo.audioInfo count]);
}

-(void) playbackWillStop:(id)coreController
{
	[notifCenter postNotificationName:kMPCPlayWillStopNotification object:self userInfo:nil];
}

-(void) playbackStopped:(id)coreController info:(NSDictionary*)dict
{	
	BOOL stoppedByForce = [[dict objectForKey:kMPCPlayStoppedByForceKey] boolValue];

	[notifCenter postNotificationName:kMPCPlayStoppedNotification object:self userInfo:nil];

	if (![ud boolForKey:kUDKeyDisableLastStopBookmark]) {
		// if not disable bookmark completely
		if (stoppedByForce) {
			// If it was a forced stop
			// Use the file name as the key, and record this file's playback time
			[[[AppController sharedAppController] bookmarks] setObject:[dict objectForKey:kMPCPlayStoppedTimeKey] forKey:[lastPlayedPath absoluteString]];
		} else {
			// Stopped naturally
			// Remove the playback time recorded under this file's key
			[[[AppController sharedAppController] bookmarks] removeObjectForKey:[lastPlayedPath absoluteString]];
		}
	}
	
	if ([ud boolForKey:kUDKeyAutoPlayNext] && [lastPlayedPath isFileURL] && (!stoppedByForce)) {
		//If it wasn't a forced close
		//If it's not a local file, this is guaranteed to return nil
		NSString *nextPath = 
			[PlayListController SearchNextMoviePathFrom:[lastPlayedPath path] 
											  inFormats:[[AppController sharedAppController] playableFormats]];
		
		if (nextPath != nil) {			
			autoPlayState = kMPCAutoPlayStateJustFound;
			
			[self loadFiles:[NSArray arrayWithObject:nextPath] fromLocal:YES];
			
			return;
		}
	}

	if ([[PlayListController sharedPlayListController] consumeRequestingNextOrPrev]) {
		// If this is a next/prev signal issued by the playlist, then pretend it's AutoPlayNextJustFound
		// This way some necessary parameters can be preserved
		autoPlayState = kMPCAutoPlayStateJustFound;
	} else {
		MPLog(@"Finalize");
		
		autoPlayState = kMPCAutoPlayStateInvalid;
	
		[self enablePowerSave:YES];
		
		[notifCenter postNotificationName:kMPCPlayFinalizedNotification object:self userInfo:nil];
		
		if ([ud boolForKey:kUDKeyQuitOnClose] && (!stoppedByForce) && [ud boolForKey:kUDKeyCloseWindowWhenStopped]) {
			[NSApp terminate:nil];
		}	
	}
}

-(void) playbackError:(id)coreController
{
	autoPlayState = kMPCAutoPlayStateInvalid;
}
/////////////////////////////////SubConverter Delegate methods/////////////////////////////////////
-(NSString*) subConverter:(SubConverter*)subConv detectedFile:(NSString*)path ofCharsetName:(NSString*)charsetName confidence:(float)confidence
{
	// When the confidence is above the threshold, directly return the passed-in charsetName
	NSString *ret = charsetName;

	if (confidence <= [ud floatForKey:kUDKeyTextSubtitleCharsetConfidenceThresh]) {
		// When the confidence is below the threshold
		CFStringEncoding ce;

		if ([ud boolForKey:kUDKeyTextSubtitleCharsetManual]) {
			// If it's manually specified
			ce = [charsetController askForSubEncodingForFile:path charsetName:charsetName confidence:confidence];
		} else {
			// If it's an automatic fallback
			ce = [ud integerForKey:kUDKeyTextSubtitleCharsetFallback];
		}
		ret = (NSString*)CFStringConvertEncodingToIANACharSetName(ce);
	}
	return ret;
}
@end
