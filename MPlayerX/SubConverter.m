/*
 * MPlayerX - SubConverter.m
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

#import "SubConverter.h"
#import "UniversalDetector.h"

NSString * const kWorkDirSubDir = @"Subs";

@implementation SubConverter

@synthesize delegate;
 
-(id) init
{
	self = [super init];
	
	if (self) {
		delegate = nil;
		textSubFileExts = [[NSSet alloc] initWithObjects:@"utf", @"utf8", @"srt", @"ass", @"smi", @"txt", @"ssa", @"smil", @"jss", @"rt", nil];
		workDirectory = nil;
		detector = [[UniversalDetector alloc] init];
		[detector reset];
	}
	return self;
}

-(void) dealloc
{
	[textSubFileExts release];
	[workDirectory release];

	@synchronized (detector) { [detector release]; }

	[super dealloc];
}

-(void) clearWorkDirectory
{
	if (workDirectory) {
		[[NSFileManager defaultManager] removeItemAtPath:[workDirectory stringByAppendingPathComponent:kWorkDirSubDir] error:NULL];
	}
}

-(void) setWorkDirectory:(NSString *)wd
{
	[self clearWorkDirectory];

	[wd retain];
	[workDirectory release];
	workDirectory = wd;
}

-(NSString*) getCPOfTextSubtitle:(NSString*)path
{
	BOOL isDir = YES;
	NSString *cpStr = nil;	
	
	if (path && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && (!isDir) &&
		[textSubFileExts containsObject:[[path pathExtension] lowercaseString]]) {

		@synchronized(detector) {
			[detector analyzeContentsOfFile:path];
			cpStr = [detector MIMECharset];
			
			if (delegate) {
				NSString *cpPrefer = [delegate subConverter:self detectedFile:path ofCharsetName:cpStr confidence:[detector confidence]];
				if (cpPrefer && (cpPrefer != cpStr)) {
					cpStr = cpPrefer;
				}
			}
			[cpStr retain];
			[detector reset];
		}
	}
	return [cpStr autorelease];
}

-(NSArray*) convertTextSubsAndEncodings:(NSDictionary*)subEncDict
{
	if (!workDirectory) {
		return nil;
	}
	
	NSString *subDir = [workDirectory stringByAppendingPathComponent:kWorkDirSubDir];
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir = NO;
	
	if ([fm fileExistsAtPath:subDir isDirectory:&isDir] && (!isDir)) {
		// If it exists but is not a directory, remove the file first
		[fm removeItemAtPath:subDir error:NULL];
	}

	if (!isDir) {
		// If the directory did not exist originally, or a file existed there instead, the directory needs to be (re)created
		if (![fm createDirectoryAtPath:subDir withIntermediateDirectories:YES attributes:nil error:NULL]) {
			return nil;
		}
	}

	NSMutableArray *newSubs = [[NSMutableArray alloc] initWithCapacity:4];
	NSString *subPathOld, *enc, *subFileOld, *subPathNew, *ext, *prefix;
	NSUInteger idx;
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	for (subPathOld in subEncDict) {
		// Get the file's encoding
		enc = [subEncDict objectForKey:subPathOld];
		
		if (enc) {
			// If we could get the encoding string, first convert it to the CF format
			CFStringEncoding ce = CFStringConvertIANACharSetNameToEncoding((CFStringRef)enc);
			
			if (ce != kCFStringEncodingInvalidId) {
				// First get the file path under workDir based on the original file name
				subPathNew = [subDir stringByAppendingPathComponent:
							  [[subPathOld lastPathComponent] stringByReplacingOccurrencesOfString:@"," withString:@"_"]];
				
				// Since name collisions are possible, find a suitable file name here
				isDir = YES;
				idx = 0;
				ext = nil;
				prefix = nil;
				
				// Since name collisions are possible, find a file name that doesn't already exist
				while([fm fileExistsAtPath:subPathNew isDirectory:&isDir] && (!isDir)) {
					if (ext == nil) {
						ext = [subPathNew pathExtension];
					}
					if (prefix == nil) {
						prefix = [subPathNew stringByDeletingPathExtension];
					}
					// If this file exists, look for the next file name that doesn't
					subPathNew = [prefix stringByAppendingFormat:@".mpx.%d.%@", (int)(idx++), ext];
				}
				
				// CP949 apparently always falls back to EUC_KR; map it back to CP949 (kCFStringEncodingDOSKorean) here
				if ((ce == kCFStringEncodingMacKorean) || (ce == kCFStringEncodingEUC_KR)) {
					ce = kCFStringEncodingDOSKorean;
				}
				
				// Transcode if it's valid
				NSStringEncoding ne = CFStringConvertEncodingToNSStringEncoding(ce);
				
				subFileOld = [NSString stringWithContentsOfFile:subPathOld encoding:ne error:NULL];
				
				if (!subFileOld) {
					// If opening failed, the specified encoding might be problematic
					if (ce == kCFStringEncodingBig5) {
						// If it's Big5, try HKSCS as well
						ne = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5_HKSCS_1999);
						subFileOld = [NSString stringWithContentsOfFile:subPathOld encoding:ne error:NULL];
					} else {
					}
				}
				
				if (subFileOld) {
					// Successfully read the file
					// Since UCD can also guess wrong, just copy the file directly in that case
					if ([subFileOld writeToFile:subPathNew atomically:NO encoding:NSUTF8StringEncoding error:NULL]) {
						// If the write succeeded
						// If it didn't succeed, try copying the file directly instead
						[newSubs addObject:subPathNew];
						continue;
					}
				}
			}
		}
	}
	[pool drain];
	
	return [newSubs autorelease];
}

-(NSDictionary*) getCPFromMoviePath:(NSString*)moviePath nameRule:(SUBFILE_NAMERULE)nameRule alsoFindVobSub:(NSString**)vobPath
{
	NSString *cpStr = nil;
	NSString *subPath = nil;
	NSMutableDictionary *subEncDict = [[NSMutableDictionary alloc] initWithCapacity:2];

	if (vobPath) {
		*vobPath = nil;
	}

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// Directory path
	NSString *directoryPath = [moviePath stringByDeletingLastPathComponent];
	// Name of the file being played
	NSString *movieName = [[[moviePath lastPathComponent] stringByDeletingPathExtension] lowercaseString];
	
	NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:directoryPath];
	
	// Enumerate the directory containing the file being played
	for (NSString *path in directoryEnumerator)
	{
		// the lower case of the sub path
		NSString *caseName = [[path stringByDeletingPathExtension] lowercaseString];

		NSDictionary *fileAttr = [directoryEnumerator fileAttributes];
		
		if ([[fileAttr objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory]) {
			// Don't descend into subdirectories
			[directoryEnumerator skipDescendants];
			
		} else if ([[fileAttr objectForKey:NSFileType] isEqualToString: NSFileTypeRegular]) {
			// If it's a regular file
			switch (nameRule) {
				case kSubFileNameRuleExactMatch:
					if (![movieName isEqualToString:caseName]) continue; // exact match
					break;
				case kSubFileNameRuleAny:
					break; // any sub file is OK
				case kSubFileNameRuleContain:
					if ([caseName rangeOfString: movieName].location == NSNotFound) continue; // contain the movieName
					break;
				default:
					continue;
					break;
			}
			
			subPath = [directoryPath stringByAppendingPathComponent:path];

			NSString *ext = [[path pathExtension] lowercaseString];
			
			if ([textSubFileExts containsObject: ext]) {
				// If it's a text subtitle file
				@synchronized (detector) {
					[detector analyzeContentsOfFile: subPath];
					
					cpStr = [detector MIMECharset];

					if (delegate) {
						NSString *cpPrefer = [delegate subConverter:self detectedFile:subPath ofCharsetName:cpStr confidence:[detector confidence]];
						if (cpPrefer && (cpPrefer != cpStr)) {
							cpStr = cpPrefer;
						}
					}
					if (cpStr) {
						[subEncDict setObject:cpStr forKey:subPath];
					}
					[detector reset];					
				}
			} else if (vobPath && [ext isEqualToString:@"sub"]) {
				// If it's a vobsub and we're set to look for vobsub
				[*vobPath release];
				*vobPath = [subPath retain];
			}
		}
	}
	[pool drain];

	if (vobPath && (*vobPath)) {
		[*vobPath autorelease];
	}

	return [subEncDict autorelease];	
}

@end
