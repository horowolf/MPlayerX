/*
 * MPlayerX - PlayListController.m
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

#import "PlayListController.h"
#import "PlayerController.h"
#import "CocoaAppendix.h"
#import "AppController.h"
#import "LocalizedStrings.h"

NSArray* findDigitParts(NSString *name)
{
	unichar ch;
	NSRange range;
	NSMutableArray *ret = [[NSMutableArray alloc] initWithCapacity:5];;
	
	range.location = [name length];
	range.length = 0;
	
	// string length greater than 0
	while(range.location--) {
		// get the current char
		ch = [name characterAtIndex:range.location];
		
		if ((ch>='0')&&(ch<='9')) {
			// is a digit
			range.length++;
		} else if (range.length > 0) {
			// not a digit, and a digit has already been found
			[ret addObject:[NSValue valueWithRange:NSMakeRange(range.location+1, range.length)]];
			range.length = 0;
		}
	}
	if (range.length > 0) {
		[ret addObject:[NSValue valueWithRange:NSMakeRange(0, range.length)]];
	}
	return [ret autorelease];
}

NSArray* enumerateAllFilesAt(NSString *dirPath, NSSet *exts)
{
	NSMutableArray *ret = nil;

	NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:dirPath];
	
	for (NSString *file in directoryEnumerator) {
		// enum the folder
		NSDictionary *fileAttr = [directoryEnumerator fileAttributes];
		
		if ([[fileAttr objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory]) {
			// skip all sub-folders
			[directoryEnumerator skipDescendants];
			
		} else if ([[fileAttr objectForKey:NSFileType] isEqualToString: NSFileTypeRegular] &&
				   ((exts && [exts containsObject:[[file pathExtension] lowercaseString]]) || (!exts))) {
			// the normal file and the file extension is OK
			// or if exts is nil, don't care the extensions
			if (!ret) {
				// lazy load
				ret = [[NSMutableArray alloc] initWithCapacity:20];
			}
			[ret addObject:file];
		}
	}
	return [ret autorelease];
}

BOOL isTimesOfTen(NSInteger num)
{
	if ((num == 10) || (num == 0) || (num == -10)) {
		return YES;
	} else if ((num % 10) == 0) {
		return isTimesOfTen(num / 10);
	} else {
		return NO;
	}
}

NSString* getFirstDigitPart(NSString *str)
{
	NSString *ret = nil;
	NSInteger i, len = [str length];
	unichar ch;
	
	for(i = 0;i < len; i++) {
		ch = [str characterAtIndex:i];
		
		if (!((ch>='0')&&(ch<='9'))) {
			break;
		}
	}
	if (i != 0) {
		ret = [[str substringToIndex:i] retain];
	}
	return [ret autorelease];
}

// implement the singleton pattern
static PlayListController *sharedInstance = nil;
static BOOL init_ed = NO;

@implementation PlayListController

@synthesize requestingNextOrPrev;

+(PlayListController*) sharedPlayListController
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
		
		requestingNextOrPrev = NO;
	}
	return self;
}

+(id) allocWithZone:(NSZone *)zone { return [[self sharedPlayListController] retain]; }
-(id) copyWithZone:(NSZone*)zone { return self; }
-(id) retain { return self; }
-(NSUInteger) retainCount { return NSUIntegerMax; }
-(oneway void) release { }
-(id) autorelease { return self; }

-(BOOL) consumeRequestingNextOrPrev
{
	BOOL requesting = requestingNextOrPrev;
	requestingNextOrPrev = NO;
	return requesting;
}

-(void) dealloc
{
	sharedInstance = nil;
	
	[super dealloc];
}

-(IBAction) playNext:(id)sender
{
	// MPLog(@"Play next");
	
	NSURL *lastURL = [playerController lastPlayedPath];
	
	if (lastURL) {
		if ([lastURL isFileURL]) {
			NSString *nextPath = [PlayListController SearchNextMoviePathFrom:[lastURL path]
																   inFormats:[[AppController sharedAppController] playableFormats]];
			if (nextPath) {
				// requestingNextOrPrev is consumed (and reset) by PlayerController's
				// playbackStopped: once the old mplayer task's termination delegate call
				// actually arrives -- that callback isn't guaranteed to happen synchronously
				// within -stop, so resetting the flag here right after -loadFiles: returns
				// could race ahead of it and cause the window to get resized as if this were
				// a fresh open instead of a continuous-play switch.
				requestingNextOrPrev = YES;
				[playerController stop];
				[playerController loadFiles:[NSArray arrayWithObject:nextPath] fromLocal:YES];
			} else {
				[self showAlertPanelModal:kMPXStringCantFindNextEpisode];
			}
		} else {
			[self showAlertPanelModal:kMPXStringNextPrevOnlySupportLocalMedia];
		}
	}
}

-(IBAction) playPrevious:(id)sender
{
	// MPLog(@"Play prev");
	
	NSURL *lastURL = [playerController lastPlayedPath];
	
	if (lastURL) {
		if ([lastURL isFileURL]) {
			NSString *nextPath = [PlayListController SearchPreviousMoviePathFrom:[lastURL path]
																	   inFormats:[[AppController sharedAppController] playableFormats]];
			if (nextPath) {
				// see the comment in -playNext: about why the reset happens in
				// -[PlayerController playbackStopped:] instead of here
				requestingNextOrPrev = YES;
				[playerController stop];
				[playerController loadFiles:[NSArray arrayWithObject:nextPath] fromLocal:YES];
			} else {
				[self showAlertPanelModal:kMPXStringCantFindPrevEpisode];
			}		
		} else {
			[self showAlertPanelModal:kMPXStringNextPrevOnlySupportLocalMedia];
		}
	}
}

+ (NSString*) SearchPreviousMoviePathFrom:(NSString*)path inFormats:(NSSet*)exts
{
	NSString *nextPath = nil;

	if (path) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		NSArray *filesCandidates = nil;
		NSRange digitRange, lastRange;
		NSString *idxNext, *fileNamePrefix = nil, *idxNextTemp;
		BOOL isTen;
		NSInteger i = 0, idxNow, digitLast; //, nonFuzzySuffixPos = 0; //;
		// get the file name, without the extension
		NSString *movieName = [[path lastPathComponent] stringByDeletingPathExtension];
		// directory path
		NSString *dirPath = [path stringByDeletingLastPathComponent];
		// find the index where the digits start
		NSArray *digitRangeArray = findDigitParts(movieName);
		
		lastRange.length = 0;
		lastRange.location = NSNotFound;
		
		for (NSValue *val in digitRangeArray) {
			// get the current digit segment
			digitRange = [val rangeValue];
			
			// get the current numeric value
			idxNow = [[movieName substringWithRange:digitRange] integerValue];
			
			if (idxNow > 1) {
				// the numeric value must be greater than 1
				idxNext = [NSString stringWithFormat:@"%d", (int)(idxNow - 1)];

				NSUInteger idxNextLen = [idxNext length];
					// subtraction doesn't hold here, 10 - 1 = 9 or 09
				if (isTimesOfTen(idxNow)) {
					// if it's an integer power of 10
					++idxNextLen;
					isTen = YES;
				} else {
					isTen = NO;
				}
				
					// if this index's length is shorter than the previous one, that means there's padding
				if (idxNextLen < digitRange.length) {
						// has padding
					digitRange.location += (digitRange.length-idxNextLen);
					digitRange.length = idxNextLen;
				}

				if ((lastRange.length > 0) && ([[movieName substringWithRange:lastRange] integerValue] == 1)) {
					// if it's not the last field
					// and the previous field is 1, that means we've reached the first episode of a season, need to find the last episode of the previous season
					
						// get the list of all files
					if (!filesCandidates) {
						// lazy load
						filesCandidates = enumerateAllFilesAt(dirPath, exts);
					}
					
					NSInteger maxNum = 0;
					NSString *digitMax;
					
					for (i = 0; i < 2; ++i) {
						if (i == 1) {
							if (isTen) {
								// if it's a power of 10, also need to probe the possibility of 099
								idxNextTemp = [NSString stringWithFormat:@"0%@", idxNext];
							} else {
								continue;
							}
						} else {
							idxNextTemp = idxNext;
						}
						
						// if there was a previous field
						digitLast = digitRange.location + digitRange.length;
						fileNamePrefix = [NSString stringWithFormat:@"%@%@%@", 
										  [movieName substringToIndex:digitRange.location],
										  idxNextTemp,
										  [movieName substringWithRange:NSMakeRange(digitLast, lastRange.location-digitLast)]];

						MPLog(@"0: %@", fileNamePrefix);

						NSRange rng;
						for (NSString *name in filesCandidates) {
							// search not including the digit, for now
							rng = [name rangeOfString:fileNamePrefix options:NSCaseInsensitiveSearch|NSAnchoredSearch];
							
							if (rng.length != 0) {
								// found the name
									// get the lastDigit string
								digitMax = getFirstDigitPart([name substringFromIndex:rng.length + rng.location]);
								
									// if greater than the max value, then
								if ([digitMax integerValue] > maxNum) {
									maxNum = [digitMax integerValue];
									if (nextPath) {
										[nextPath release];
										nextPath = nil;
									}
									nextPath = [[dirPath stringByAppendingPathComponent:name] retain];
								}
							}
						}
						// after iterating through all files
						if (nextPath) {
							goto ExitLoopPrev;
						}
					}
				} else {
					for (i = 0; i < 2; ++i) {
						if (i == 1) {
							if (isTen) {
								// if it's a power of 10, also need to probe the possibility of 099
								idxNextTemp = [NSString stringWithFormat:@"0%@", idxNext];
							} else {
								continue;
							}
						} else {
							idxNextTemp = idxNext;
						}
						// if it's not 1, it might be a meaningless field, or just an ordinary episode
						// or the last field
						fileNamePrefix = [[movieName substringToIndex:digitRange.location] stringByAppendingString:idxNextTemp];
						
						MPLog(@"1: %@", fileNamePrefix);

						// fuzzy matching
						if (!filesCandidates) {
							// lazy load
							filesCandidates = enumerateAllFilesAt(dirPath, exts);
						}
							
						NSRange rng;
						for (NSString *name in filesCandidates) {
							rng = [name rangeOfString:fileNamePrefix options:NSCaseInsensitiveSearch|NSAnchoredSearch];
							if (rng.length != 0) {
								// found the name
								nextPath = [[dirPath stringByAppendingPathComponent:name] retain];
								goto ExitLoopPrev;
							}
						}
					}
				}
			}
			lastRange = digitRange;
		}
ExitLoopPrev:
		[pool drain];
	}
	return [nextPath autorelease];
}

+(NSString*) SearchNextMoviePathFrom:(NSString*)path inFormats:(NSSet*)exts
{
	NSString *nextPath = nil;
	
	if (path) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		NSArray *filesCandidates = nil;
		NSRange digitRange, lastRange;
		NSString *idxNext, *fileNamePrefix = nil;
		NSInteger i = 0, digitLast; //, nonFuzzySuffixPos = 0;
		// get the file name, without the extension
		NSString *movieName = [[path lastPathComponent] stringByDeletingPathExtension];
		// directory path
		NSString *dirPath = [path stringByDeletingLastPathComponent];
		// find the index where the digits start
		NSArray *digitRangeArray = findDigitParts(movieName);
		
		// initialize the previous field
		lastRange.length = 0;
		lastRange.location = NSNotFound;
		
		for (NSValue *val in digitRangeArray) {
			// get the range of the field
			digitRange = [val rangeValue];

			// get the index of the next file to play
			idxNext = [NSString stringWithFormat:@"%d", (int)([[movieName substringWithRange:digitRange] integerValue] + 1)];

			NSUInteger idxNextLen = [idxNext length];
			// if this index's length is shorter than the previous one, that means there's padding
			if (idxNextLen < digitRange.length) {
				digitRange.location += (digitRange.length-idxNextLen);
				digitRange.length = idxNextLen;
			}
			
			for (i = 0; i < 3; ++i) {
				switch (i) {
					case 0:
						// match the with the padding 0001
						if (lastRange.length > 1) {
							digitLast = digitRange.location+digitRange.length;
							NSString *fmt = [NSString stringWithFormat:@"%%@%%@%%@%%0%dd",(int)lastRange.length];
							fileNamePrefix = [NSString stringWithFormat:fmt,
											  [movieName substringToIndex:digitRange.location],
											  idxNext,
											  [movieName substringWithRange:NSMakeRange(digitLast, lastRange.location-digitLast)],
											  1];
							// nonFuzzySuffixPos = lastRange.location + lastRange.length;
							MPLog(@"%@", fileNamePrefix);
						} else {
							continue;
						}
						break;
					case 1:
						// match the un padding 1
						if (lastRange.length > 0) {
							digitLast = digitRange.location+digitRange.length;
							
							fileNamePrefix = [NSString stringWithFormat:@"%@%@%@1",
											  [movieName substringToIndex:digitRange.location],
											  idxNext,
											  [movieName substringWithRange:NSMakeRange(digitLast, lastRange.location-digitLast)]];
							// nonFuzzySuffixPos = lastRange.location + lastRange.length;
							MPLog(@"%@", fileNamePrefix);
						} else {
							continue;
						}
						break;
					default:
						// match the increment +1
						
						fileNamePrefix = [[movieName substringToIndex:digitRange.location] stringByAppendingString:idxNext];
						
						MPLog(@"%@", fileNamePrefix);
						break;
				}
				// fuzzy matching
				if (!filesCandidates) {
					// lazy load
					filesCandidates = enumerateAllFilesAt(dirPath, exts);
				}

				NSRange rng;
				for (NSString *name in filesCandidates) {
					rng = [name rangeOfString:fileNamePrefix options:NSCaseInsensitiveSearch|NSAnchoredSearch];
					if (rng.length != 0) {
						// found the name
						nextPath = [[dirPath stringByAppendingPathComponent:name] retain];
						goto ExitLoop;
					}
				}		
			}
			lastRange = digitRange;
		}
ExitLoop:
		[pool drain];
	}	
	return [nextPath autorelease];
}
@end