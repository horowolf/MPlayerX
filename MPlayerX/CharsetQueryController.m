/*
 * MPlayerX - CharsetQueryController.m
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

#import "CharsetQueryController.h"
#import "CocoaAppendix.h"
#import "UserDefaults.h"
#import "LocalizedStrings.h"

@implementation CharsetQueryController

+(void) initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:
	 [NSDictionary dictionaryWithObjectsAndKeys:
	  [NSNumber numberWithFloat:0.8], kUDKeyTextSubtitleCharsetConfidenceThresh,
	  [NSNumber numberWithBool:YES], kUDKeyTextSubtitleCharsetManual,
	  [NSNumber numberWithInteger:kCFStringEncodingInvalidId], kUDKeyTextSubtitleCharsetFallback,
	  nil]];
}

-(id) init
{
	self = [super init];
	
	if (self) {
		nibLoaded = NO;
	}
	return self;
}

-(CFStringEncoding) askForSubEncodingForFile:(NSString*)path charsetName:(NSString*)charsetName confidence:(float)conf
{
	if (!nibLoaded) {
		[NSBundle loadNibNamed:@"SubEncoding" owner:self];
		
		[[charsetListPopup menu] removeAllItems];
		[[charsetListPopup menu] appendCharsetList];
		
		nibLoaded = YES;
	}
	
	// prepare the hint text
	[outputText setStringValue:[NSString stringWithFormat:kMPXStringSubEncQueryResult, [path lastPathComponent], charsetName, conf*100.0]];
	
	CFStringEncoding ce = (charsetName)?(CFStringConvertIANACharSetNameToEncoding((CFStringRef)charsetName)):(kCFStringEncodingInvalidId);
	
	if (ce != kCFStringEncodingInvalidId) {
		// if the charset's return value is valid
		NSMenuItem *item = [[charsetListPopup menu] itemWithTag:ce];
		
		if (item) {
			// if the corresponding item can be found in the menu, select it
			[charsetListPopup selectItem:item];
		}
	}
	return [NSApp runModalForWindow:encodingWindow];
}

-(IBAction) confirmed:(id)sender
{
	// return the Encoding value
	[NSApp stopModalWithCode:[[charsetListPopup selectedItem] tag]];
	[encodingWindow orderOut:self];
}

-(IBAction) canceled:(id)sender
{
	// return invalid Encoding value
	[NSApp stopModalWithCode:kCFStringEncodingInvalidId];
	[encodingWindow orderOut:self];
}

@end
